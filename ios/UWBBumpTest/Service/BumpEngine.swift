import Combine
import Foundation
import SwiftUI

/// Orchestrates the whole bump journey: motion → coordinator matching → mutual
/// confirmation → partner-only profile exchange → insight.
///
/// Explicit state machine. There is no indefinite spinner and no generic
/// "something went wrong" — every terminal state carries a reason and a way out.
@MainActor
final class BumpEngine: ObservableObject {

    // MARK: State

    enum Phase: Equatable {
        case notReady
        case preparing
        case ready
        case checking                       // we felt a bump, waiting on the coordinator
        case confirming(Proposal)           // "did you bump with X?"
        case waitingForPartner              // we confirmed, they haven't
        case exchanging                     // both confirmed, swapping profiles
        case connected(Result)
        case timedOut
        case ambiguous(Int)                 // several people bumped at once
        case needsRetry(String)
        case unavailable(String)

        var isBusy: Bool {
            switch self {
            case .preparing, .checking, .waitingForPartner, .exchanging: return true
            default: return false
            }
        }
    }

    struct Proposal: Equatable, Identifiable {
        let id: String
        let partner: Wire.Member
        let uwbCorroborated: Bool
        let manual: Bool
        var evidence: SavedConnection.PairingEvidence {
            if manual { return .manualSelection }
            return uwbCorroborated ? .motionAndUWB : .motionOnly
        }
    }

    struct Result: Equatable {
        let partner: SharedProfile
        let insight: ConnectionInsight
        let evidence: SavedConnection.PairingEvidence
        let roomName: String
        let metOn: Date
    }

    enum RoomState: Equatable {
        case none
        case hosting(code: String)
        case joined(code: String)
        case hostLost(code: String)

        var code: String? {
            switch self {
            case .none: return nil
            case .hosting(let c), .joined(let c), .hostLost(let c): return c
            }
        }
    }

    @Published private(set) var phase: Phase = .notReady {
        didSet {
            guard phase != oldValue else { return }
            transition("phase", Self.describe(oldValue), Self.describe(phase), proposal: myProposal?.id)
            scheduleRearmIfResting()
            syncPresentation()
        }
    }

    /// Short labels for logs. Never includes profile content.
    nonisolated static func describe(_ phase: Phase) -> String {
        switch phase {
        case .notReady: return "notReady"
        case .preparing: return "preparing"
        case .ready: return "ready"
        case .checking: return "checking"
        case .confirming(let p): return "confirming(\(p.id.prefix(8)))"
        case .waitingForPartner: return "waitingForPartner"
        case .exchanging: return "exchanging"
        case .connected: return "connected"
        case .timedOut: return "timedOut"
        case .ambiguous(let n): return "ambiguous(\(n))"
        case .needsRetry(let why): return "needsRetry(\(why))"
        case .unavailable(let why): return "unavailable(\(why))"
        }
    }
    @Published private(set) var room: RoomState = .none
    @Published private(set) var members: [Wire.Member] = [] {
        didSet {
            if members.count != oldValue.count { syncPresentation() }
            recordStreetpasses()
        }
    }
    @Published private(set) var capacityNote: String?
    @Published private(set) var log: [LogLine] = []

    struct LogLine: Identifiable, Equatable {
        let id = UUID()
        let at: Date
        let text: String
    }

    // MARK: Collaborators

    /// Owns the Live Activity for the whole session, not for a screen.
    let liveActivity = LiveActivityController()
    let motion = MotionDetector()
    let ranging = RangingService()
    let transport = PeerTransport()
    private let store: Store

    /// Coordinator-only pairing state.
    private var matcher = PairingMatcher()
    private var resolveTimer: Timer?
    private var proposals: [String: LiveProposal] = [:]
    private var membersByID: [String: Wire.Member] = [:]
    private var aiCapable: Set<String> = []
    /// Transient peer ids already written to the streetpass log this session, so
    /// one roster rebroadcast doesn't log the same person again.
    private var streetpassLogged: Set<String> = []

    private struct LiveProposal {
        let id: String
        let a: String
        let b: String
        var confirmed: Set<String> = []
        let uwbCorroborated: Bool
        let manual: Bool
        let createdAt: Date
    }

    /// Our own side of a live proposal.
    private var myProposal: Proposal?
    /// When the proposal on screen expires. Set once, so the countdown runs
    /// down and the Live Activity content does not change on every refresh.
    private var myProposalExpiresAt: Date?
    private var partnerProfile: SharedProfile?
    private var sentProfileFor: String?
    private var iAmGenerator = false
    /// The coordinator's pick (Apple-Intelligence-aware). Overridden by the two
    /// partners only when both allowed cloud processing — see `chooseGenerator`.
    private var coordinatorPick: String?
    private var partnerCaps: Wire.PartnerCaps?
    /// Our own caps, frozen when the proposal seals. Both what we send and how we
    /// choose the generator use this snapshot, so a health check finishing
    /// mid-exchange can't make the two phones disagree.
    private var lockedCaps: Wire.PartnerCaps?
    /// The in-flight insight generation, so a newer connection can cancel it.
    private var generationTask: Task<Void, Never>?

    /// Whether this phone can currently reach a BUMP server with Grok set up.
    /// Refreshed on joining/hosting a room; only checked if cloud is allowed.
    @Published private(set) var grokReady = false
    private var healthTask: Task<Void, Never>?
    private var localSequence = 0
    /// True while the app is not on screen. Detection changes shape here: there
    /// is no accelerometer, so proximity is the only evidence available.
    @Published private(set) var isBackgrounded = false
    /// One approach gate per peer, so a measurement can only ever fire for the
    /// peer it belongs to.
    private var proximityGates: [String: ProximityGate] = [:]
    /// Checkpoint A evidence: how many real ranging callbacks arrived while the
    /// app was NOT on screen, and when the last one landed. A frozen distance or
    /// a persistent Live Activity proves nothing; these do.
    @Published private(set) var backgroundRangingCallbacks = 0
    @Published private(set) var lastBackgroundRangingAt: Date?
    @Published private(set) var lastBackgroundedAt: Date?
    private var phaseDeadline: Timer?

    /// Seconds a proposal may sit unconfirmed before it is closed.
    static let confirmationTimeout: TimeInterval = 20
    /// Seconds to wait for the partner-only profile exchange before giving up.
    static let exchangeTimeout: TimeInterval = 15

    private var cancellables = Set<AnyCancellable>()

    // MARK: Diagnostics

    /// Scene state as last reported, for the testing panel.
    @Published private(set) var lifecycle = "launching"
    /// Counters for comparing the two phones' logs after a trial.
    struct Counters: Equatable {
        var bumpsDetected = 0          // local spikes accepted as a bump
        var bumpsSuppressed = 0        // crossings swallowed by cooldown or a non-ready phase
        var bumpsSent = 0              // handed to a connected coordinator
        var bumpsNotSent = 0           // felt, but nobody to send to
        var bumpsReceived = 0          // coordinator only: events that arrived
        var outcomes = 0               // proposal / timeout / ambiguous replies received
    }
    @Published private(set) var counters = Counters()
    /// Last readiness we reported, so a change can be logged once.
    private var lastLoggedStatus: AutoStatus?
    /// Set 15 s into a room with no BUMP phone ever seen. iOS gives Multipeer no
    /// error when Local Network access is declined, so this is the only signal.
    @Published private(set) var searchStalled = false
    private var searchStallTimer: Timer?
    static let searchStallAfter: TimeInterval = 15
    /// Brings a resting outcome (timeout, rejection) back to listening, so the
    /// next encounter never needs a tap or a restart.
    private var rearmTimer: Timer?
    static let restingOutcomeDuration: TimeInterval = 4
    /// Bounded recovery of invalidated UWB sessions, per peer.
    private var uwbRecoveries: [String: Int] = [:]
    static let maxUWBRecoveries = 3
    /// Bounded deferral of "become the host" while a coordinator is in reach.
    private var hostDeferrals = 0
    static let maxHostDeferrals = 3

    init(store: Store) {
        self.store = store
        wireUp()
        applySettings()
        // A returning user has a profile already, so begin discovery now rather
        // than when some view appears. This is what makes the Local Network
        // prompt show up at launch.
        if store.profile.isComplete { autoStart() }
    }

    // MARK: Wiring

    private func wireUp() {
        motion.onSpike = { [weak self] magnitude in self?.handleLocalSpike(magnitude) }
        motion.onSuppressed = { [weak self] magnitude in
            guard let self else { return }
            self.counters.bumpsSuppressed += 1
            self.note(String(format: "[motion] crossing suppressed by %.1f s cooldown (%.1f m/s²)",
                             self.motion.config.cooldown, magnitude))
        }
        ranging.onSessionInvalidated = { [weak self] peer in self?.recoverRanging(peer) }
        transport.onCoordinatorChanged = { [weak self] id in self?.relayCoordinatorChanged(id) }
        ranging.onMeasurement = { [weak self] peer, distance in self?.handleMeasurement(peer, distance) }
        ranging.onLog = { [weak self] line in self?.note(line) }
        transport.onLog = { [weak self] line in self?.note(line) }
        transport.onMessage = { [weak self] from, envelope in self?.handle(envelope.body, from: from) }
        transport.onPeerJoined = { [weak self] peer in self?.peerJoined(peer) }
        transport.onPeerLeft = { [weak self] peer in self?.peerLeft(peer) }

        transport.$connected
            .sink { [weak self] peers in self?.rosterChanged(peers) }
            .store(in: &cancellables)

        // Start discovery as soon as the profile is usable, rather than waiting
        // for the Bump tab to render. That tab is behind onboarding and the
        // tutorial cover, so waiting for it delayed the Local Network prompt
        // until minutes into the session, sometimes until the moment someone
        // actually tried to bump. @Published replays the current value, so a
        // returning user starts at launch and a new one starts the instant
        // onboarding completes.
        store.$profile
            .map(\.isComplete)
            .removeDuplicates()
            .dropFirst()        // the launch case is handled synchronously below
            .sink { [weak self] complete in
                guard complete else { return }
                // @Published emits in willSet, so at this instant store.profile
                // is still the OLD value. autoStart reads it through
                // setupBlocker, so we let the assignment land first. One runloop
                // later is imperceptible and only affects the moment someone
                // finishes onboarding.
                Task { @MainActor [weak self] in self?.autoStart() }
            }
            .store(in: &cancellables)

        // Common ground: re-announce our topics when the choice or the
        // profile changes, and re-evaluate on every ranging update.
        Publishers.CombineLatest(store.$privacy.map(\.sharesCommonGround),
                                 store.$profile.map { InterestMatcher.topics($0.interests) })
            .removeDuplicates { $0 == $1 }
            .dropFirst()
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.announceTopics(to: self.transport.connected.map(\.id))
                    self.updateCommonGround()
                }
            }
            .store(in: &cancellables)
        ranging.$measurements
            .sink { [weak self] _ in Task { @MainActor [weak self] in self?.updateCommonGround() } }
            .store(in: &cancellables)

        // Tag new custom interests in the background (one Grok call, once).
        store.$profile
            .map { $0.interests.filter { $0.custom && $0.tags == nil }.map(\.label) }
            .removeDuplicates()
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in self?.tagInterestsIfNeeded() }
            }
            .store(in: &cancellables)

        liveActivity.onLog = { [weak self] line in self?.note(line) }
        // A crash or force quit can leave an activity behind. Adopt or clear it
        // before we start anything new, so there is only ever one.
        liveActivity.reconcileOnLaunch()

        // Confirm / Not them / Stop arrive here from the Dynamic Island. They
        // run in this process, so they act on the same authoritative state as
        // the in-app buttons.
        BumpIntentBridge.shared.handler = { [weak self] action in
            // The bridge is nonisolated, so hop explicitly and capture the
            // engine inside the hop rather than across it.
            await MainActor.run { [weak self] in self?.handleIntent(action) }
            // Return only once the new state has reached the Live Activity.
            let controller = await MainActor.run { [weak self] in self?.liveActivity }
            await controller?.flush()
        }

        transport.$discoveredRooms
            .sink { [weak self] rooms in self?.resolveDuplicateNearbyHost(rooms) }
            .store(in: &cancellables)

        // Readiness is derived from these. @Published fires in willSet, so
        // re-evaluate one hop later when the new values are in place.
        Publishers.MergeMany(
            transport.$connected.map { _ in () }.eraseToAnyPublisher(),
            transport.$joinInFlight.map { _ in () }.eraseToAnyPublisher(),
            transport.$peersSeen.map { _ in () }.eraseToAnyPublisher(),
            motion.$isRunning.map { _ in () }.eraseToAnyPublisher()
        )
        .sink { [weak self] in
            Task { @MainActor [weak self] in self?.statusInputsChanged() }
        }
        .store(in: &cancellables)
    }

    /// Push the user's testing-tools settings into the components that use them.
    func applySettings() {
        let s = store.settings
        motion.config.threshold = s.motionThreshold
        motion.config.cooldown = s.motionCooldown
        ranging.config.proximityThreshold = s.uwbProximity
        ranging.config.freshness = s.uwbFreshness
        matcher.config.window = s.pairingWindow
        matcher.config.ambiguityMargin = s.ambiguityMargin
        matcher.config.buffer = s.pairingBuffer
        matcher.config.uwbProximity = s.uwbProximity
        matcher.config.uwbFreshness = s.uwbFreshness
    }

    // MARK: Rooms

    func host(roomCode: String) {
        let code = sanitize(roomCode)
        guard !code.isEmpty else { return }
        transport.start(role: .coordinator, roomCode: code, displayName: store.profile.displayName)
        room = .hosting(code: code)
        matcher.reset()
        membersByID[transport.myID] = Wire.Member(id: transport.myID,
                                                 displayName: store.profile.displayName,
                                                 supportsUWB: ranging.isSupported)
        if ConversationService.onDeviceModelAvailable { aiCapable.insert(transport.myID) }
        startResolving()
        refreshCloudStatus()
        phase = .notReady
        armSearchStallTimer()
        note("hosting room \"\(code)\", capacity \(PeerTransport.maxPeers) phones including you")
    }

    func join(roomCode: String) {
        let code = sanitize(roomCode)
        guard !code.isEmpty else { return }
        transport.start(role: .guest, roomCode: code, displayName: store.profile.displayName)
        room = .joined(code: code)
        refreshCloudStatus()
        phase = .notReady
        armSearchStallTimer()
        note("joining room \"\(code)\"")
    }

    // MARK: Nearby (automatic room)

    /// The shared room everyone joins by default, so nobody types a code. One
    /// phone still coordinates matching (see `PairingMatcher`); which one is
    /// decided automatically.
    static let nearbyRoom = "nearby"
    /// True while the user has asked to bump with whoever is nearby.
    @Published private(set) var nearbyMode = false
    private var nearbyTimer: Timer?

    /// One tap: find the nearby room (or start it) and get ready to bump.
    ///
    /// Join first and listen for a coordinator. If nobody answers within a
    /// short, slightly random wait, become the coordinator. If two phones do
    /// that at the same moment, `resolveDuplicateNearbyHost` makes one of them
    /// step down and join the other.
    func startNearby() {
        nearbyMode = true
        let preference = store.settings.transport ?? .automatic
        guard preference != .nearby, let client = apiClient else {
            if preference == .server { return serverUnreachable("No BUMP server is set. Add one in Testing tools.") }
            joinNearbyOrHost()
            return
        }
        // Brief and bounded: "Getting ready" for at most `relayCheckTimeout`.
        note("[net] checking for the BUMP server relay at \(client.baseURL.host ?? "")")
        relayCheck?.cancel()
        relayCheck = Task { [weak self] in
            let ok = await Self.relayAvailable(client, timeout: Self.relayCheckTimeout)
            guard let self, !Task.isCancelled, self.nearbyMode, self.room == .none else { return }
            if ok {
                self.startRelayRoom(client.baseURL)
            } else if preference == .server {
                self.serverUnreachable("Can't reach the BUMP server at \(client.baseURL.host ?? "the set address"). Check it is running, then BUMP will try again.")
            } else {
                self.note("[net] server relay unavailable; using nearby (Multipeer)")
                self.joinNearbyOrHost()
            }
        }
    }

    // MARK: Server relay

    private var relayCheck: Task<Void, Never>?
    static let relayCheckTimeout: TimeInterval = 4

    nonisolated static func relayAvailable(_ client: BumpAPIClient, timeout: TimeInterval) async -> Bool {
        await withTaskGroup(of: Bool.self) { group in
            group.addTask { (try? await client.health())?.relay == true }
            group.addTask {
                try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                return false
            }
            let first = await group.next() ?? false
            group.cancelAll()
            return first
        }
    }

    private func serverUnreachable(_ why: String) {
        // Clear nearbyMode so the resting-outcome rearm can try again.
        nearbyMode = false
        note("[net] \(why)")
        phase = .needsRetry(why)
    }

    private func startRelayRoom(_ baseURL: URL) {
        transport.startRelay(baseURL: baseURL, roomCode: Self.nearbyRoom, displayName: store.profile.displayName)
        room = .joined(code: Self.nearbyRoom)
        matcher.reset()
        refreshCloudStatus()
        phase = .notReady
        armSearchStallTimer()
        setReady(true)
        note("joined \"\(Self.nearbyRoom)\" through the server relay")
    }

    /// The server names the coordinator: the earliest phone still in the room.
    /// No timers or tie-breaks, so two phones can never both host.
    private func relayCoordinatorChanged(_ coordinator: String) {
        guard transport.isRelay, let code = room.code else { return }
        if coordinator == transport.myID {
            guard case .joined = room else { return }
            room = .hosting(code: code)
            matcher.reset()
            membersByID[transport.myID] = Wire.Member(id: transport.myID,
                                                     displayName: store.profile.displayName,
                                                     supportsUWB: ranging.isSupported)
            if ConversationService.onDeviceModelAvailable { aiCapable.insert(transport.myID) }
            startResolving()
            broadcastRoster()
            note("[net] the server made this phone the coordinator")
        } else {
            if case .hosting = room {
                stopResolving()
                for id in Array(proposals.keys) { close(id, reason: "The phone coordinating changed. Bump again.") }
                room = .joined(code: code)
            }
            note("[net] coordinator is \(name(coordinator))")
            transport.send(.hello(displayName: store.profile.displayName, roomCode: code,
                                  supportsUWB: ranging.isSupported,
                                  supportsAI: ConversationService.onDeviceModelAvailable),
                           to: [coordinator])
        }
    }

    // MARK: Automatic readiness

    /// True only while the user has explicitly paused. Nothing else sets this,
    /// so backgrounding or a finished match can never leave BUMP silently off.
    @Published private(set) var isPaused = false {
        didSet { if isPaused != oldValue { syncPresentation() } }
    }

    /// What the Bump tab should show while waiting. Derived from the real state
    /// of the services rather than stored, so the label can never claim the app
    /// is ready when it isn't.
    enum AutoStatus: Equatable {
        /// Local services starting. Brief; never used for "waiting on a peer".
        case preparing
        /// In a room, no other phone connected. `hint` explains a long search.
        case lookingForPhones(hint: String?)
        /// A coordinator was found and the session is forming.
        case connecting
        /// The phone coordinating the room went away; finding a new one.
        case reconnecting
        /// Connected to at least one phone with sensing actually running.
        case listening
        case paused
        /// A specific step the person has to complete, phrased for them.
        case blocked(String)
    }

    static let relayHint = "Connected to the BUMP server, but no other phone has joined yet. Make sure BUMP is open on their phone and both phones use the same server."
    static let localNetworkHint = "No other BUMP phone found yet. Make sure BUMP is open on their phone too. If you tapped Don't Allow when iOS asked about finding devices on your local network, turn Local Network on for BUMP in Settings."

    var autoStatus: AutoStatus {
        Self.readiness(.init(
            paused: isPaused, blocker: setupBlocker, phase: phase, room: room,
            connectedPeers: transport.connected.count, joinInFlight: transport.joinInFlight,
            motionRunning: motion.isRunning, uwbOnly: store.settings.detectionMode == .uwbOnly,
            backgrounded: isBackgrounded, freshUWB: ranging.measurements.values.contains { $0.age <= ranging.config.freshness && $0.distance != nil },
            searchStalled: searchStalled, relay: transport.isRelay))
    }

    struct ReadinessInputs {
        var paused = false
        var blocker: String?
        var phase: Phase = .notReady
        var room: RoomState = .none
        var connectedPeers = 0
        var joinInFlight = false
        var motionRunning = false
        var uwbOnly = false
        var backgrounded = false
        var freshUWB = false
        var searchStalled = false
        var relay = false
    }

    /// Pure, so every combination is testable. "Ready" requires a connected
    /// peer AND a live sensing path; a start function having been called is
    /// not enough.
    nonisolated static func readiness(_ i: ReadinessInputs) -> AutoStatus {
        if i.paused { return .paused }
        if let blocker = i.blocker { return .blocked(blocker) }
        if case .unavailable(let why) = i.phase { return .blocked(why) }
        switch i.room {
        case .none: return .preparing
        case .hostLost: return .reconnecting
        case .hosting, .joined: break
        }
        if i.connectedPeers == 0 {
            if i.joinInFlight { return .connecting }
            return .lookingForPhones(hint: i.searchStalled ? (i.relay ? relayHint : localNetworkHint) : nil)
        }
        guard case .ready = i.phase else { return .preparing }
        // Backgrounded there is no accelerometer; only fresh ranging counts.
        if i.backgrounded || i.uwbOnly { return i.freshUWB ? .listening : .reconnecting }
        return i.motionRunning ? .listening : .preparing
    }

    private func statusInputsChanged() {
        if transport.peersSeen > 0 { searchStalled = false; searchStallTimer?.invalidate() }
        objectWillChange.send()
        let status = autoStatus
        if status != lastLoggedStatus {
            transition("readiness", lastLoggedStatus.map { "\($0)" } ?? "none", "\(status)",
                       reason: "peers \(transport.connected.count), motion \(motion.isRunning ? "on" : "off"), phase \(Self.describe(phase))")
            lastLoggedStatus = status
        }
        // A resting phase with motion stopped but a peer now connected (for
        // example, the first peer arriving) should start sensing.
        ensureSensing()
        syncPresentation()
    }

    /// A step that genuinely prevents a session from existing at all.
    ///
    /// Deliberately short. A missing accelerometer is NOT in here: discovery,
    /// the peer session and manual selection all still work without it, so
    /// blocking startup over it would strand the person with nothing. That case
    /// surfaces through `phase == .unavailable` once the session is up, which
    /// still reads as `.blocked` to the UI but leaves the room running.
    var setupBlocker: String? {
        if !store.profile.isComplete {
            return "Finish your profile first so the person you meet knows who you are."
        }
        // Only a genuine discovery failure blocks. `transport.lastError` must
        // NOT be used here: it is also set by routine recoverable things like a
        // send to a peer that just dropped, and a single one of those would
        // otherwise strand the app with no session and no Live Activity.
        if let why = transport.discoveryUnavailable { return why }
        return nil
    }

    /// Begin waiting for a bump. Idempotent: safe to call on every appearance of
    /// the Bump tab and on every return to the foreground, because it never
    /// opens a second session or stacks a second set of listeners.
    func autoStart() {
        guard !isPaused, setupBlocker == nil else { return }
        // Already in a room: the session stands, just make sure sensing is live.
        if room != .none { ensureSensing(); return }
        // A start is already in flight (joining, or waiting to decide the host).
        guard !nearbyMode else { return }
        note("starting automatically")
        startNearby()
    }

    /// Bring motion sensing back without touching the peer session. Only acts
    /// from a resting phase, so it can never interrupt a live proposal, an
    /// in-flight bump or the reveal.
    private func ensureSensing() {
        guard !isPaused, room != .none, !isBackgrounded else { return }
        if case .hostLost = room { return }     // the reconnect path owns this
        switch phase {
        case .notReady:
            setReady(true)
        case .ready where !motion.isRunning && store.settings.detectionMode != .uwbOnly:
            // The phase said ready while the accelerometer was off. This is
            // what stranded a phone after a system prompt: the prompt made the
            // app inactive, that stopped motion, and nothing restarted it.
            note("[motion] phase was ready with motion stopped; restarting motion")
            motion.start()
        default:
            break
        }
    }

    /// The small secondary control. Pausing keeps the peer session open and only
    /// stops detection, so resuming is instant and needs no reconnect.
    func pause() {
        guard !isPaused else { return }
        isPaused = true
        nearbyTimer?.invalidate(); nearbyTimer = nil
        motion.stop()
        if case .ready = phase { phase = .notReady }
        note("paused by the user")
    }

    func resume() {
        guard isPaused else { return }
        isPaused = false
        note("resumed by the user")
        autoStart()
    }

    /// Leave a named event room and fall back to waiting for whoever is nearby.
    func leaveEvent() {
        leaveRoom()
        nearbyMode = false
        autoStart()
    }

    /// Tear everything down and come straight back up, for the Testing tools
    /// reset. `leaveRoom` alone left `nearbyMode` set, so autoStart believed a
    /// start was in flight and the phone stayed disconnected.
    func resetAndReconnect() {
        note("reset requested; tearing down and restarting")
        stopNearby()
        applySettings()
        autoStart()
    }

    /// Stop bumping and leave the nearby room.
    func stopNearby() {
        nearbyMode = false
        nearbyTimer?.invalidate(); nearbyTimer = nil
        leaveRoom()
    }

    private func joinNearbyOrHost() {
        nearbyTimer?.invalidate()
        hostDeferrals = 0
        join(roomCode: Self.nearbyRoom)
        setReady(true)
        scheduleHostDecision()
    }

    /// Become the host if, after a jittered wait, nobody is hosting. Deferred
    /// (bounded) while a coordinator is visible or an invitation is pending:
    /// hosting at that moment restarted the transport and killed the very
    /// session that was forming, which then left two hosts to fight it out.
    private func scheduleHostDecision() {
        // Jitter breaks the tie when several phones start at once.
        let wait = 2.0 + Double.random(in: 0...1.5)
        nearbyTimer = Timer.scheduledTimer(withTimeInterval: wait, repeats: false) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.nearbyMode, case .joined = self.room,
                      self.transport.connected.isEmpty else { return }
                if self.transport.coordinatorReachable, self.hostDeferrals < Self.maxHostDeferrals {
                    self.hostDeferrals += 1
                    self.note("[net] a nearby host is in reach; waiting to join it (\(self.hostDeferrals)/\(Self.maxHostDeferrals))")
                    self.scheduleHostDecision()
                    return
                }
                self.note("nobody hosting nearby yet, so this phone will")
                self.host(roomCode: Self.nearbyRoom)
                self.setReady(true)
            }
        }
    }

    /// Two phones both started the nearby room. The one with the higher id
    /// steps down and joins the other, so everyone ends up in one room.
    private func resolveDuplicateNearbyHost(_ rooms: [String: Wire.Member]) {
        guard nearbyMode, !transport.isRelay, case .hosting(let code) = room, code == Self.nearbyRoom,
              let other = rooms[Self.nearbyRoom],
              Self.shouldYield(me: transport.myID, otherHost: other.id),
              proposals.isEmpty, myProposal == nil else { return }
        note("another phone is already hosting nearby; joining it")
        leaveRoom()
        joinNearbyOrHost()
    }

    /// Deterministic, so both hosts agree on who steps down.
    nonisolated static func shouldYield(me: String, otherHost: String) -> Bool {
        !otherHost.isEmpty && otherHost != me && otherHost < me
    }

    func leaveRoom() {
        relayCheck?.cancel(); relayCheck = nil
        rearmTimer?.invalidate(); rearmTimer = nil
        searchStallTimer?.invalidate(); searchStalled = false
        uwbRecoveries.removeAll()
        setReady(false)
        stopResolving()
        transport.stop()
        ranging.stopAll()
        matcher.reset()
        proposals.removeAll(); membersByID.removeAll(); aiCapable.removeAll()
        streetpassLogged.removeAll()
        cancelGeneration()
        myProposal = nil; partnerProfile = nil
        room = .none
        members = []
        phase = .notReady
    }

    private func armSearchStallTimer() {
        searchStallTimer?.invalidate()
        guard transport.peersSeen == 0 else { searchStalled = false; return }
        searchStallTimer = Timer.scheduledTimer(withTimeInterval: Self.searchStallAfter, repeats: false) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.room != .none, self.transport.peersSeen == 0 else { return }
                self.searchStalled = true
                self.note("[net] no BUMP phone seen in \(Int(Self.searchStallAfter)) s (Local Network access or nobody nearby)")
                self.statusInputsChanged()
            }
        }
    }

    private func sanitize(_ code: String) -> String {
        String(InterestCatalog.normalize(code).replacingOccurrences(of: " ", with: "-").prefix(20))
    }

    var isCoordinator: Bool { transport.role == .coordinator }

    // MARK: Ready

    func setReady(_ ready: Bool) {
        guard ready else {
            motion.stop()
            if case .ready = phase { phase = .notReady }
            else if case .checking = phase { phase = .notReady }
            return
        }
        guard room != .none else { return }

        phase = .preparing
        guard motion.isAvailable else {
            phase = .unavailable("This iPhone isn't reporting motion data, so BUMP can't feel a bump. You can still connect by picking someone from the room.")
            return
        }
        if store.settings.detectionMode == .uwbOnly && !ranging.isSupported {
            phase = .unavailable("UWB-only mode is selected but this iPhone has no ultra-wideband chip. Switch to Motion or Combined in Testing tools.")
            return
        }
        motion.start()
        phase = .ready
        note("ready, mode: \(store.settings.detectionMode.label)")
    }

    // MARK: Local sensing

    private func handleLocalSpike(_ magnitude: Double) {
        guard case .ready = phase else {
            counters.bumpsSuppressed += 1
            note(String(format: "[motion] spike %.1f m/s² ignored: phase %@", magnitude, Self.describe(phase)))
            return
        }
        guard store.settings.detectionMode != .uwbOnly else {
            note("[motion] spike ignored: UWB-only mode")
            return
        }
        counters.bumpsDetected += 1
        emitBump(magnitude: magnitude)
    }

    private func handleMeasurement(_ peerID: String, _ distance: Double) {
        let age = ranging.measurements[peerID]?.age ?? 0
        if isBackgrounded {
            backgroundRangingCallbacks += 1
            lastBackgroundRangingAt = Date()
        }

        // Always report close readings as evidence about WHICH peer. On its own
        // this is not a trigger in the normal foreground flow, where a
        // deliberate motion spike is the gesture.
        if distance <= store.settings.uwbProximity {
            if isCoordinator {
                matcher.record(.init(observer: transport.myID, peer: peerID,
                                     distance: distance, at: monotonic()))
            } else {
                transport.send(.proximity(peer: peerID, distance: distance), to: coordinatorIDs())
            }
        }

        // Proximity may become the trigger in two cases:
        //   - the tester picked UWB-only mode, or
        //   - we are backgrounded, where Core Motion delivers nothing at all.
        // Both are proximity detection, not proof of physical impact.
        let proximityIsTheTrigger = store.settings.detectionMode == .uwbOnly
            || (isBackgrounded && liveActivity.isRunning)
        guard proximityIsTheTrigger, case .ready = phase else { return }

        var gate = proximityGates[peerID] ?? ProximityGate(
            threshold: store.settings.uwbProximity,
            freshness: store.settings.uwbFreshness
        )
        gate.threshold = store.settings.uwbProximity
        gate.freshness = store.settings.uwbFreshness
        let verdict = gate.feed(distance: distance, age: age, now: monotonic())
        proximityGates[peerID] = gate

        if case .bump(let d) = verdict {
            note(String(format: "proximity trigger at %.2f m with %@ (%@)",
                        d, name(peerID), isBackgrounded ? "backgrounded" : "UWB-only mode"))
            emitBump(magnitude: 0)
        }
    }

    private func emitBump(magnitude: Double) {
        localSequence += 1
        // No connected phone means nobody can be matched. Say so now rather
        // than waiting 3 seconds and blaming the other person.
        guard !transport.connected.isEmpty else {
            counters.bumpsNotSent += 1
            note(String(format: "[bump] #%d felt (%.1f m/s²) but not sent: no phone connected", localSequence, magnitude))
            phase = .needsRetry("Felt that, but no other phone is connected yet, so there was nobody to match with.")
            return
        }
        phase = .checking
        armPhaseDeadline(matcher.config.timeout + 0.75) { [weak self] in
            guard let self, case .checking = self.phase else { return }
            self.phase = .timedOut
        }
        if isCoordinator {
            ingestBump(from: transport.myID)
            counters.bumpsSent += 1
            note(String(format: "[bump] #%d felt (%.1f m/s²), submitted locally as coordinator", localSequence, magnitude))
        } else if transport.send(.bumpEvent(localSequence: localSequence, magnitude: magnitude),
                                 to: coordinatorIDs()) {
            counters.bumpsSent += 1
            note(String(format: "[bump] #%d felt (%.1f m/s²), sent to coordinator", localSequence, magnitude))
        } else {
            // Never retried: a bump resent later would be matched against a
            // different moment.
            counters.bumpsNotSent += 1
            note(String(format: "[bump] #%d felt (%.1f m/s²), NOT delivered to coordinator", localSequence, magnitude))
            phase = .needsRetry("Felt that, but it could not reach the other phone. Try again.")
        }
    }

    /// The coordinator's own bumps go through the exact same pipeline as guests'.
    private func ingestBump(from participant: String) {
        let event = PairingMatcher.Event(id: UUID().uuidString, participant: participant, arrival: monotonic())
        if participant != transport.myID { counters.bumpsReceived += 1 }
        note("[match] event from \(name(participant)) at \(String(format: "%.3f", event.arrival))")
        if let rejection = matcher.submit(event) {
            note("[match] rejected bump from \(name(participant)): \(rejection)")
            if participant == transport.myID, case .checking = phase { phase = .needsRetry("That one came too soon after your last bump. Try again.") }
            else if participant != transport.myID {
                transport.send(.bumpTimedOut, to: [participant])
            }
        }
    }

    /// The coordinator's monotonic clock. Timestamps from other phones are never
    /// used for matching — only arrival time here.
    private func monotonic() -> TimeInterval { ProcessInfo.processInfo.systemUptime }

    // MARK: Coordinator loop

    private func startResolving() {
        stopResolving()
        resolveTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
    }

    private func stopResolving() { resolveTimer?.invalidate(); resolveTimer = nil }

    private func tick() {
        guard isCoordinator else { return }
        for outcome in matcher.resolve(now: monotonic()) {
            switch outcome {
            case .matched(let a, let b, let gap, let uwb):
                openProposal(a: a, b: b, uwb: uwb, manual: false, gap: gap)
            case .ambiguous(let participants, let count):
                for p in participants { deliverAmbiguous(to: p, candidates: count) }
                note("rejected \(participants.count) bumps as ambiguous")
            case .timedOut(let participant):
                note("[match] \(name(participant))'s bump had no partner within \(Int(matcher.config.window * 1000)) ms; only one phone reported a bump")
                deliverTimeout(to: participant)
            }
        }
        expireProposals()
    }

    private func openProposal(a: String, b: String, uwb: Bool, manual: Bool, gap: TimeInterval) {
        // One active proposal per participant.
        guard !matcher.locked.contains(a), !matcher.locked.contains(b) else { return }
        let proposal = LiveProposal(id: UUID().uuidString, a: a, b: b,
                                    uwbCorroborated: uwb, manual: manual, createdAt: Date())
        proposals[proposal.id] = proposal
        matcher.lock([a, b])

        for (me, them) in [(a, b), (b, a)] {
            let partner = membersByID[them] ?? Wire.Member(id: them, displayName: name(them))
            let body = Wire.Body.proposal(id: proposal.id, partner: partner,
                                          uwbCorroborated: uwb,
                                          expiresIn: Self.confirmationTimeout)
            if me == transport.myID {
                receiveProposal(id: proposal.id, partner: partner, uwb: uwb, manual: manual)
            } else {
                transport.send(body, to: [me])
            }
        }
        note(String(format: "proposed %@ ↔ %@ (gap %.0f ms%@)", name(a), name(b), gap * 1000, uwb ? ", UWB corroborated" : ""))
    }

    private func expireProposals() {
        let now = Date()
        for proposal in proposals.values
        where now.timeIntervalSince(proposal.createdAt) > Self.confirmationTimeout {
            close(proposal.id, reason: "Nobody confirmed in time.")
        }
    }

    private func close(_ proposalID: String, reason: String) {
        guard let proposal = proposals.removeValue(forKey: proposalID) else { return }
        matcher.unlock([proposal.a, proposal.b])
        for participant in [proposal.a, proposal.b] {
            if participant == transport.myID {
                localProposalClosed(proposalID, reason: reason)
            } else {
                transport.send(.proposalClosed(proposalID: proposalID, reason: reason), to: [participant])
            }
        }
    }

    private func seal(_ proposal: LiveProposal) {
        // Prefer an AI-capable participant to generate, so both phones get the
        // better result; otherwise a stable deterministic choice.
        let generator = aiCapable.contains(proposal.a) ? proposal.a
                      : aiCapable.contains(proposal.b) ? proposal.b
                      : min(proposal.a, proposal.b)
        // Tell the remote participant FIRST: sealing ourselves sends our profile,
        // and the partner must be sealed (caps locked) before that arrives.
        for participant in [proposal.a, proposal.b] where participant != transport.myID {
            transport.send(.proposalSealed(proposalID: proposal.id, generator: generator), to: [participant])
        }
        if proposal.a == transport.myID || proposal.b == transport.myID {
            localProposalSealed(proposal.id, generator: generator)
        }
        proposals.removeValue(forKey: proposal.id)
        matcher.unlock([proposal.a, proposal.b])
        note("sealed \(proposal.id.prefix(8)): \(name(generator)) writes the opener")
    }

    private func deliverTimeout(to participant: String) {
        if participant == transport.myID {
            if case .checking = phase { phase = .timedOut }
        } else {
            transport.send(.bumpTimedOut, to: [participant])
        }
    }

    private func deliverAmbiguous(to participant: String, candidates: Int) {
        if participant == transport.myID {
            if case .checking = phase { phase = .ambiguous(candidates) }
        } else {
            transport.send(.bumpAmbiguous(candidates: candidates), to: [participant])
        }
    }

    // MARK: Messages

    private func handle(_ body: Wire.Body, from peer: String) {
        switch body {

        case .hello(let displayName, let roomCode, let supportsUWB, let supportsAI):
            guard isCoordinator else { return }
            let full = transport.connected.count + 1 > PeerTransport.maxPeers
            guard roomCode == room.code, !full else {
                transport.send(.welcome(accepted: false,
                                        reason: full ? "This room is full (\(PeerTransport.maxPeers) phones max)." : "Wrong room code.",
                                        roomName: room.code ?? "", capacity: PeerTransport.maxPeers,
                                        occupancy: transport.connected.count + 1), to: [peer])
                return
            }
            membersByID[peer] = Wire.Member(id: peer, displayName: displayName, supportsUWB: supportsUWB)
            if supportsAI { aiCapable.insert(peer) }
            transport.send(.welcome(accepted: true, reason: nil, roomName: room.code ?? "",
                                    capacity: PeerTransport.maxPeers,
                                    occupancy: transport.connected.count + 1), to: [peer])
            broadcastRoster()
            exchangeTokens(with: peer)

        case .welcome(let accepted, let reason, let roomName, let capacity, let occupancy):
            if accepted {
                note("joined \"\(roomName)\": \(occupancy)/\(capacity) phones")
                capacityNote = "\(occupancy) of \(capacity) phones"
                exchangeTokens(with: peer)
            } else {
                room = .none
                transport.stop()
                // Clear nearby mode too, or autoStart would believe a start is
                // still in flight and never try again.
                nearbyMode = false
                phase = .needsRetry(reason ?? "That room wouldn't let you in.")
            }

        case .roster(let list):
            members = list.filter { $0.id != transport.myID }
            for m in list { membersByID[m.id] = m }

        case .discoveryToken(let data):
            // Reciprocate only for a NEW token, so the exchange terminates.
            if ranging.acceptToken(data, from: peer), let mine = ranging.prepareSession(for: peer) {
                transport.send(.discoveryToken(mine), to: [peer])
            }

        case .bumpEvent:
            guard isCoordinator else { return }
            ingestBump(from: peer)

        case .proximity(let subject, let distance):
            guard isCoordinator else { return }
            // Attributed to the reporting observer and its named peer, never
            // assumed to be about us.
            matcher.record(.init(observer: peer, peer: subject, distance: distance, at: monotonic()))

        case .proposal(let id, let partner, let uwb, _):
            counters.outcomes += 1
            note("[bump] outcome from coordinator: proposal")
            receiveProposal(id: id, partner: partner, uwb: uwb, manual: false)

        case .bumpTimedOut:
            counters.outcomes += 1
            note("[bump] outcome from coordinator: bumpTimedOut")
            if case .checking = phase { phase = .timedOut }

        case .bumpAmbiguous(let candidates):
            counters.outcomes += 1
            note("[bump] outcome from coordinator: bumpAmbiguous")
            if case .checking = phase { phase = .ambiguous(candidates) }

        case .confirm(let proposalID):
            guard isCoordinator, var proposal = proposals[proposalID] else { return }
            guard proposal.a == peer || proposal.b == peer else { return }
            proposal.confirmed.insert(peer)              // idempotent
            proposals[proposalID] = proposal
            let other = proposal.a == peer ? proposal.b : proposal.a
            if proposal.confirmed.count == 2 { seal(proposal) }
            else if other == transport.myID { partnerConfirmedLocally(proposalID) }
            else { transport.send(.partnerConfirmed(proposalID: proposalID), to: [other]) }

        case .decline(let proposalID, let reason):
            guard isCoordinator else { return }
            close(proposalID, reason: reason)

        case .partnerConfirmed:
            note("your partner confirmed")

        case .proposalClosed(let proposalID, let reason):
            localProposalClosed(proposalID, reason: reason)

        case .proposalSealed(let proposalID, let generator):
            localProposalSealed(proposalID, generator: generator)

        case .profile(let proposalID, let profile, let caps):
            guard myProposal?.id == proposalID, let proposal = myProposal else { return }
            var profile = profile
            profile.photo = ProfilePhoto.sanitized(profile.photo)   // bounded, must be an image
            partnerProfile = profile
            partnerCaps = caps
            iAmGenerator = chooseGenerator(partner: proposal.partner.id) == transport.myID
            note("received \(profile.displayName)'s interests")
            startGenerationIfReady(proposalID: proposalID)

        case .commonTopics(let ids):
            // Held in memory so turning the setting on later works at once,
            // but only ever shown while we have opted in too.
            if !ids.isEmpty {
                peerTopics[peer] = Set(ids.prefix(120))
            } else {
                peerTopics[peer] = nil
            }
            updateCommonGround()

        case .insight(let proposalID, let insight):
            guard myProposal?.id == proposalID, !iAmGenerator else { return }
            // The generator wrote "your/their" from its side; flip for ours.
            completeConnection(with: insight.mirrored())
        }
    }

    // MARK: Local proposal handling

    private func receiveProposal(id: String, partner: Wire.Member, uwb: Bool, manual: Bool) {
        // One active proposal per person: ignore a second while one is open.
        guard myProposal == nil else { return }
        let proposal = Proposal(id: id, partner: partner, uwbCorroborated: uwb, manual: manual)
        cancelGeneration()
        myProposal = proposal
        partnerProfile = nil
        partnerCaps = nil
        lockedCaps = nil
        coordinatorPick = nil
        sentProfileFor = nil
        myProposalExpiresAt = Date().addingTimeInterval(Self.confirmationTimeout)
        phase = .confirming(proposal)
        armPhaseDeadline(Self.confirmationTimeout) { [weak self] in
            guard let self, case .confirming = self.phase else { return }
            self.declineCurrent(reason: "You didn't confirm in time.")
        }
        Haptics.tap()
    }

    func confirmCurrent() {
        guard let proposal = myProposal else { return }
        phase = .waitingForPartner
        armPhaseDeadline(Self.confirmationTimeout) { [weak self] in
            guard let self, case .waitingForPartner = self.phase else { return }
            self.phase = .needsRetry("\(proposal.partner.displayName) didn't confirm in time.")
            self.myProposal = nil
        }
        if isCoordinator {
            guard var live = proposals[proposal.id] else { return }
            live.confirmed.insert(transport.myID)
            proposals[proposal.id] = live
            let other = live.a == transport.myID ? live.b : live.a
            if live.confirmed.count == 2 { seal(live) }
            else { transport.send(.partnerConfirmed(proposalID: proposal.id), to: [other]) }
        } else {
            transport.send(.confirm(proposalID: proposal.id), to: coordinatorIDs())
        }
    }

    func declineCurrent(reason: String = "Not this person.") {
        guard let proposal = myProposal else { return }
        cancelGeneration()
        myProposal = nil
        if isCoordinator { close(proposal.id, reason: reason) }
        else { transport.send(.decline(proposalID: proposal.id, reason: reason), to: coordinatorIDs()) }
        phase = .needsRetry(reason)
    }

    private func partnerConfirmedLocally(_ proposalID: String) {
        note("partner confirmed \(proposalID.prefix(8))")
    }

    private func localProposalClosed(_ proposalID: String, reason: String) {
        guard myProposal?.id == proposalID else { return }
        cancelGeneration()
        myProposal = nil; partnerProfile = nil
        phase = .needsRetry(reason)
    }

    /// Both confirmed. Now — and only now — the two phones exchange full
    /// profiles DIRECTLY. The coordinator never sees them.
    private func localProposalSealed(_ proposalID: String, generator: String) {
        guard let proposal = myProposal, proposal.id == proposalID else { return }
        coordinatorPick = generator
        lockedCaps = currentCaps
        iAmGenerator = chooseGenerator(partner: proposal.partner.id) == transport.myID
        phase = .exchanging
        armPhaseDeadline(Self.exchangeTimeout) { [weak self] in
            guard let self, case .exchanging = self.phase else { return }
            self.phase = .needsRetry("Couldn't swap interests with \(proposal.partner.displayName). Move a little closer and bump again.")
            self.myProposal = nil
        }
        transport.openDirectLink(to: proposal.partner.id)
        sendProfileIfPossible(proposalID: proposalID)
        // The partner's profile may have arrived before our seal.
        startGenerationIfReady(proposalID: proposalID)
    }

    private func sendProfileIfPossible(proposalID: String) {
        guard let proposal = myProposal, proposal.id == proposalID, sentProfileFor != proposalID else { return }
        guard transport.connected.contains(where: { $0.id == proposal.partner.id }) else { return }
        sentProfileFor = proposalID
        transport.send(.profile(proposalID: proposalID, profile: store.profile.shareable, caps: myCaps),
                       to: [proposal.partner.id])
        note("sent your interests to \(proposal.partner.displayName)")
        startGenerationIfReady(proposalID: proposalID)
    }

    /// What we tell a confirmed partner about ourselves: two booleans.
    private var currentCaps: Wire.PartnerCaps {
        Wire.PartnerCaps(cloudConsent: store.privacy.allowsCloud,
                         grokReady: store.privacy.allowsCloud && grokReady)
    }
    private var myCaps: Wire.PartnerCaps { lockedCaps ?? currentCaps }

    /// Both phones run this with the same inputs and reach the same answer.
    /// Grok is used only when BOTH people allowed cloud processing; then the
    /// phone that can reach it (lowest id if both can) generates. Otherwise the
    /// coordinator's pick stands — it prefers an Apple-Intelligence phone, which
    /// is unrelated to whether Grok is usable.
    private func chooseGenerator(partner: String) -> String? {
        Self.generator(me: transport.myID, partner: partner, myCaps: myCaps,
                       theirCaps: partnerCaps, coordinatorPick: coordinatorPick)
    }

    /// Pure, so it can be tested and so both phones provably agree: swap `me`
    /// and `partner` (and their caps) and the answer is the same.
    nonisolated static func generator(me: String, partner: String, myCaps: Wire.PartnerCaps,
                          theirCaps: Wire.PartnerCaps?, coordinatorPick: String?) -> String? {
        if let theirCaps, myCaps.cloudConsent, theirCaps.cloudConsent {
            let ready = [(me, myCaps.grokReady), (partner, theirCaps.grokReady)]
                .filter(\.1).map(\.0).sorted()
            if let first = ready.first { return first }
        }
        return coordinatorPick
    }

    private func startGenerationIfReady(proposalID: String) {
        // Only once sealed (caps locked), so the choice can't change underneath us.
        guard iAmGenerator, generationTask == nil, lockedCaps != nil,
              let proposal = myProposal, proposal.id == proposalID,
              let theirs = partnerProfile, let caps = partnerCaps else { return }
        // Only send shared information to the cloud if both people allowed it.
        let cloud: ConversationService.CloudPhraser? =
            (myCaps.grokReady && caps.cloudConsent) ? apiClient : nil
        let mine = store.profile.shareable
        generationTask = Task { [weak self] in
            let insight = await ConversationService.makeInsight(mine: mine, theirs: theirs, cloud: cloud)
            guard let self, !Task.isCancelled else { return }
            self.generationTask = nil
            // A late result for a connection we've moved on from is dropped, and
            // we never send if we're somehow no longer the generator.
            guard self.iAmGenerator, let current = self.myProposal, current.id == proposalID else { return }
            // Idempotent: a retried send is harmless because the receiver keys on the
            // proposal id and ignores a second one.
            self.transport.send(.insight(proposalID: proposalID, insight: insight), to: [current.partner.id])
            self.completeConnection(with: insight)
        }
    }

    private func cancelGeneration() {
        generationTask?.cancel()
        generationTask = nil
    }

    // MARK: Common ground (opt-in, before a bump)

    struct NearbyCommon: Equatable {
        let peer: String
        let topics: [String]
        let distance: Double
    }
    /// The strongest nearby match right now, or nil. No name: that is only
    /// shared after both people confirm a bump.
    @Published private(set) var nearbyCommon: NearbyCommon?
    private var peerTopics: [String: Set<String>] = [:]
    static let commonGroundDistance: Double = 1.5
    static let commonGroundMinimum = 2

    private func announceTopics(to peers: [String]) {
        guard !peers.isEmpty else { return }
        let ids = store.privacy.sharesCommonGround
            ? InterestMatcher.topics(store.profile.interests).sorted() : []
        transport.send(.commonTopics(ids), to: peers)
    }

    private func updateCommonGround() {
        let resting: Bool = {
            switch phase { case .ready, .notReady, .preparing: return true; default: return false }
        }()
        guard store.privacy.sharesCommonGround, resting, !isBackgrounded else {
            nearbyCommon = nil; return
        }
        let mine = InterestMatcher.topics(store.profile.interests)
        let best = peerTopics.compactMap { peer, theirs -> NearbyCommon? in
            // Fresh UWB distance only: a stale or missing reading proves nothing.
            guard let m = ranging.freshMeasurement(for: peer), let d = m.distance,
                  d <= Self.commonGroundDistance else { return nil }
            let shared = InterestMatcher.sharedTopicLabels(mine, theirs)
            guard shared.count >= Self.commonGroundMinimum else { return nil }
            return NearbyCommon(peer: peer, topics: Array(shared.prefix(3)), distance: d)
        }
        .max { ($0.topics.count, -$0.distance) < ($1.topics.count, -$1.distance) }

        if best?.peer != nearbyCommon?.peer, let best {
            Haptics.tap()
            note(String(format: "[common] %d shared topics with %@ at %.2f m", best.topics.count, name(best.peer), best.distance))
        }
        nearbyCommon = best
    }

    // MARK: Interest tags

    private var tagging: Task<Void, Never>?

    /// Files custom interests under catalogue categories so "One Piece" and
    /// "Naruto" can meet at "Anime". Invisible to the person; only with cloud
    /// processing allowed. A failure leaves them untagged for the next launch.
    func tagInterestsIfNeeded() {
        guard tagging == nil, store.privacy.allowsCloud, let client = apiClient else { return }
        let untagged = store.profile.interests.filter { $0.custom && $0.tags == nil }.map(\.label)
        guard !untagged.isEmpty else { return }
        tagging = Task { [weak self] in
            let result = try? await client.tagInterests(untagged)
            guard let self else { return }
            self.tagging = nil
            guard let result else { return self.note("[tags] tagging failed; will retry later") }
            let byLabel = Dictionary(result.map { ($0.key.lowercased(), $0.value) }, uniquingKeysWith: { a, _ in a })
            self.store.profile.interests = self.store.profile.interests.map { interest in
                guard interest.custom, interest.tags == nil, untagged.contains(interest.label) else { return interest }
                var tagged = interest
                tagged.tags = byLabel[interest.label.lowercased()] ?? []
                return tagged
            }
            self.note("[tags] tagged \(untagged.count) interest(s)")
        }
    }

    // MARK: Cloud status

    private var apiClient: BumpAPIClient? { BumpAPIClient.resolve(override: store.settings.apiBaseURL) }

    /// Check (quickly) whether the BUMP server is reachable and has Grok set up.
    /// Skipped entirely when the user hasn't allowed cloud processing.
    func refreshCloudStatus() {
        healthTask?.cancel()
        guard store.privacy.allowsCloud, let client = apiClient else { grokReady = false; return }
        healthTask = Task { [weak self] in
            let ready = (try? await client.health())?.grokConfigured ?? false
            guard !Task.isCancelled else { return }
            self?.grokReady = ready
        }
    }

    private func completeConnection(with insight: ConnectionInsight) {
        guard let proposal = myProposal, let partner = partnerProfile else { return }
        phaseDeadline?.invalidate()
        let result = Result(partner: partner, insight: insight,
                            evidence: proposal.evidence,
                            roomName: room.code ?? "",
                            metOn: Date())
        phase = .connected(result)
        myProposal = nil
        motion.stop()
        Haptics.success()
        note("connected with \(partner.displayName)")
    }

    // MARK: Manual selection (honest fallback)

    /// Used when automatic matching can't decide, or UWB/motion isn't usable.
    /// Recorded as `.manualSelection`, never as a hardware-detected bump.
    func proposeManually(with member: Wire.Member) {
        guard isCoordinator else {
            // A guest asks the coordinator by sending a bump and letting the
            // coordinator pair, which it cannot do for a manual pick. Keep the
            // honest limitation explicit.
            phase = .needsRetry("Only the phone hosting the room can pick someone manually right now. Ask them to host the pick, or try bumping again.")
            return
        }
        openProposal(a: transport.myID, b: member.id, uwb: false, manual: true, gap: 0)
    }

    // MARK: Roster / peers

    private func peerJoined(_ peer: String) {
        announceTopics(to: [peer])
        if !isCoordinator, room.code != nil {
            transport.send(.hello(displayName: store.profile.displayName,
                                  roomCode: room.code ?? "",
                                  supportsUWB: ranging.isSupported,
                                  supportsAI: ConversationService.onDeviceModelAvailable),
                           to: [peer])
        }
        if case .hostLost(let code) = room { room = .joined(code: code) }
        // A newly opened direct link may be the partner we are waiting for.
        if let proposal = myProposal, proposal.partner.id == peer {
            sendProfileIfPossible(proposalID: proposal.id)
        }
    }

    private func peerLeft(_ peer: String) {
        proximityGates[peer] = nil
        peerTopics[peer] = nil
        updateCommonGround()
        // A Multipeer drop is NOT proof that ranging has failed. Multipeer is a
        // foreground-only transport, so it disconnects the instant the app is
        // backgrounded, while a UWB session is allowed to keep running with an
        // active Live Activity. Tearing the NISession down here killed ranging
        // about a second after backgrounding, every time.
        //
        // Only end ranging when the session is genuinely finished: the app is in
        // the foreground (so the drop means something), or there is no live
        // session to keep it alive for. NISession's own delegate still reports
        // peerEnded and invalidation, which is what actually decides this.
        let sessionStillLive = liveActivity.isRunning && !liveActivity.hasExpired
        if !isBackgrounded || !sessionStillLive {
            ranging.endSession(for: peer)
        } else {
            note("transport dropped \(name(peer)) while backgrounded, keeping the UWB session")
        }
        if isCoordinator {
            matcher.remove(participant: peer)
            membersByID[peer] = nil
            aiCapable.remove(peer)
            for proposal in proposals.values where proposal.a == peer || proposal.b == peer {
                close(proposal.id, reason: "\(name(peer)) disconnected.")
            }
            broadcastRoster()
        } else if !transport.isRelay, members.isEmpty || transport.connected.isEmpty {
            // (With the relay the server re-elects a coordinator itself, so
            // there is nothing to rebuild here.)
            // Backgrounded, losing the coordinator is expected: Multipeer always
            // drops. Retrying would spin against a transport iOS has stopped, so
            // hold the session and let the foreground handler rebuild it.
            if isBackgrounded && liveActivity.isRunning && !liveActivity.hasExpired {
                note("coordinator dropped while backgrounded, waiting rather than retrying")
                return
            }
            // We lost the coordinator. Pause matching and offer a clear way back;
            // no host migration, by design.
            if let code = room.code {
                room = .hostLost(code: code)
                motion.stop()
                if nearbyMode && code == Self.nearbyRoom {
                    // Nearby mode heals itself: find (or become) a new host.
                    phase = .notReady
                    note("nearby host left; reconnecting")
                    let delay = 0.5 + Double.random(in: 0...1.5)
                    Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
                        Task { @MainActor in
                            guard let self, self.nearbyMode, case .hostLost = self.room else { return }
                            self.leaveRoom()
                            self.joinNearbyOrHost()
                        }
                    }
                } else {
                    phase = .needsRetry("The phone hosting \"\(code)\" went away. Rejoin, or host the room yourself.")
                }
            }
        }
        if let proposal = myProposal, proposal.partner.id == peer {
            cancelGeneration()
            myProposal = nil
            phase = .needsRetry("\(proposal.partner.displayName) disconnected.")
        }
    }

    private func rosterChanged(_ peers: [Wire.Member]) {
        guard isCoordinator else { return }
        capacityNote = "\(peers.count + 1) of \(PeerTransport.maxPeers) phones"
        broadcastRoster()
    }

    private func broadcastRoster() {
        guard isCoordinator else { return }
        var list = transport.connected.map { membersByID[$0.id] ?? $0 }
        list.append(Wire.Member(id: transport.myID,
                                displayName: store.profile.displayName,
                                supportsUWB: ranging.isSupported))
        members = list.filter { $0.id != transport.myID }
        transport.broadcast(.roster(members: list))
    }

    /// An NISession was invalidated. Its tokens are dead, so the only recovery
    /// is a fresh session and a fresh exchange, and only while the peer is
    /// still connected. Bounded so a persistent failure cannot spin.
    private func recoverRanging(_ peer: String) {
        guard transport.connected.contains(where: { $0.id == peer }) else { return }
        let n = uwbRecoveries[peer, default: 0]
        guard n < Self.maxUWBRecoveries else {
            note("[uwb] not recovering \(name(peer)) again after \(n) attempts; motion matching still works")
            return
        }
        uwbRecoveries[peer] = n + 1
        note("[uwb] recreating session with \(name(peer)) (attempt \(n + 1))")
        exchangeTokens(with: peer)
    }

    private func exchangeTokens(with peer: String) {
        guard let token = ranging.prepareSession(for: peer) else { return }
        transport.send(.discoveryToken(token), to: [peer])
    }

    private func coordinatorIDs() -> [String] {
        // As a guest we are connected to the coordinator (and possibly a partner
        // via a direct link). Messages for the coordinator go to whichever peer
        // we joined through; with a star topology that is the host.
        transport.connected.map(\.id)
    }

    private func name(_ id: String) -> String {
        membersByID[id]?.displayName ?? transport.displayName(of: id)
    }

    // MARK: Live Activity

    /// Stable for the life of a session, so an intent fired from the Dynamic
    /// Island can be checked against the session it was rendered for.
    private(set) var sessionID = UUID().uuidString

    /// Actions from the Live Activity. Every one is validated against current
    /// state: a stale session, an expired proposal or one already consumed is
    /// refused rather than acted on.
    func handleIntent(_ action: BumpIntentAction) {
        switch action {
        case .confirm(let session, let proposal):
            guard session == sessionID else { return note("ignored confirm from an old session") }
            guard let mine = myProposal, mine.id == proposal else {
                return note("ignored confirm for a proposal that is no longer current")
            }
            confirmCurrent()
        case .reject(let session, let proposal):
            guard session == sessionID, let mine = myProposal, mine.id == proposal else {
                return note("ignored reject for a proposal that is no longer current")
            }
            declineCurrent()
        case .stop(let session):
            guard session == sessionID else { return }
            note("stopped from the Live Activity")
            endSession()
        }
    }

    /// Begin the session activity once there is a real session to describe.
    private func startLiveActivityIfNeeded() {
        guard !liveActivity.isRunning, room != .none else { return }
        liveActivity.start(sessionID: sessionID, initial: .preparing)
        refreshLiveActivity()
    }

    /// End the session entirely: no room, no sensing, no activity.
    func endSession() {
        var final = BumpActivityAttributes.ContentState.preparing()
        final.state = .ended
        liveActivity.end(final: final)
        isPaused = true
        leaveRoom()
    }

    /// Map the engine's state onto what a person reads in the Dynamic Island.
    /// Derived every time rather than stored, so the two cannot drift.
    private var activityContent: BumpActivityAttributes.ContentState {
        var c = BumpActivityAttributes.ContentState.preparing()
        c.nearbyCount = members.count

        switch phase {
        case .confirming(let proposal):
            c.state = .candidate
            c.peerName = proposal.partner.displayName
            c.proposalID = proposal.id
            // Stable, not "now + timeout": a fresh value on every refresh made
            // each refresh a real update, used up iOS's update allowance and
            // left button taps waiting behind a queue of throttled updates.
            c.proposalExpiresAt = myProposalExpiresAt ?? Date().addingTimeInterval(Self.confirmationTimeout)
            return c
        case .waitingForPartner, .exchanging:
            c.state = .awaitingPeer
            c.peerName = myProposal?.partner.displayName
            return c
        case .connected(let result):
            c.state = .connected
            c.peerName = result.partner.displayName
            c.connectionID = store.connections.first?.id.uuidString
            return c
        default:
            break
        }

        switch autoStatus {
        case .paused:
            c.state = .paused
        case .blocked(let why):
            c.state = .unavailable
            c.unavailableReason = why
        case .preparing:
            c.state = room == .none ? .preparing : .discovering
        case .lookingForPhones, .connecting:
            c.state = .discovering
        case .reconnecting:
            // Honest: a backgrounded session without fresh ranging is not
            // ready, whatever the Live Activity last said.
            c.state = isBackgrounded ? .unavailable : .discovering
            if isBackgrounded { c.unavailableReason = "Open BUMP to reconnect." }
        case .listening:
            c.state = .ready
        }
        return c
    }

    /// Push the current state. Cheap: the controller drops updates that would
    /// not change anything on screen.
    func refreshLiveActivity() {
        guard liveActivity.isRunning else { return }
        if liveActivity.hasExpired {
            note("session deadline reached")
            endSession()
            return
        }
        let content = activityContent
        // Only a new decision deserves to interrupt whatever the person is doing.
        let alert = content.state == .candidate && liveActivity.lastPushedState != .candidate
        liveActivity.update(content, alert: alert)
    }

    // MARK: Lifecycle

    func handleScenePhase(_ scenePhase: ScenePhase) {
        let old = lifecycle
        lifecycle = "\(scenePhase)"
        if old != lifecycle { transition("lifecycle", old, lifecycle) }
        switch scenePhase {
        case .inactive:
            // Inactive is NOT backgrounded. iOS makes the app inactive while a
            // system prompt is up (Local Network, Nearby Interaction), and for
            // Control Center or a notification pull-down. Stopping here used
            // to kill motion during the permission prompt, and with a Live
            // Activity running the phase stayed .ready, so nothing restarted
            // it: the phone looked ready and ignored every bump.
            note("inactive (system prompt or overlay); services kept running")
        case .active:
            isBackgrounded = false
            proximityGates.removeAll()
            // Coming back may mean they just fixed a permission, so always give
            // discovery another chance rather than staying blocked forever.
            transport.clearDiscoveryBlock()
            ranging.resumeAll()
            if room != .none { refreshCloudStatus() }
            // Validate the deadline here rather than trusting an in-memory
            // timer to have fired while the process was suspended.
            if liveActivity.isRunning && liveActivity.hasExpired {
                note("session expired while backgrounded")
                endSession()
                return
            }
            // Pick straight back up. No Start action, no reconnect prompt.
            autoStart()
            syncPresentation()
        case .background:
            // Core Motion gets no background execution, so the accelerometer
            // stops either way. A bump that was mid-flight drops back to
            // resting, and returning to the app starts listening again on its
            // own.
            motion.stop()

            isBackgrounded = true
            lastBackgroundedAt = Date()
            backgroundRangingCallbacks = 0      // count this backgrounding only
            if liveActivity.isRunning && !liveActivity.hasExpired {
                // A valid session with a Live Activity keeps ranging. Documented
                // from iOS 18.4 with the nearby-interaction background mode.
                // NOTE: documented platform support, not observed on hardware here.
                //
                // Stay in `.ready`: ranging continues, so proximity can still
                // trigger. Dropping to `.notReady` here would silently make the
                // whole background path impossible.
                note("backgrounded with a live session, keeping UWB ranging")
                proximityGates.removeAll()   // require a fresh approach
            } else {
                ranging.pauseAll()
                if case .ready = phase { phase = .notReady }
            }
            if case .checking = phase { phase = .notReady }
            refreshLiveActivity()
        @unknown default: break
        }
    }

    // MARK: Retry / reset

    func retry() {
        cancelGeneration()
        myProposal = nil; partnerProfile = nil
        phase = .notReady
        // .notReady alone is a dead end: something has to start sensing again.
        autoStart()
    }

    func bumpAgain() {
        cancelGeneration()
        myProposal = nil; partnerProfile = nil
        phase = .notReady
        // Goes through autoStart so a finished match also re-establishes the
        // room if it was lost while the reveal was open.
        autoStart()
    }

    /// Returns what it saved, so the caller can take the user to that
    /// connection. Without this the id is unrecoverable at the call site, and
    /// the reveal has nowhere to go but back to the radar.
    @discardableResult
    func saveCurrentConnection() -> SavedConnection? {
        guard case .connected(let result) = phase else { return nil }
        let connection = SavedConnection(partnerName: result.partner.displayName,
                                         partnerBio: result.partner.bio,
                                         partnerPhoto: result.partner.photo,
                                         metOn: result.metOn,
                                         roomName: result.roomName,
                                         insight: result.insight,
                                         pairingEvidence: result.evidence,
                                         partnerProfile: result.partner)
        store.save(connection)
        Haptics.tap()
        return connection
    }

    // MARK: Helpers

    /// Resting outcomes return to listening on their own after a short pause,
    /// long enough to read. Before this, the person had to tap Try again, and
    /// the other phone (which may not have seen the message) sat stuck.
    private func scheduleRearmIfResting() {
        rearmTimer?.invalidate(); rearmTimer = nil
        switch phase {
        case .timedOut, .ambiguous, .needsRetry: break
        default: return
        }
        let resting = phase
        rearmTimer = Timer.scheduledTimer(withTimeInterval: Self.restingOutcomeDuration, repeats: false) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.phase == resting else { return }
                self.note("returning to listening after \(Self.describe(resting))")
                self.bumpAgain()
            }
        }
    }

    /// One structured transition line: subsystem, old -> new, reason, ids.
    func transition(_ subsystem: String, _ from: String, _ to: String,
                    reason: String? = nil, proposal: String? = nil) {
        var line = "[\(subsystem)] \(from) -> \(to)"
        if let reason { line += " | \(reason)" }
        if let proposal { line += " | proposal \(proposal.prefix(8))" }
        note(line)
    }

    private func armPhaseDeadline(_ seconds: TimeInterval, _ action: @escaping () -> Void) {
        phaseDeadline?.invalidate()
        phaseDeadline = Timer.scheduledTimer(withTimeInterval: seconds, repeats: false) { _ in
            Task { @MainActor in action() }
        }
    }

    /// Logs each newly-appeared nearby phone as a streetpass. Every appearance
    /// counts, bump or no bump; `Store` collapses repeats of the same person.
    private func recordStreetpasses() {
        #if DEBUG
        guard DemoMode.active == nil else { return }
        #endif
        for member in members where !streetpassLogged.contains(member.id) {
            streetpassLogged.insert(member.id)
            store.recordStreetpass(name: member.displayName,
                                   roomName: room.code ?? Self.nearbyRoom)
        }
    }

    /// Called after any state change that a person could see.
    private func syncPresentation() {
        startLiveActivityIfNeeded()
        refreshLiveActivity()
    }

    func note(_ text: String) {
        log.insert(LogLine(at: Date(), text: text), at: 0)
        if log.count > 500 { log.removeLast() }
    }

    func clearLog() { log.removeAll() }

    /// Everything the two-phone panel shows, as label/value rows. Excludes
    /// profile content, tokens and full peer names (only the transient suffix).
    func diagnosticsRows() -> [(String, String)] {
        func age(_ d: Date?) -> String { d.map { String(format: "%.1f s ago", Date().timeIntervalSince($0)) } ?? "never" }
        func short(_ id: String) -> String { id.components(separatedBy: "#").last ?? "?" }
        var rows: [(String, String)] = [
            ("Session", String(sessionID.prefix(6))),
            ("Peer id", short(transport.myID)),
            ("Lifecycle", lifecycle),
            ("Readiness", "\(autoStatus)"),
            ("Phase", Self.describe(phase)),
            ("Transport", "\(transport.isRelay ? "server relay\(transport.relayStreamUp ? "" : " (not reached)")" : "Multipeer"), \(transport.isActive ? "up" : "down"), \(isCoordinator ? "coordinator" : "guest")"),
            ("Room", room.code ?? "none"),
            ("Peers seen / connected", "\(transport.peersSeen) / \(transport.connected.map { short($0.id) }.joined(separator: ","))"),
            ("Join in flight", transport.joinInFlight ? "yes" : "no"),
            ("Msgs sent / undelivered / received", "\(transport.sentCount) / \(transport.undeliveredCount) / \(transport.receivedCount)"),
            ("Local Network", transport.discoveryUnavailable != nil ? "failed to start" : (searchStalled ? "no phones seen in 15 s (possibly denied)" : "no error reported (iOS exposes no status)")),
            ("Nearby Interaction permission", ranging.permissionDenied ? "denied" : "not denied (iOS exposes no status before a denial)"),
            ("Motion", "\(motion.isRunning ? "running" : "stopped"), \(motion.isAvailable ? "available" : "unavailable")"),
            ("Last sample", motion.sampleAge.map { String(format: "%.2f s ago", $0) } ?? "none"),
            ("Samples", "\(motion.sampleCount)"),
            ("|a| now / peak 3 s", String(format: "%.1f / %.1f m/s²", motion.currentMagnitude, motion.recentPeak)),
            ("Last spike", motion.lastSpikeMagnitude.map { String(format: "%.1f m/s², %@", $0, age(motion.lastSpikeAt)) } ?? "none"),
            ("Threshold / cooldown", String(format: "%.1f m/s² (gravity removed) / %.1f s", motion.config.threshold, motion.config.cooldown)),
            ("Bumps detected / suppressed", "\(counters.bumpsDetected) / \(counters.bumpsSuppressed)"),
            ("Bumps sent / not sent", "\(counters.bumpsSent) / \(counters.bumpsNotSent)"),
            ("Events received (coord) / outcomes", "\(counters.bumpsReceived) / \(counters.outcomes)"),
            ("UWB", ranging.isSupported ? "supported, direction \(ranging.supportsDirection ? "yes" : "no")" : "unsupported"),
            ("Mode", store.settings.detectionMode.label),
        ]
        for (peer, state) in ranging.sessionStates.sorted(by: { $0.key < $1.key }) {
            let m = ranging.measurements[peer]
            rows.append(("UWB \(short(peer))", "\(state), \(ranging.callbackCounts[peer] ?? 0) callbacks, last \(age(ranging.lastCallbackAt[peer]))"))
            rows.append(("  distance / direction", "\(m?.distance.map { String(format: "%.2f m", $0) } ?? "nil") / \(m?.direction == nil ? "nil" : "yes")"))
        }
        rows.append(("Common ground", store.privacy.sharesCommonGround
            ? "on, topics from \(peerTopics.count) peer(s), showing \(nearbyCommon.map { "\($0.topics.count) with \(short($0.peer)) at \(String(format: "%.2f m", $0.distance))" } ?? "nothing")"
            : "off"))
        rows.append(("Proposal", myProposal.map { "\($0.id.prefix(8)) with \(short($0.partner.id))" } ?? "none"))
        return rows
    }

    #if DEBUG
    /// DEBUG-only: pose a phase for simulator screenshots and previews. Never
    /// called on a real run; see `DemoMode`.
    func applyDemo(phase: Phase, members: [Wire.Member]) {
        self.phase = phase
        self.members = members
        self.room = .hosting(code: "demo")
        self.capacityNote = "\(members.count + 1) of \(PeerTransport.maxPeers) phones"
    }
    #endif
}
