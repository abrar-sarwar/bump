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
