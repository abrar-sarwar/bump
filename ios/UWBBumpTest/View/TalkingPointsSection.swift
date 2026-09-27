import SwiftUI

/// Talking points, split into what both people listed and what's merely
/// related. A complementary point is framed as something to ask about — never
/// as a claim that the two people share it. Shown as chat bubbles, with the
/// evidence from both cards under each.
struct TalkingPointsSection: View {
    let points: [TalkingPoint]

    // Shared points attached to a highlight are shown on that card instead
    // (see `TalkingPromptLine`); what arrives here is everything else.
    private var shared: [TalkingPoint] { points.filter { $0.kind == .shared } }
    private var complementary: [TalkingPoint] { points.filter { $0.kind == .complementary } }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            if !shared.isEmpty {
                group("You both listed", shared)
            }
            if !complementary.isEmpty {
                group("Worth asking about", complementary)
            }
            if let label = sourceLabel {
                Text(label)
                    .font(BumpFont.caption2)
                    .foregroundStyle(BumpColor.faint)
                    .padding(.horizontal, 6)
            }
        }
    }

    /// One label when every point came from the same place (the usual case).
    private var sourceLabel: String? {
        let sources = Set(points.map(\.source))
        guard sources.count == 1, let only = sources.first else { return "Some written by a model, some suggested" }
        return only == .fallbackTemplate ? "Suggested questions, built from both cards" : only.label
    }

    private func group(_ title: String, _ items: [TalkingPoint]) -> some View {
        VStack(alignment: .leading, spacing: Space.s) {
            Eyebrow(title)
                .padding(.horizontal, Space.xs)
            ForEach(items) { point in
                Card {
                    VStack(alignment: .leading, spacing: Space.xs) {
                        Text(point.prompt)
                            .font(BumpFont.bodyEmphasis)
                        // Evidence from BOTH approved cards.
                        Text("You: “\(point.yourEntry)” · Them: “\(point.theirEntry)”")
                            .font(BumpFont.caption2)
                            .foregroundStyle(BumpColor.faint)
                    }
                }
                .accessibilityElement(children: .combine)
            }
        }
    }
}

/// A talking point's question, shown under the highlight it belongs to.
struct TalkingPromptLine: View {
    let point: TalkingPoint

    var body: some View {
        HStack(alignment: .top, spacing: Space.s) {
            Image(systemName: "bubble.left.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(BumpColor.primary)
                .padding(.top, 3)
            VStack(alignment: .leading, spacing: 2) {
                Text(point.prompt)
                    .font(BumpFont.captionEmphasis)
                    .foregroundStyle(BumpColor.primary)
                    .fixedSize(horizontal: false, vertical: true)
                if point.source == .grok {
                    Text(point.source.label)
                        .font(BumpFont.caption2)
                        .foregroundStyle(BumpColor.faint)
                }
            }
        }
        .padding(.top, Space.xs)
    }
}
