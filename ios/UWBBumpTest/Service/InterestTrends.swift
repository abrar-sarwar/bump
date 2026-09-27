import Foundation

/// Aggregates private ratings into a picture of which mutual interests actually
/// carry conversations. Pure and synchronous, like `InterestMatcher`.
///
/// `InterestMatcher` is explicit that rarity percentages are deliberately not
/// computed, because there is no population data to support them. This holds the
/// same line: every number here is a count over the USER'S OWN connections, and
/// `landed` is always reported against `rated`, never against `surfaced`, so a
/// one-of-one can never read as a certainty. Below `minimumRated` answers the
/// summary declares itself too sparse and the UI says so instead of ranking noise.
enum InterestTrends {

    /// One mutual interest, and how it has actually gone.
    struct InterestStat: Identifiable, Equatable, Sendable {
        /// Canonical interest id, from `SharedHighlight.interestID`.
        let id: String
        /// The user's own wording for it.
        let label: String
        /// Connections where this came up as shared ground.
        var surfaced: Int
        /// Of those, how many the user has answered for at all. The honest
        /// denominator for `landed`.
        var rated: Int
        /// Of the rated ones, how many the user said this was talked about in.
        var landed: Int
    }

    struct Summary: Equatable, Sendable {
        var totalConnections: Int
        var ratedConnections: Int
        /// Ranked: most landed first, then most surfaced, then id so the order
        /// is stable across launches.
        var stats: [InterestStat]
        /// Too few answers to say anything honest about trends.
        var isTooSparse: Bool
    }

    /// How many rated connections it takes before trends are worth stating.
    static let defaultMinimumRated = 3

    static func summarize(connections: [SavedConnection],
                          ratings: [UUID: InteractionRating],
                          minimumRated: Int = defaultMinimumRated) -> Summary {
        var byID: [String: InterestStat] = [:]

        for connection in connections {
            let rating = ratings[connection.id]
            let landed = Set(rating?.landedInterestIDs ?? [])

            for highlight in connection.insight.highlights {
                let id = highlight.interestID
                var stat = byID[id] ?? InterestStat(id: id,
                                                    label: label(for: highlight),
                                                    surfaced: 0, rated: 0, landed: 0)
                stat.surfaced += 1
                if rating != nil {
                    stat.rated += 1
                    if landed.contains(id) { stat.landed += 1 }
                }
                byID[id] = stat
            }
        }

        let ratedConnections = connections.filter { ratings[$0.id] != nil }.count

        let stats = byID.values.sorted {
            if $0.landed != $1.landed { return $0.landed > $1.landed }
            if $0.surfaced != $1.surfaced { return $0.surfaced > $1.surfaced }
            return $0.id < $1.id
        }

        return Summary(totalConnections: connections.count,
                       ratedConnections: ratedConnections,
                       stats: stats,
                       isTooSparse: ratedConnections < minimumRated)
    }

    /// The user's own wording, tidied through the catalog so two spellings of the
    /// same interest don't read as two different things. Falls back to the raw
    /// entry: a custom interest the catalog doesn't know is still the user's.
    private static func label(for highlight: SharedHighlight) -> String {
        let mine = highlight.yourEntry.trimmed()
        guard !mine.isEmpty else { return highlight.statement }
        return InterestCatalog.canonical(from: mine)?.label ?? mine
    }
}
