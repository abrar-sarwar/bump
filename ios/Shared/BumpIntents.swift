import AppIntents
import Foundation

/// Actions fired from the Live Activity.
///
/// `LiveActivityIntent` runs inside the APP process, not the widget extension,
/// so confirming a bump from Dynamic Island does not bring the BUMP interface
/// to the foreground. The widget only names the action and passes ids; every
/// decision is made against the app's authoritative state.
///
/// This file is compiled into both targets. It must not reference the engine,
/// the transports or the sensors directly, so it goes through the bridge below.

// MARK: - Bridge

/// What an intent is asking for. Deliberately tiny and value-typed so it can
/// cross the target boundary.
public enum BumpIntentAction: Sendable, Equatable {
    case confirm(sessionID: String, proposalID: String)
    case reject(sessionID: String, proposalID: String)
    case stop(sessionID: String)
}

/// The app registers a handler at launch. In the widget extension nothing
/// registers one, which is correct: the widget never performs the work.
public final class BumpIntentBridge: @unchecked Sendable {
    public static let shared = BumpIntentBridge()
    private let lock = NSLock()
    private var _handler: (@Sendable (BumpIntentAction) async -> Void)?

    public var handler: (@Sendable (BumpIntentAction) async -> Void)? {
        get { lock.lock(); defer { lock.unlock() }; return _handler }
        set { lock.lock(); _handler = newValue; lock.unlock() }
    }

    public func perform(_ action: BumpIntentAction) async {
        // A missing handler means the app process is not running the session.
        // The intent still succeeds: the Live Activity shows the reconnect
        // action rather than pretending the decision went through.
        guard let handler else { return }
        await handler(action)
    }

    private init() {}
}

// MARK: - Intents

@available(iOS 17.0, *)
public struct ConfirmBumpIntent: LiveActivityIntent {
    public static let title: LocalizedStringResource = "Confirm bump"
    public static let description = IntentDescription("Confirm that you bumped with this person.")
    /// Confirming shares your interests, so it is a consent action. It must not
    /// need the phone unlocked in this iteration, and it must not silently
    /// open the app.
    public static let openAppWhenRun = false

    @Parameter(title: "Session") public var sessionID: String
    @Parameter(title: "Proposal") public var proposalID: String

    public init() {}
    public init(sessionID: String, proposalID: String) {
        self.sessionID = sessionID
        self.proposalID = proposalID
    }

    public func perform() async throws -> some IntentResult {
        await BumpIntentBridge.shared.perform(.confirm(sessionID: sessionID, proposalID: proposalID))
        return .result()
    }
}

@available(iOS 17.0, *)
public struct RejectBumpIntent: LiveActivityIntent {
    public static let title: LocalizedStringResource = "Not this person"
    public static let description = IntentDescription("Dismiss this possible connection.")
    public static let openAppWhenRun = false

    @Parameter(title: "Session") public var sessionID: String
    @Parameter(title: "Proposal") public var proposalID: String

    public init() {}
    public init(sessionID: String, proposalID: String) {
        self.sessionID = sessionID
        self.proposalID = proposalID
    }

    public func perform() async throws -> some IntentResult {
        await BumpIntentBridge.shared.perform(.reject(sessionID: sessionID, proposalID: proposalID))
        return .result()
    }
}

@available(iOS 17.0, *)
public struct StopBumpIntent: LiveActivityIntent {
    public static let title: LocalizedStringResource = "Stop bumping"
    public static let description = IntentDescription("End this BUMP session.")
    public static let openAppWhenRun = false

    @Parameter(title: "Session") public var sessionID: String

    public init() {}
    public init(sessionID: String) { self.sessionID = sessionID }

    public func perform() async throws -> some IntentResult {
        await BumpIntentBridge.shared.perform(.stop(sessionID: sessionID))
        return .result()
    }
}
