import Foundation

/// Both people said, privately and independently, that they'd want to connect
/// again. Recording it is what unlocks the partner's full profile.
///
/// Sticky on purpose: once a match exists it is never removed (short of deleting
/// the connection). Someone who has already seen a profile cannot un-see it, so
/// pretending to take it back would be a lie, and flipping your own answer later
/// must not silently revoke what the other person already has.
///
/// Local only, like `InteractionRating`. Nothing about a match is sent to the
/// BUMP server or xAI.
struct MutualMatch: Codable, Equatable, Identifiable, Sendable {
    /// Matches `SavedConnection.id`, which is how a match finds its connection.
    var id: UUID
    var matchedOn: Date

    init(id: UUID, matchedOn: Date = Date()) {
        self.id = id
        self.matchedOn = matchedOn
    }
}

extension MutualMatch {
    // MARK: On-disk form

    /// The form `matches.json` holds: a flat array, newest first. Same shape and
    /// same reasoning as `InteractionRating.persistable` — `UUID` is not a string
    /// coding key, so a dictionary would encode unreadably.
    static func persistable(_ index: [UUID: MutualMatch]) -> [MutualMatch] {
        index.values.sorted { $0.matchedOn > $1.matchedOn }
    }

    /// Rebuilds the in-memory index from what was on disk. Duplicates for one
    /// connection resolve to the EARLIEST match: the moment it first happened is
    /// the true one.
    static func index(_ matches: [MutualMatch]) -> [UUID: MutualMatch] {
        Dictionary(matches.map { ($0.id, $0) },
                   uniquingKeysWith: { a, b in a.matchedOn <= b.matchedOn ? a : b })
    }
}
