import SwiftUI

/// What the user's own history says about their mutual interests, as data.
///
/// Every figure here is a count over this person's own connections. There are no
/// percentages of "people like you", no compatibility scores and no population
/// claims — the app has no data that would make those true. Rates are always
/// drawn with their denominator visible (the bar shows landed AND missed, the
/// table prints "2/3"), and a low sample count is labelled as one rather than
/// quietly rendered as a confident percentage.
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
                ScreenTitle("What lands")

                metrics(summary)

                if summary.isTooSparse && summary.ratedInstances > 0 {
                    lowSampleBanner(summary)
                }

                if summary.charted.isEmpty {
                    empty
                } else {
                    chart(summary)
                    table(summary)
                }

                if !summary.unrated.isEmpty {
                    unratedInterests(summary)
                }

                if !store.unratedConnections.isEmpty {
                    waiting
                }

                InfoNotice(text: "These answers never leave your phone. Nobody you have bumped can see them, and they are not sent to the BUMP server.",
                           icon: "lock.fill",
                           tone: .neutral)
            }
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(BumpColor.surface, for: .navigationBar)
    }

    // MARK: Headline metrics

    private func metrics(_ summary: InterestTrends.Summary) -> some View {
        HStack(spacing: Space.s) {
            metric(value: "\(summary.totalConnections)", caption: "met")
            metric(value: "\(summary.ratedConnections)", caption: "rated")
            metric(value: summary.landingRate.map { Self.percent($0) } ?? "—",
                   caption: "hit rate",
                   footnote: summary.ratedInstances > 0
                     ? "\(summary.landedInstances)/\(summary.ratedInstances)" : "no data")
        }
        .frame(maxWidth: .infinity)
    }

    private func metric(value: String, caption: String, footnote: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(BumpFont.display)
                .foregroundStyle(BumpColor.onSurface)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(caption.uppercased())
                .font(BumpFont.labelSmall)
                .kerning(0.8)
                .foregroundStyle(BumpColor.onSurfaceVariant)
            // The denominator, always. A rate with no n is not a finding.
            Text(footnote ?? " ")
                .font(BumpFont.bodySmall)
                .foregroundStyle(BumpColor.onSurfaceVariant)
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Space.m)
        .background(
            RoundedRectangle(cornerRadius: Space.corner, style: .continuous)
                .fill(BumpColor.track)
        )
    }

    /// Says the sample is small instead of hiding the numbers. The data is the
    /// user's own and they are entitled to see it; what it must not do is imply
    /// a pattern that three answers cannot support.
    private func lowSampleBanner(_ summary: InterestTrends.Summary) -> some View {
        HStack(alignment: .top, spacing: Space.sm) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(BumpColor.warning)
                .padding(.top, 2)
            Text("Low sample: \(summary.ratedConnections) rated \(summary.ratedConnections == 1 ? "conversation" : "conversations"). Read these as counts, not as a trend.")
                .font(BumpFont.bodySmall)
                .foregroundStyle(BumpColor.onSurfaceVariant)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Space.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            Wash.peach.background
                .clipShape(RoundedRectangle(cornerRadius: Space.corner, style: .continuous))
        )
    }

    // MARK: Chart

    /// Landed vs missed per interest, as one track per interest. Drawing the
    /// misses rather than a bare percentage keeps the sample size visible: a
    /// 1-of-1 bar is visibly one unit wide, because every track is scaled
    /// against the busiest interest rather than against itself.
    private func chart(_ summary: InterestTrends.Summary) -> some View {
        let widest = max(summary.charted.map(\.rated).max() ?? 1, 1)
        return VStack(alignment: .leading, spacing: Space.s) {
            Eyebrow("Rated conversations per interest")
            VStack(alignment: .leading, spacing: Space.sm) {
                ForEach(summary.charted) { stat in
                    bar(stat, widest: widest)
                }
            }
            legend
                .padding(.top, Space.xs)
        }
        .padding(Space.m)
        .background(
            RoundedRectangle(cornerRadius: Space.corner, style: .continuous)
                .fill(BumpColor.surfaceContainerLowest)
        )
    }

    private func bar(_ stat: InterestTrends.InterestStat, widest: Int) -> some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            HStack(spacing: Space.s) {
                Text(stat.label)
                    .font(BumpFont.labelMedium)
                    .foregroundStyle(BumpColor.onSurface)
                    .lineLimit(1)
                Spacer(minLength: Space.xs)
                Text("\(stat.landed)/\(stat.rated)")
                    .font(BumpFont.bodySmall)
                    .monospacedDigit()
                    .foregroundStyle(stat.landed > 0 ? BumpColor.primary : BumpColor.onSurfaceVariant)
            }
            // Segment widths are a real proportion of the row, and every row
            // is scaled against the busiest interest rather than against
            // itself, so a 1-of-1 bar reads as one unit and not as a full bar.
            GeometryReader { geo in
                let unit = geo.size.width / CGFloat(widest)
                HStack(spacing: 0) {
                    Capsule().fill(BumpColor.primary)
                        .frame(width: unit * CGFloat(stat.landed))
                    Capsule().fill(BumpColor.track)
                        .frame(width: unit * CGFloat(stat.missed))
                    Spacer(minLength: 0)
                }
            }
            .frame(height: 10)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(stat.label): talked about in \(stat.landed) of \(stat.rated) rated conversations")
    }

    private var legend: some View {
        HStack(spacing: Space.m) {
            legendKey(color: BumpColor.primary, label: "Talked about")
            legendKey(color: BumpColor.track, label: "Didn\u{2019}t come up")
        }
        .accessibilityHidden(true)
    }

    private func legendKey(color: Color, label: String) -> some View {
        HStack(spacing: Space.xs) {
            Capsule().fill(color).frame(width: 14, height: 8)
            Text(label)
                .font(BumpFont.bodySmall)
                .foregroundStyle(BumpColor.onSurfaceVariant)
        }
    }

    // MARK: Table

    private func table(_ summary: InterestTrends.Summary) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Eyebrow("Interest")
                Spacer()
                Eyebrow("Hit")
                    .frame(width: 52, alignment: .trailing)
                Eyebrow("Seen")
                    .frame(width: 44, alignment: .trailing)
                Eyebrow("Last")
                    .frame(width: 56, alignment: .trailing)
            }
            .padding(.bottom, Space.xs)

            Divider().overlay(BumpColor.outlineVariant)

            ForEach(summary.charted) { stat in
                HStack {
                    Text(stat.label)
                        .font(BumpFont.bodyMedium)
                        .foregroundStyle(BumpColor.onSurface)
                        .lineLimit(1)
                    Spacer(minLength: Space.xs)
                    Text("\(stat.landed)/\(stat.rated)")
                        .font(BumpFont.bodyMedium)
                        .monospacedDigit()
                        .foregroundStyle(stat.landed > 0 ? BumpColor.primary : BumpColor.onSurfaceVariant)
                        .frame(width: 52, alignment: .trailing)
                    Text("\(stat.surfaced)")
                        .font(BumpFont.bodyMedium)
                        .monospacedDigit()
                        .foregroundStyle(BumpColor.onSurfaceVariant)
                        .frame(width: 44, alignment: .trailing)
                    Text(stat.lastSurfaced.formatted(.dateTime.month(.abbreviated).day()))
                        .font(BumpFont.bodySmall)
                        .monospacedDigit()
                        .foregroundStyle(BumpColor.onSurfaceVariant)
                        .frame(width: 56, alignment: .trailing)
                }
                .padding(.vertical, Space.xs)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(stat.label): talked about in \(stat.landed) of \(stat.rated) rated conversations, seen \(stat.surfaced) times")

                Divider().overlay(BumpColor.outlineVariant.opacity(0.5))
            }
        }
        .padding(Space.m)
        .background(
            RoundedRectangle(cornerRadius: Space.corner, style: .continuous)
                .fill(BumpColor.surfaceContainerLowest)
        )
    }

    /// Interests that have come up but never in a conversation with an answer.
    /// Kept out of the chart, because a bar with no denominator is not a
    /// measurement of anything.
    private func unratedInterests(_ summary: InterestTrends.Summary) -> some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            Eyebrow("Seen, not yet rated")
            ForEach(summary.unrated) { stat in
                HStack {
                    Text(stat.label)
                        .font(BumpFont.bodyMedium)
                        .foregroundStyle(BumpColor.onSurfaceVariant)
                    Spacer()
                    Text("\(stat.surfaced)×")
                        .font(BumpFont.bodyMedium)
                        .monospacedDigit()
                        .foregroundStyle(BumpColor.onSurfaceVariant)
                }
                .padding(.vertical, 2)
            }
        }
    }

    private var empty: some View {
        Card(style: .filled) {
            Text("No rated conversations yet. Rate one and the breakdown appears here.")
                .font(BumpFont.bodyLarge)
                .foregroundStyle(BumpColor.onSurface)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var waiting: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            Eyebrow("Waiting on you")
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
                        StatusPill(text: "Rate", tone: .active, icon: "text.bubble.fill")
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

    /// Whole percent. Never shown without its "landed/rated" footnote.
    private static func percent(_ fraction: Double) -> String {
        "\(Int((fraction * 100).rounded()))%"
    }
}

#Preview("Insights") {
    NavigationStack {
        InsightsScreen(store: PreviewFixtures.ratedStore(), onRate: { _ in })
    }
}
