import Foundation
#if canImport(ActivityKit)
import ActivityKit
#endif

/// Owns the BUMP Live Activity: at most one per device, for the life of a
/// session rather than the life of a screen.
///
/// Everything here is about presentation. It never decides anything about
/// matching; it is handed state that the engine has already settled on.
@MainActor
final class LiveActivityController: ObservableObject {

    /// Mirrors what is currently on screen, so the app can show session status
    /// in Testing tools without reaching into ActivityKit.
    @Published private(set) var isRunning = false
    @Published private(set) var lastPushedState: BumpActivityState?
    @Published private(set) var sessionID: String?
    @Published private(set) var expiresAt: Date?
    @Published private(set) var unavailableReason: String?

    var onLog: ((String) -> Void)?

    #if canImport(ActivityKit)
    @available(iOS 16.2, *)
    private var activity: Activity<BumpActivityAttributes>? {
        get { _activity as? Activity<BumpActivityAttributes> }
        set { _activity = newValue }
    }
    private var _activity: Any?
    #endif

    /// The last content we pushed. Updates are skipped when nothing a person
    /// could see has changed, so we never drive the activity at sensor rate.
    private var lastContent: AnyHashable?

    // MARK: Availability

    /// Live Activities can be switched off per app in Settings, and are not
    /// available at all before iOS 16.2. Both are runtime facts, not guesses.
    var isAvailable: Bool {
        #if canImport(ActivityKit)
        if #available(iOS 16.2, *) {
            return ActivityAuthorizationInfo().areActivitiesEnabled
        }
        #endif
        return false
    }

    var unavailableExplanation: String? {
        #if canImport(ActivityKit)
        if #available(iOS 16.2, *) {
            return ActivityAuthorizationInfo().areActivitiesEnabled
                ? nil
                : "Live Activities are off for BUMP. Turn them on in Settings to keep bumping while you use another app."
        }
        #endif
        return "This iOS version doesn't support Live Activities."
    }

    // MARK: Lifecycle

    /// Adopt any activity left over from a previous launch, and end the extras.
    /// Called once at startup so a crash or force quit cannot leave a stale
    /// BUMP sitting in the Dynamic Island.
    func reconcileOnLaunch() {
        #if canImport(ActivityKit)
        guard #available(iOS 16.2, *) else { return }
        let existing = Activity<BumpActivityAttributes>.activities
        guard !existing.isEmpty else { return }
        // Keep the newest, end the rest. One session per device.
        let sorted = existing.sorted { $0.attributes.expiresAt > $1.attributes.expiresAt }
        for stale in sorted.dropFirst() {
            Task { await stale.end(nil, dismissalPolicy: .immediate) }
        }
        if let keep = sorted.first {
            if keep.attributes.expiresAt <= Date() || keep.attributes.schema != BumpActivity.schema {
                // Expired while we were not running, or from an older build.
                Task { await keep.end(nil, dismissalPolicy: .immediate) }
                log("ended a stale Live Activity from a previous launch")
            } else {
                activity = keep
                sessionID = keep.attributes.sessionID
                expiresAt = keep.attributes.expiresAt
                isRunning = true
                log("adopted the Live Activity from a previous launch")
            }
        }
        #endif
    }

    /// Start the session activity. Idempotent: calling it again while one is
    /// running only refreshes the content.
    @discardableResult
    func start(sessionID id: String, minutes: Int = BumpActivity.defaultSessionMinutes,
               initial: BumpActivityState = .preparing) -> Bool {
        #if canImport(ActivityKit)
        guard #available(iOS 16.2, *) else { return false }
        guard isAvailable else {
            unavailableReason = unavailableExplanation
            log("not starting a Live Activity: \(unavailableReason ?? "unavailable")")
            return false
        }
        if activity != nil {
            log("Live Activity already running; not starting a second one")
            return true
        }
        let ends = Date().addingTimeInterval(TimeInterval(minutes) * 60)
        let attributes = BumpActivityAttributes(sessionID: id, expiresAt: ends,
                                                schema: BumpActivity.schema)
        var content = BumpActivityAttributes.ContentState.preparing()
        content.state = initial
        do {
            activity = try Activity.request(
                attributes: attributes,
                content: .init(state: content, staleDate: Date().addingTimeInterval(BumpActivity.staleAfter)),
                pushType: nil          // all updates come from this process
            )
            sessionID = id
            expiresAt = ends
            isRunning = true
            unavailableReason = nil
            lastPushedState = initial
            log("Live Activity started, session \(id.prefix(8)), ends \(ends.formatted(date: .omitted, time: .shortened))")
            return true
        } catch {
            unavailableReason = "Couldn't start the Live Activity: \(error.localizedDescription)"
            log("Live Activity request failed: \(error.localizedDescription)")
            return false
        }
        #else
        return false
        #endif
    }

    /// Push new content, but only when something a person could see changed.
    /// `alert` asks iOS to surface the update; it decides the presentation, we
    /// do not claim to force an expansion.
    func update(_ state: BumpActivityAttributes.ContentState, alert: Bool = false) {
        #if canImport(ActivityKit)
        guard #available(iOS 16.2, *), let activity else { return }
        let key = AnyHashable(state)
        guard key != lastContent else { return }
        lastContent = key
        lastPushedState = state.state

        let content = ActivityContent(
            state: state,
            staleDate: Date().addingTimeInterval(BumpActivity.staleAfter)
        )
        Task {
            if alert, #available(iOS 16.2, *) {
                let name = state.peerName ?? "someone"
                await activity.update(content, alertConfiguration: .init(
                    title: "Possible connection",
                    body: "Did you bump with \(name)?",
                    sound: .default
                ))
            } else {
                await activity.update(content)
            }
        }
        log("Live Activity -> \(state.state.rawValue)")
        #endif
    }

    /// End the activity. `keepVisible` leaves a completed connection on screen
    /// briefly so it can be tapped.
    func end(final: BumpActivityAttributes.ContentState? = nil, keepVisible: Bool = false) {
        #if canImport(ActivityKit)
        guard #available(iOS 16.2, *), let activity else { return }
        let content = final.map {
            ActivityContent(state: $0, staleDate: nil)
        }
        Task {
            await activity.end(content,
                               dismissalPolicy: keepVisible ? .after(Date().addingTimeInterval(240)) : .immediate)
        }
        self.activity = nil
        isRunning = false
        lastContent = nil
        lastPushedState = nil
        sessionID = nil
        expiresAt = nil
        log("Live Activity ended")
        #endif
    }

    /// True once the session's own deadline has passed. Checked on callbacks
    /// and on foreground restoration rather than trusting a timer to fire while
    /// the process is suspended.
    var hasExpired: Bool {
        guard let expiresAt else { return false }
        return Date() >= expiresAt
    }

    private func log(_ s: String) { onLog?(s) }
}
