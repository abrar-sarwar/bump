import Foundation

/// Decides WHEN to ask "what did you actually talk about?", and about whom.
///
/// Pure and clock-injected, in the spirit of `ProximityGate` and
/// `StreetPassEncounterGate`: no radios, no `Store`, no dates of its own, so the
/// whole policy is unit-testable without hardware.
///
/// This detects that the APP came back, not that the other person left. Bump has
/// no "they walked away" signal — the encounter gates rearm silently and the
/// transport only reports a hard disconnect — so the honest proxy is: they saved
/// the connection, put the phone away, talked, and came back. A dwell floor keeps
/// the prompt from landing while the conversation is still happening.
struct RatingPrompter {

    /// Don't ask the instant they tap Save; they are probably still talking.
    var minimumDwell: TimeInterval
    /// Past this, the conversation is no longer fresh enough to recall reliably,
    /// so stop asking unprompted. It stays rateable on demand forever.
    var staleAfter: TimeInterval

    /// Connections surfaced and waved off this launch, so "Not now" is respected
    /// for the rest of the session instead of reappearing on every foreground.
    private var dismissedThisSession: Set<UUID> = []

    init(minimumDwell: TimeInterval = 120,
         staleAfter: TimeInterval = 24 * 60 * 60) {
        self.minimumDwell = minimumDwell
        self.staleAfter = staleAfter
    }

    /// The connection to prompt about, or nil if none qualifies.
    ///
    /// When several qualify, the OLDEST is chosen: it is the closest to going
    /// stale, so it is the one whose answer we are about to lose.
    func next(connections: [SavedConnection],
              ratings: [UUID: InteractionRating],
              now: Date = Date()) -> SavedConnection? {
        connections
            .filter { eligible($0, ratings: ratings, now: now) }
            .min { $0.metOn < $1.metOn }
    }

    private func eligible(_ connection: SavedConnection,
                          ratings: [UUID: InteractionRating],
                          now: Date) -> Bool {
        // Already answered.
        guard ratings[connection.id] == nil else { return false }
        // Waved off this launch.
        guard !dismissedThisSession.contains(connection.id) else { return false }
        // Nothing to ask about. Asking "which of these landed?" with an empty
        // list is a question with no answers, so these are never prompted.
        guard !connection.insight.highlights.isEmpty else { return false }

        let age = now.timeIntervalSince(connection.metOn)
        return age >= minimumDwell && age <= staleAfter
    }

    /// Records a "Not now" so this launch stops asking about that connection.
    mutating func dismiss(_ id: UUID) {
        dismissedThisSession.insert(id)
    }
}
