import Foundation

/// What actually happened in an interaction, recorded privately by one person.
///
/// Local only. A rating is never exchanged with the partner, never written into
/// `connections.json`, and never sent to the BUMP server or xAI. The partner's
/// phone has its own, possibly different, answer and the two never meet.
///
/// Deliberately NOT recorded: a score, a grade, tags, or free text. The only
/// question asked is which of the shared interests were actually talked about,
/// because that is the one answer the app can act on honestly.
struct InteractionRating: Codable, Equatable, Identifiable, Sendable {
    /// Matches `SavedConnection.id`, which is how a rating finds its connection.
    var id: UUID
    var ratedOn: Date
    /// Canonical interest ids (`SharedHighlight.interestID`) the user said they
    /// actually talked about.
    ///
    /// Empty is a real answer: "none of these landed". That is different from
    /// never having been asked, which is the ABSENCE of an `InteractionRating`.
    var landedInterestIDs: [String]

    init(id: UUID, ratedOn: Date = Date(), landedInterestIDs: [String]) {
        self.id = id
        self.ratedOn = ratedOn
        // Sorted so two equal answers compare equal regardless of tap order.
        self.landedInterestIDs = landedInterestIDs.sorted()
    }
}

extension InteractionRating {
    /// The user's own wording for each shared interest they said was actually
    /// talked about, in the order the highlights were presented.
    ///
    /// Lives here rather than in a view because two screens need the same answer
    /// and the rule — intersect the recorded ids with the highlights actually on
    /// this connection — is logic, not presentation. Recorded ids with no
    /// matching highlight are dropped: the connection is the source of truth for
    /// what was on offer.
    func landedEntries(among highlights: [SharedHighlight]) -> [String] {
        let landed = Set(landedInterestIDs)
        return highlights.filter { landed.contains($0.interestID) }.map(\.yourEntry)
    }

    // MARK: On-disk form

    /// The form `ratings.json` holds: a flat array, newest answer first.
    ///
    /// Not a dictionary, because `UUID` is not a string coding key and
    /// `[UUID: _]` would encode as an alternating key/value array that is
    /// unreadable on disk.
    static func persistable(_ index: [UUID: InteractionRating]) -> [InteractionRating] {
        index.values.sorted { $0.ratedOn > $1.ratedOn }
    }

    /// Rebuilds the in-memory index from what was on disk.
    ///
    /// Because the file is an array, nothing structurally prevents two entries
    /// for one connection — a half-written file, or a future merge across
    /// devices. The NEWEST answer wins: it is the one the user gave last.
    static func index(_ ratings: [InteractionRating]) -> [UUID: InteractionRating] {
        Dictionary(ratings.map { ($0.id, $0) },
                   uniquingKeysWith: { a, b in a.ratedOn >= b.ratedOn ? a : b })
    }
}
