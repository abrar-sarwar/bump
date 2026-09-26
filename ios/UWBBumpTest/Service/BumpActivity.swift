import Foundation
#if canImport(ActivityKit)
import ActivityKit
#endif

/// The contract between the app and the Live Activity / Dynamic Island.
///
/// This file is compiled into BOTH the app and the widget extension, so it must
/// stay free of sensors, transports and anything else that only exists in the
/// app process.
///
/// Deliberately small. ActivityKit content is delivered through the system and
/// is visible wherever the Live Activity is rendered, so it carries only what
/// the presentation needs:
///   - no discovery tokens
///   - no interest profiles
///   - no raw sensor samples
/// A candidate is identified by an opaque proposal id plus a display name, and
/// the authoritative state stays in the app.
enum BumpActivity {

    /// Bumped when the shape of the content changes in a way older widget code
    /// could not render. The widget refuses to guess at unknown versions.
    static let schema = 1

    /// How long a session runs before it expires on its own.
    static let defaultSessionMinutes = 30

    /// After this long without an update, the presentation must stop claiming
    /// it is ready. ActivityKit renders the stale view past this date.
    static let staleAfter: TimeInterval = 90
}

/// The one user-facing state the Dynamic Island shows.
///
/// Distinct from `BumpEngine.Phase`: that is the internal machine, this is what
/// a person reads at a glance. Keeping them separate means a delayed interface
/// update can never feed back into a matching decision.
enum BumpActivityState: String, Codable, Hashable, Sendable {
    case preparing
    case discovering
    case ready
    case candidate           // a possible connection is waiting on this person
    case awaitingMe          // shown after a reject/confirm race, needs this person
    case awaitingPeer        // this person confirmed, the other has not
    case connected
    case paused
    case unavailable         // services lost; the app has to be opened
    case ended

    /// Short status line. No em dashes.
    var headline: String {
        switch self {
        case .preparing:   return "Getting ready"
        case .discovering: return "Looking for nearby people"
        case .ready:       return "Ready to bump"
        case .candidate:   return "Possible connection"
        case .awaitingMe:  return "Possible connection"
        case .awaitingPeer:return "Waiting for confirmation"
        case .connected:   return "You're connected"
        case .paused:      return "Paused"
        case .unavailable: return "Open BUMP to reconnect"
        case .ended:       return "Session ended"
        }
    }

    /// True when the person has a decision to make right now.
    var needsDecision: Bool { self == .candidate || self == .awaitingMe }
}

#if canImport(ActivityKit)

@available(iOS 16.2, *)
struct BumpActivityAttributes: ActivityAttributes {

    /// Fixed for the life of the session.
    let sessionID: String
    /// When the session expires on its own, so the widget can show the
    /// remaining time without the app pushing a tick every second.
    let expiresAt: Date
    let schema: Int

    struct ContentState: Codable, Hashable {
        var state: BumpActivityState
        /// Display name of the current candidate or confirmed partner. Nil in
        /// every state that has no person attached.
        var peerName: String?
        /// Opaque id, validated against live state before any action is honoured.
        var proposalID: String?
        /// When the current proposal stops being actionable.
        var proposalExpiresAt: Date?
        /// How many other BUMP users are currently visible. Coarse on purpose.
        var nearbyCount: Int
        /// Set once a connection is saved, so the completed activity can deep
        /// link to the right row.
        var connectionID: String?
        /// Why the session is unavailable, when it is. Short, human, no jargon.
        var unavailableReason: String?

        static func preparing() -> ContentState {
            ContentState(state: .preparing, nearbyCount: 0)
        }
    }
}

#endif
