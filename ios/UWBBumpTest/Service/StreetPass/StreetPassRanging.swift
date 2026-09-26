import Foundation
import NearbyInteraction

/// UWB ranging for StreetPass peers. Same lifecycle discipline as
/// RangingService (one NISession per peer, capability checked at runtime,
/// pause/resume across backgrounding, stale-measurement expiry), kept as its
/// own class with its own cap so StreetPass never contends with the
/// active-bump pipeline's RangingService.maxConcurrentPeers ceiling.
@MainActor
final class StreetPassRanging: NSObject, ObservableObject {

    struct Measurement: Equatable {
        let peerID: String
        let distance: Double?      // metres; nil means UNKNOWN, never 0
        let at: Date
        var age: TimeInterval { Date().timeIntervalSince(at) }
    }

    @Published private(set) var isSupported = false
    @Published private(set) var measurements: [String: Measurement] = [:]
    var config = StreetPassConfig()

    var onMeasurement: ((_ peerID: String, _ distance: Double) -> Void)?
    var onLog: ((String) -> Void)?

    private var sessions: [String: NISession] = [:]
    private var peerForSession: [ObjectIdentifier: String] = [:]
    private var peerTokens: [String: NIDiscoveryToken] = [:]
    private var staleTimer: Timer?

    override init() {
        super.init()
        isSupported = NISession.deviceCapabilities.supportsPreciseDistanceMeasurement
    }

    @discardableResult
    func prepareSession(for peerID: String) -> Data? {
        guard isSupported else { return nil }
        guard sessions.count < config.maxConcurrentPeers || sessions[peerID] != nil else {
            log("StreetPass at the \(config.maxConcurrentPeers)-peer ranging limit; not ranging \(peerID)")
            return nil
        }
        let session = sessions[peerID] ?? makeSession(for: peerID)
        guard let token = session.discoveryToken else { return nil }
        return try? NSKeyedArchiver.archivedData(withRootObject: token, requiringSecureCoding: true)
    }

    private func makeSession(for peerID: String) -> NISession {
        let session = NISession()
        session.delegate = self
        session.delegateQueue = .main
        sessions[peerID] = session
        peerForSession[ObjectIdentifier(session)] = peerID
        startStaleTimer()
        return session
    }

    func acceptToken(_ data: Data, from peerID: String) {
        guard isSupported,
              let token = try? NSKeyedUnarchiver.unarchivedObject(ofClass: NIDiscoveryToken.self, from: data)
        else {
            log("StreetPass could not decode token from \(peerID)")
            return
        }
        peerTokens[peerID] = token
        let session = sessions[peerID] ?? makeSession(for: peerID)
        session.run(NINearbyPeerConfiguration(peerToken: token))
        log("StreetPass ranging \(peerID)")
    }

    func endSession(for peerID: String) {
        if let session = sessions.removeValue(forKey: peerID) {
            peerForSession[ObjectIdentifier(session)] = nil
            session.invalidate()
        }
        peerTokens[peerID] = nil
        measurements[peerID] = nil
        if sessions.isEmpty { stopStaleTimer() }
    }

    func stopAll() {
        sessions.values.forEach { $0.invalidate() }
        sessions.removeAll(); peerForSession.removeAll()
        peerTokens.removeAll(); measurements.removeAll()
        stopStaleTimer()
    }

    func pauseAll() {
        sessions.values.forEach { $0.pause() }
        measurements.removeAll()
    }

    func resumeAll() {
        for (peerID, session) in sessions {
            guard let token = peerTokens[peerID] else { continue }
            session.run(NINearbyPeerConfiguration(peerToken: token))
        }
    }

    private func startStaleTimer() {
        guard staleTimer == nil else { return }
        staleTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.expireStale() }
        }
    }

    private func stopStaleTimer() { staleTimer?.invalidate(); staleTimer = nil }

    private func expireStale() {
        measurements = measurements.filter { $0.value.age <= config.measurementFreshness }
    }

    private func log(_ s: String) { onLog?(s) }
}

// MARK: - NISessionDelegate

extension StreetPassRanging: NISessionDelegate {

    nonisolated func session(_ session: NISession, didUpdate nearbyObjects: [NINearbyObject]) {
        Task { @MainActor in
            guard let peerID = self.peerForSession[ObjectIdentifier(session)],
                  let object = nearbyObjects.first else { return }
            let distance = object.distance.map(Double.init)
            self.measurements[peerID] = Measurement(peerID: peerID, distance: distance, at: Date())
            if let distance { self.onMeasurement?(peerID, distance) }
        }
    }

    nonisolated func session(_ session: NISession, didRemove nearbyObjects: [NINearbyObject],
                             reason: NINearbyObject.RemovalReason) {
        Task { @MainActor in
            guard let peerID = self.peerForSession[ObjectIdentifier(session)] else { return }
            self.measurements[peerID] = nil
            switch reason {
            case .peerEnded:
                self.endSession(for: peerID)
            case .timeout:
                if let token = self.peerTokens[peerID] { session.run(NINearbyPeerConfiguration(peerToken: token)) }
            @unknown default: break
            }
        }
    }

    nonisolated func sessionWasSuspended(_ session: NISession) {
        Task { @MainActor in
            guard let peerID = self.peerForSession[ObjectIdentifier(session)] else { return }
            self.measurements[peerID] = nil
        }
    }

    nonisolated func sessionSuspensionEnded(_ session: NISession) {
        Task { @MainActor in
            guard let peerID = self.peerForSession[ObjectIdentifier(session)],
                  let token = self.peerTokens[peerID] else { return }
            session.run(NINearbyPeerConfiguration(peerToken: token))
        }
    }

    nonisolated func session(_ session: NISession, didInvalidateWith error: Error) {
        Task { @MainActor in
            if let peerID = self.peerForSession[ObjectIdentifier(session)] {
                self.measurements[peerID] = nil
                self.sessions[peerID] = nil
                self.peerTokens[peerID] = nil
            }
            self.peerForSession[ObjectIdentifier(session)] = nil
        }
    }
}
