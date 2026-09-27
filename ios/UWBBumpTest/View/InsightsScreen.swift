import SwiftUI

/// What the user's own history says about their mutual interests.
///
/// Every number here is a count over this person's own connections. There are no
/// percentages of "people like you", no compatibility scores and no population
/// claims — the app has no data that would make those true. `landed` is always
/// shown against how many of those conversations were actually rated, so a single
/// answer never reads as a pattern.
struct InsightsScreen: View {
    @ObservedObject var store: Store
    /// Opens the rating sheet for a connection still waiting on an answer.
    var onRate: (SavedConnection) -> Void

    private var trends: InterestTrends.Summary {
        InterestTrends.summarize(connections: store.connections, ratings: store.ratings)
    }

    var body: some View {
        Screen {
            let summary = trends
            VStack(alignment: .leading, spacing: Space.l) {
                PageTitle(title: "What lands",
                          subtitle: overview(summary))

                if summary.stats.isEmpty {
                    empty
                } else if summary.isTooSparse {
                    sparse(summary)
                } else {
                    ranked(summary)
                }

                if !store.unratedConnections.isEmpty {
                    waiting
                }

                NoticeText(text: "These answers never leave your phone. Nobody you have bumped can see them, and they are not sent to the BUMP server.",
                           icon: "lock.fill",
                           tone: .neutral)
            }
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(BumpColor.surface, for: .navigationBar)
    }

    private func overview(_ summary: InterestTrends.Summary) -> String {
        let people = summary.totalConnections == 1 ? "1 person met" : "\(summary.totalConnections) people met"
        return "\(people) · \(summary.ratedConnections) rated"
    }

    private var empty: some View {
        Card(style: .filled) {
            Text("Once you have bumped a few people and said what you talked about, the interests that actually start conversations show up here.")
                .font(BumpFont.bodyLarge)
                .foregroundStyle(BumpColor.onSurface)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// Below the threshold the app shows the history without ranking it. Three
    /// answers is not a trend, and presenting it as one would be a fabrication.
    private func sparse(_ summary: InterestTrends.Summary) -> some View {
        VStack(alignment: .leading, spacing: Space.s) {
            Eyebrow(text: "Not enough yet")
            Card(style: .filled) {
                Text("Rate a few more interactions and this starts to mean something. So far there are \(summary.ratedConnections) rated \(summary.ratedConnections == 1 ? "conversation" : "conversations") — too few to call anything a pattern.")
                    .font(BumpFont.bodyLarge)
                    .foregroundStyle(BumpColor.onSurface)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Eyebrow(text: "Shared ground so far")
                .padding(.top, Space.s)
            ForEach(summary.stats) { stat in
                HStack {
                    Text(stat.label)
                        .font(BumpFont.bodyLarge)
                        .foregroundStyle(BumpColor.onSurface)
                    Spacer(minLength: Space.m)
                    Text(stat.surfaced == 1 ? "1 person" : "\(stat.surfaced) people")
                        .font(BumpFont.labelMedium)
                        .foregroundStyle(BumpColor.onSurfaceVariant)
                }
                .padding(.vertical, Space.xs)
            }
        }
    }

    private func ranked(_ summary: InterestTrends.Summary) -> some View {
        VStack(alignment: .leading, spacing: Space.s) {
            Eyebrow(text: "What you actually talk about")
            ForEach(summary.stats) { stat in
                Card(style: .elevated) {
                    VStack(alignment: .leading, spacing: Space.xs) {
                        Text(stat.label)
                            .font(BumpFont.titleMedium)
                            .foregroundStyle(BumpColor.onSurface)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(detail(stat))
                            .font(BumpFont.bodyMedium)
                            .foregroundStyle(BumpColor.onSurfaceVariant)
                            .fixedSize(horizontal: false, vertical: true)
                        bar(stat)
                    }
                }
            }
        }
    }

    /// Stated against `rated`, never against `surfaced`: the app only knows about
    /// conversations the user answered for.
    private func detail(_ stat: InterestTrends.InterestStat) -> String {
        guard stat.rated > 0 else {
            return "Came up with \(stat.surfaced == 1 ? "1 person" : "\(stat.surfaced) people") · none rated yet"
        }
        let conversations = stat.rated == 1 ? "1 rated conversation" : "\(stat.rated) rated conversations"
        return "Talked about in \(stat.landed) of \(conversations)"
    }

    /// A plain proportional bar. No chart library: the shape is two rounded
    /// rectangles and the number is already stated in words above it.
    private func bar(_ stat: InterestTrends.InterestStat) -> some View {
        let fraction = stat.rated > 0 ? Double(stat.landed) / Double(stat.rated) : 0
        return GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(BumpColor.surfaceContainerHigh)
                Capsule().fill(BumpColor.primary)
                    .frame(width: max(0, geo.size.width * fraction))
            }
        }
        .frame(height: 6)
        .accessibilityHidden(true)      // the sentence above already says it
    }

    private var waiting: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            Eyebrow(text: "Waiting on you")
            ForEach(store.unratedConnections) { connection in
                Button {
                    onRate(connection)
                } label: {
                    HStack(spacing: Space.m) {
                        Avatar(name: connection.partnerName, size: 36, photo: connection.partnerPhoto)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(connection.partnerName)
                                .font(BumpFont.bodyLarge)
                                .foregroundStyle(BumpColor.onSurface)
                            Text(connection.metOn.formatted(date: .abbreviated, time: .omitted))
                                .font(BumpFont.bodySmall)
                                .foregroundStyle(BumpColor.onSurfaceVariant)
                        }
                        Spacer(minLength: 0)
                        StatusPill(text: "Rate", tone: .active)
                    }
                    .padding(.vertical, Space.xs)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                // A connection with no shared ground has nothing to ask about.
                .disabled(connection.insight.highlights.isEmpty)
                .opacity(connection.insight.highlights.isEmpty ? 0.45 : 1)
            }
        }
    }
}

#Preview("Insights") {
    NavigationStack {
        InsightsScreen(store: PreviewFixtures.ratedStore(), onRate: { _ in })
    }
}
