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
        /// The most recent connection this came up in, for the recency column.
        var lastSurfaced: Date

        /// Landed over rated. `nil` when nothing has been rated yet: there is no
        /// rate to report, and 0 would read as "never lands" rather than "unknown".
        var landingRate: Double? {
            guard rated > 0 else { return nil }
            return Double(landed) / Double(rated)
        }

        /// Rated conversations where this did NOT come up. The other half of the
        /// bar, so the chart shows the denominator instead of implying it.
        var missed: Int { rated - landed }
    }

    struct Summary: Equatable, Sendable {
        var totalConnections: Int
        var ratedConnections: Int
        /// Ranked: most landed first, then most surfaced, then id so the order
        /// is stable across launches.
        var stats: [InterestStat]
        /// Too few answers to say anything honest about trends.
        var isTooSparse: Bool
        /// Shared-interest appearances across every rated connection, and how
        /// many of them the user said were talked about. The headline figure,
        /// always carried with its denominator.
        var ratedInstances: Int
        var landedInstances: Int

        /// Landed over rated across everything. `nil` before anything is rated.
        var landingRate: Double? {
            guard ratedInstances > 0 else { return nil }
            return Double(landedInstances) / Double(ratedInstances)
        }

        /// Interests with at least one answer, which are the only ones that can
        /// honestly appear in a rate chart.
        var charted: [InterestStat] { stats.filter { $0.rated > 0 } }
        /// Seen, but never in a conversation the user answered for.
        var unrated: [InterestStat] { stats.filter { $0.rated == 0 } }
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
                                                    surfaced: 0, rated: 0, landed: 0,
                                                    lastSurfaced: connection.metOn)
                stat.surfaced += 1
                stat.lastSurfaced = max(stat.lastSurfaced, connection.metOn)
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
                       isTooSparse: ratedConnections < minimumRated,
                       ratedInstances: stats.reduce(0) { $0 + $1.rated },
                       landedInstances: stats.reduce(0) { $0 + $1.landed })
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
