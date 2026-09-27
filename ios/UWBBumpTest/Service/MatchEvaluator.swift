import Foundation

/// Decides whether an answer just produced a mutual match.
///
/// Pure and clock-injected, in the style of `RatingPrompter`: the rule is logic,
/// not presentation, and it is the one place that defines what "both liked each
/// other" means. Keeping it separate is what lets the truth table be tested
/// without a store, a sheet or a resolver.
struct MatchEvaluator {
    /// A new match, or `nil`.
    ///
    /// Returns `nil` — rather than the existing match — when the two already
    /// matched, so a caller can treat a non-nil result as "celebrate this now"
    /// without re-notifying on every subsequent re-rate.
    ///
    /// Requires an explicit yes from BOTH sides: a missing answer on either side
    /// is not a yes, which is what keeps someone who never answered the question
    /// from being matched by the other person's enthusiasm alone.
    func evaluate(rating: InteractionRating?,
                  partnerLike: PartnerLike,
                  existing: MutualMatch?,
                  now: Date = Date()) -> MutualMatch? {
        guard existing == nil else { return nil }
        guard let rating, rating.wantsToConnect == true else { return nil }
        guard partnerLike == .wantsToConnect else { return nil }
        return MutualMatch(id: rating.id, matchedOn: now)
    }
}
