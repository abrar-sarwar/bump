import Foundation
import SwiftUI

/// Orchestrates the StreetPass ambient-encounter pipeline: transport
/// discovery -> UWB ranging -> per-peer encounter gate -> mutual-interest
/// teaser -> in-app sheet, or (only if backgrounded at that instant) a local
/// notification. Every real decision lives in StreetPassEncounterGate and
/// InterestMatcher; this class only wires them together. Foreground-only —
/// stops and clears all state the moment the app leaves .active, mirroring
/// BumpEngine's own scene-phase policy. Nothing here is persisted.
@MainActor
final class StreetPassEngine: ObservableObject {

    @Published private(set) var pendingEncounter: StreetPassEncounter?

    let transport = StreetPassTransport()
    let ranging = StreetPassRanging()

    private let store: Store
    private let config = StreetPassConfig()
    private var gates: [String: StreetPassEncounterGate] = [:]
    private var peerProfiles: [String: StreetPassPeerProfile] = [:]
    private var isActive = false
    private var isAppActive = true

    init(store: Store) {
        self.store = store
        transport.config = config
        ranging.config = config
        wireUp()
    }

    private func wireUp() {
        transport.onPeerJoined = { [weak self] peer in self?.peerJoined(peer) }
        transport.onPeerLeft = { [weak self] peer in self?.peerLeft(peer) }
        transport.onMessage = { [weak self] from, envelope in self?.handle(envelope.body, from: from) }
        ranging.onMeasurement = { [weak self] peer, distance in self?.handleMeasurement(peer, distance) }
    }

    func start() {
        guard !isActive, store.profile.isComplete else { return }
        isActive = true
        transport.start(displayName: store.profile.displayName)
        StreetPassNotifier.requestAuthorizationIfNeeded()
    }

    func stop() {
        guard isActive else { return }
        isActive = false
        transport.stop()
        ranging.stopAll()
        gates.removeAll()
        peerProfiles.removeAll()
        pendingEncounter = nil
    }

    func handleScenePhase(_ scenePhase: ScenePhase) {
        switch scenePhase {
        case .active:
            isAppActive = true
            guard store.profile.isComplete else { return }
            if !isActive { start() } else { ranging.resumeAll() }
        case .background, .inactive:
            isAppActive = false
            stop()
        @unknown default: break
        }
    }

    func dismissPendingEncounter() {
        pendingEncounter = nil
    }

    // MARK: Wiring

    private func peerJoined(_ peer: String) {
        transport.send(.hello(profile: myPeerProfile()), to: peer)
        if let token = ranging.prepareSession(for: peer) {
            transport.send(.discoveryToken(token), to: peer)
        }
    }

    private func peerLeft(_ peer: String) {
        ranging.endSession(for: peer)
        gates[peer] = nil
        peerProfiles[peer] = nil
        if pendingEncounter?.id == peer { pendingEncounter = nil }
    }

    private func handle(_ body: StreetPassWire.Body, from peer: String) {
        switch body {
        case .hello(let profile):
            peerProfiles[peer] = profile
        case .discoveryToken(let data):
            ranging.acceptToken(data, from: peer)
        }
    }

    private func handleMeasurement(_ peer: String, _ distance: Double) {
        var gate = gates[peer] ?? StreetPassEncounterGate(
            proximityThreshold: config.proximityThreshold,
            consecutiveReadingsRequired: config.consecutiveReadingsRequired,
            exitHysteresisMargin: config.exitHysteresisMargin,
            cooldown: config.cooldown)
        let verdict = gate.feed(distance: distance, now: ProcessInfo.processInfo.systemUptime)
        gates[peer] = gate

        guard verdict == .qualified, let profile = peerProfiles[peer] else { return }
        let mutual = InterestMatcher.overlap(store.profile.interests, profile.interests, limit: 1).first
        let encounter = StreetPassEncounter(id: peer, displayName: profile.displayName,
                                            avatarThumbnail: profile.avatarThumbnail,
                                            mutualInterestStatement: mutual?.statement)
        pendingEncounter = encounter
        // Only the narrow app-not-active window gets a system notification —
        // while foregrounded, setting pendingEncounter above is enough to
        // show the custom sheet; no redundant banner.
        if !isAppActive {
            StreetPassNotifier.notify(encounter)
        }
    }

    private func myPeerProfile() -> StreetPassPeerProfile {
        StreetPassPeerProfile(id: transport.myID, displayName: store.profile.displayName,
                              avatarThumbnail: store.profile.photo,
                              interests: store.profile.interests)
    }
}
