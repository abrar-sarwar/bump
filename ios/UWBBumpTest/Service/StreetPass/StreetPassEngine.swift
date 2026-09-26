import Foundation
import SwiftUI

/// Orchestrates the StreetPass ambient-encounter pipeline: transport
/// discovery -> UWB ranging -> per-peer encounter gate -> mutual-interest
/// teaser -> in-app sheet, or (only if backgrounded at that instant) a local
/// notification. Every real decision lives in StreetPassEncounterGate and
/// InterestMatcher; this class only wires them together. Foreground-only:
/// ranging pauses the moment the app leaves .active, mirroring what
/// BumpEngine.handleScenePhase actually does, while the transport connection
/// and each peer's encounter-gate (cooldown/latch) state are preserved — they
/// only truly reset on a real peer disconnect or process termination, so a
/// transient interruption can't double-trigger a peer already in range.
/// Nothing here is persisted.
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
        // Without these two, every log(...) inside the transport and the
        // ranging service would call a nil closure and vanish — including the
        // ones that report a dropped frame or a refused peer.
        transport.onLog = { [weak self] line in self?.log(line) }
        ranging.onLog = { [weak self] line in self?.log(line) }
    }

    /// Diagnostics sink for both StreetPass services. Debug console only — no
    /// UI surface and nothing retained in memory (a StreetPass Testing-tools
    /// panel is explicitly out of scope for this iteration).
    private func log(_ text: String) {
        #if DEBUG
        print("StreetPass: \(text)")
        #endif
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
            guard isActive else { return }
            ranging.pauseAll()
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
        case .hello(var profile):
            // A StreetPass peer is an unauthenticated stranger, less trusted
            // than a confirmed partner — so apply at least the same discipline
            // BumpEngine applies to a partner's `.profile`: drop an avatar that
            // isn't a decodable image or is oversized, and bound the name.
            profile.avatarThumbnail = ProfilePhoto.sanitized(profile.avatarThumbnail)
            profile.displayName = String(profile.displayName.trimmed().prefix(24))
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
        let teaser = StreetPassEncounter.teaser(mine: store.profile.interests, theirs: profile.interests)
        let encounter = StreetPassEncounter(id: peer, displayName: profile.displayName,
                                            avatarThumbnail: profile.avatarThumbnail,
                                            mutualInterestStatement: teaser.statement,
                                            teasedMutualStatements: teaser.teased)
        pendingEncounter = encounter
        // Only the narrow app-not-active window gets a system notification —
        // while foregrounded, setting pendingEncounter above is enough to
        // show the custom sheet; no redundant banner.
        if !isAppActive {
            StreetPassNotifier.notify(encounter)
        }
    }

    private func myPeerProfile() -> StreetPassPeerProfile {
        // Never the full profile photo: base64'd into the envelope it would
        // blow past StreetPassWire.maxFrame and the whole .hello would be
        // dropped, so the peer would never learn who we are.
        let thumbnail = store.profile.photo.flatMap { ProfilePhoto.prepareThumbnail($0) }
        return StreetPassPeerProfile(id: transport.myID, displayName: store.profile.displayName,
                                     avatarThumbnail: thumbnail,
                                     interests: store.profile.interests)
    }

    #if DEBUG
    /// DEBUG-only: pose a pending encounter for simulator screenshots and
    /// previews. Never called on a real run; see `DemoMode`.
    func applyDemo(encounter: StreetPassEncounter) {
        pendingEncounter = encounter
    }
    #endif
}
