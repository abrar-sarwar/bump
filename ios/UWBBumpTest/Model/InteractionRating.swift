import Foundation

/// What actually happened in an interaction, recorded privately by one person.
///
/// `landedInterestIDs` is local only: never exchanged with the partner, never
/// written into `connections.json`, never sent to the BUMP server or xAI. The
/// partner's phone has its own, possibly different, answer and the two never meet.
///
/// `wantsToConnect` is the ONE field that can be shared, and only in one
/// direction: if both people answered yes, both learn it. A no is never
/// revealed, and neither is the absence of an answer — the partner cannot tell
/// a no from a not-asked-yet. See `MatchEvaluator`.
///
/// Deliberately NOT recorded: a score, a grade, tags, or free text. The only
/// questions asked are which of the shared interests were actually talked
/// about, and whether you'd want to connect again — the two answers the app can
/// act on honestly.
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
    /// Whether the user would want to connect with this person again.
    ///
    /// `nil` means the question was not answered, which is deliberately DISTINCT
    /// from a recorded `false`: a match needs an explicit yes from both sides, so
    /// skipping the question can never produce one. Changeable — re-rating may
    /// flip it, and a yes that arrives later still matches.
    ///
    /// Optional on the way in too (the synthesised decoder treats a missing key
    /// for an optional as `nil`), so a `ratings.json` written before this field
    /// existed still loads, as every unanswered.
    var wantsToConnect: Bool?

    init(id: UUID, ratedOn: Date = Date(), landedInterestIDs: [String],
         wantsToConnect: Bool? = nil) {
        self.id = id
        self.ratedOn = ratedOn
        // Sorted so two equal answers compare equal regardless of tap order.
        self.landedInterestIDs = landedInterestIDs.sorted()
        self.wantsToConnect = wantsToConnect
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
