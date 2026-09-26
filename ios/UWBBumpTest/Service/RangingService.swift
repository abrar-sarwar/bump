import Foundation
import NearbyInteraction
import simd

/// UWB ranging, evolved from the working spike in `uwb-ios`.
///
/// One `NISession` per peer, each bound to that peer's discovery token, so a
/// measurement is always attributed to the right person. Sessions are bounded:
/// we do not attempt to range a whole event at once.
@MainActor
final class RangingService: NSObject, ObservableObject {

    /// Practical cap on simultaneous ranging sessions. Nearby Interaction does
    /// not publish a hard number and it varies by hardware, so we keep this
    /// small and document it rather than pretending a room of 50 can be ranged.
    static let maxConcurrentPeers = 4

    struct Measurement: Equatable {
        let peerID: String
        let distance: Double?      // metres; nil means UNKNOWN, never 0
        let direction: simd_float3?
        let at: Date
        var age: TimeInterval { Date().timeIntervalSince(at) }
    }

    struct Config: Equatable {
        /// Distance below this counts as an experimental proximity trigger. It is
        /// NOT proof the phones touched.
        var proximityThreshold: Double = 0.15
        /// A measurement older than this is stale and must not be shown or used.
        var freshness: TimeInterval = 1.5
    }

    @Published private(set) var isSupported = false
    @Published private(set) var supportsDirection = false
    @Published private(set) var unsupportedReason: String?
    @Published private(set) var measurements: [String: Measurement] = [:]
    @Published private(set) var permissionDenied = false
    @Published var config = Config()

    /// Per-peer session state, for diagnostics. Never contains token bytes.
    enum SessionState: Equatable {
        case awaitingPeerToken      // our session exists, we have not got theirs
        case running                // run() called with their token
        case measuring              // at least one callback since the last run()
        case suspended
        case timedOut
        case ended(String)
    }
    @Published private(set) var sessionStates: [String: SessionState] = [:]
    @Published private(set) var callbackCounts: [String: Int] = [:]
    @Published private(set) var lastCallbackAt: [String: Date] = [:]

    /// A session was invalidated for a reason other than permission. The owner
    /// decides whether the peer is still connected and a fresh token exchange
    /// is worth doing; the old tokens are gone either way.
    var onSessionInvalidated: ((_ peerID: String) -> Void)?

    /// Called with a fresh, correctly attributed distance for a peer.
    var onMeasurement: ((_ peerID: String, _ distance: Double) -> Void)?
    var onLog: ((String) -> Void)?
    /// Our own token became available (or was replaced) and must be re-sent.
    var onLocalToken: ((_ peerID: String, _ token: Data) -> Void)?

    private var sessions: [String: NISession] = [:]
    /// Maps an NISession back to the peer it belongs to, so a delegate callback
    /// can never be attributed to the wrong person.
    private var peerForSession: [ObjectIdentifier: String] = [:]
    private var peerTokens: [String: NIDiscoveryToken] = [:]
    /// The archived form of each peer's current token, used to recognise a
    /// re-delivery of the same token. Comparing bytes avoids relying on
    /// NIDiscoveryToken equality semantics.
    private var peerTokenData: [String: Data] = [:]
    private var staleTimer: Timer?

    override init() {
        super.init()
        checkSupport()
    }

    /// Runtime capability is the only authority. "iPhone 11 or newer" does not
    /// guarantee UWB: several models in that range ship without a U1/U2 chip,
    /// and availability varies by region. The Simulator never supports it.
    private func checkSupport() {
        let caps = NISession.deviceCapabilities
        isSupported = caps.supportsPreciseDistanceMeasurement
        // Distance support does NOT imply direction support.
        supportsDirection = caps.supportsDirectionMeasurement
        if !isSupported {
            unsupportedReason = "This iPhone doesn't have the ultra-wideband chip BUMP uses for extra accuracy. Motion-only matching still works."
        }
    }

    // MARK: Sessions

    /// Begin (or restart) a session for `peerID` and hand back our token for it.
    @discardableResult
    func prepareSession(for peerID: String) -> Data? {
        guard isSupported else { return nil }
        guard sessions.count < Self.maxConcurrentPeers || sessions[peerID] != nil else {
            log("at the \(Self.maxConcurrentPeers)-peer ranging limit; not ranging \(peerID)")
            return nil
        }
        let session = sessions[peerID] ?? makeSession(for: peerID)
        guard let token = session.discoveryToken else {
            log("no local discovery token for \(peerID) yet")
            return nil
        }
        do {
            // Apple's supported archiving path for NIDiscoveryToken.
            return try NSKeyedArchiver.archivedData(withRootObject: token, requiringSecureCoding: true)
        } catch {
            log("could not archive local token: \(error.localizedDescription)")
            return nil
        }
    }

    private func makeSession(for peerID: String) -> NISession {
        let session = NISession()
        session.delegate = self
        session.delegateQueue = .main
        sessions[peerID] = session
        peerForSession[ObjectIdentifier(session)] = peerID
        setState(.awaitingPeerToken, for: peerID, reason: "session created")
        startStaleTimer()
        return session
    }

    /// Accept a peer's token and start ranging them.
    ///
    /// Returns true when the token is NEW (first one, or the peer recreated its
    /// session), which is exactly when the peer needs our token back. A
    /// re-delivery of the token we already run with is ignored and returns
    /// false. This used to reciprocate unconditionally, so the two phones
    /// bounced tokens back and forth forever and each bounce re-ran the
    /// configuration, restarting ranging before it could settle.
    @discardableResult
    func acceptToken(_ data: Data, from peerID: String) -> Bool {
        guard isSupported else { return false }
        if peerTokenData[peerID] == data, sessions[peerID] != nil {
            return false
        }
        guard let token = try? NSKeyedUnarchiver.unarchivedObject(ofClass: NIDiscoveryToken.self, from: data) else {
            log("could not decode token from \(peerID)")
            return false
        }
        peerTokens[peerID] = token
        peerTokenData[peerID] = data
        let session = sessions[peerID] ?? makeSession(for: peerID)
        session.run(NINearbyPeerConfiguration(peerToken: token))
        setState(.running, for: peerID, reason: "received peer token")
        return true
    }

    private func setState(_ state: SessionState, for peerID: String, reason: String) {
        let old = sessionStates[peerID]
        guard old != state else { return }
        sessionStates[peerID] = state
        log("[uwb] \(peerID): \(old.map { "\($0)" } ?? "none") -> \(state) (\(reason))")
    }

    func endSession(for peerID: String) {
        if let session = sessions.removeValue(forKey: peerID) {
            peerForSession[ObjectIdentifier(session)] = nil
            session.invalidate()
        }
        peerTokens[peerID] = nil
        peerTokenData[peerID] = nil
        measurements[peerID] = nil
        sessionStates[peerID] = nil
        if sessions.isEmpty { stopStaleTimer() }
    }

    func stopAll() {
        sessions.values.forEach { $0.invalidate() }
        sessions.removeAll(); peerForSession.removeAll()
        peerTokens.removeAll(); peerTokenData.removeAll(); measurements.removeAll()
        sessionStates.removeAll()
        stopStaleTimer()
    }

    /// Foreground-only: suspend when backgrounded and clear stale values rather
    /// than leaving a frozen number on screen.
    func pauseAll() {
        sessions.values.forEach { $0.pause() }
        measurements.removeAll()
        log("ranging paused (app left the foreground)")
    }

    func resumeAll() {
        for (peerID, session) in sessions {
            guard let token = peerTokens[peerID] else { continue }
            session.run(NINearbyPeerConfiguration(peerToken: token))
        }
        if !sessions.isEmpty { log("ranging resumed") }
    }

    /// Fresh measurement for a peer, or nil if we don't have one.
    func freshMeasurement(for peerID: String) -> Measurement? {
        guard let m = measurements[peerID], m.age <= config.freshness, m.distance != nil else { return nil }
        return m
    }

    // MARK: Staleness

    private func startStaleTimer() {
        guard staleTimer == nil else { return }
        staleTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.expireStale() }
        }
    }

    private func stopStaleTimer() { staleTimer?.invalidate(); staleTimer = nil }

    private func expireStale() {
        let before = measurements.count
        measurements = measurements.filter { $0.value.age <= config.freshness }
        if measurements.count != before { log("cleared stale measurement(s)") }
    }

    private func log(_ s: String) { onLog?(s) }
}

// MARK: - NISessionDelegate

extension RangingService: NISessionDelegate {

    nonisolated func session(_ session: NISession, didUpdate nearbyObjects: [NINearbyObject]) {
        Task { @MainActor in
            // Attribute strictly by the session this update came from.
            guard let peerID = self.peerForSession[ObjectIdentifier(session)],
                  let object = nearbyObjects.first else { return }
            let distance = object.distance.map(Double.init)
            self.callbackCounts[peerID, default: 0] += 1
            self.lastCallbackAt[peerID] = Date()
            self.setState(.measuring, for: peerID, reason: "first callback")
            self.measurements[peerID] = Measurement(
                peerID: peerID,
                distance: distance,                 // nil stays nil; never 0
                direction: object.direction,        // direction is optional and not required
                at: Date()
            )
            if let distance { self.onMeasurement?(peerID, distance) }
        }
    }

    nonisolated func session(_ session: NISession, didRemove nearbyObjects: [NINearbyObject],
                             reason: NINearbyObject.RemovalReason) {
        Task { @MainActor in
            guard let peerID = self.peerForSession[ObjectIdentifier(session)] else { return }
            self.measurements[peerID] = nil
            self.setState(.timedOut, for: peerID, reason: "object removed")
            switch reason {
            case .peerEnded:
                self.log("\(peerID) ended their ranging session")
                self.endSession(for: peerID)
            case .timeout:
                self.log("ranging timed out for \(peerID), retrying")
                // Recoverable: re-run with the token we still hold.
                if let token = self.peerTokens[peerID] {
                    session.run(NINearbyPeerConfiguration(peerToken: token))
                    self.setState(.running, for: peerID, reason: "re-run after timeout")
                }
            @unknown default:
                self.log("\(peerID) removed from ranging")
            }
        }
    }

    nonisolated func sessionWasSuspended(_ session: NISession) {
        Task { @MainActor in
            guard let peerID = self.peerForSession[ObjectIdentifier(session)] else { return }
            self.measurements[peerID] = nil
            self.setState(.suspended, for: peerID, reason: "system suspended the session")
        }
    }

    nonisolated func sessionSuspensionEnded(_ session: NISession) {
        Task { @MainActor in
            guard let peerID = self.peerForSession[ObjectIdentifier(session)],
                  let token = self.peerTokens[peerID] else { return }
            // Apple requires re-running the configuration after suspension.
            session.run(NINearbyPeerConfiguration(peerToken: token))
            self.setState(.running, for: peerID, reason: "suspension ended")
        }
    }

    nonisolated func session(_ session: NISession, didInvalidateWith error: Error) {
        Task { @MainActor in
            let peerID = self.peerForSession[ObjectIdentifier(session)]
            if let peerID {
                self.measurements[peerID] = nil
                self.sessions[peerID] = nil
                self.peerTokens[peerID] = nil
                self.peerTokenData[peerID] = nil
                self.setState(.ended(error.localizedDescription), for: peerID, reason: "invalidated")
            }
            self.peerForSession[ObjectIdentifier(session)] = nil

            if let niError = error as? NIError, niError.code == .userDidNotAllow {
                self.permissionDenied = true
                self.log("Nearby Interaction permission denied")
            } else {
                self.log("ranging session ended: \(error.localizedDescription)")
                // An invalidated session and its tokens are dead. The owner
                // decides whether a fresh exchange is warranted (bounded there).
                if let peerID { self.onSessionInvalidated?(peerID) }
            }
        }
    }
}
