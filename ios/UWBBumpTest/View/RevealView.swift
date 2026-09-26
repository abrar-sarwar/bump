import SwiftUI

/// The payoff screen, in the site's "overlap" language: the shared badge
/// cycling through what you both listed, the evidence as pill rows, and the
/// opener as your own blue bubble. No artificial delay; the reveal animates as
/// soon as the result exists.
struct RevealView: View {
    let result: BumpEngine.Result
    let myName: String
    var myPhoto: Data? = nil
    var onSave: () -> Void
    var onAgain: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var revealed = false

    private var hasOverlap: Bool { !result.insight.highlights.isEmpty }

    var body: some View {
        Screen(backdrop: .hero) {
            VStack(alignment: .leading, spacing: Space.l) {

                VStack(spacing: Space.s) {
                    HStack(spacing: -12) {
                        Avatar(name: myName, size: 52, photo: myPhoto)
                        Avatar(name: result.partner.displayName, size: 52, tint: BumpColor.illustrationWarm,
                               photo: result.partner.photo)
                    }
                    Text("\(myName.isEmpty ? "You" : myName) + \(result.partner.displayName)")
                        .font(BumpFont.bodyEmphasis)
                        .foregroundStyle(BumpColor.navy)
                        .multilineTextAlignment(.center)
                    StatusPill(text: result.evidence.label,
                               tone: result.evidence == .manualSelection ? .warn : .good)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, Space.m)

                ScreenTitle(hasOverlap ? "You have more in common than you think." : "Nice to meet you.",
                            alignment: .center)
                    .frame(maxWidth: .infinity)

                if hasOverlap {
                    // Cycles through every interest you both actually listed.
                    SharedBadge(kicker: "You both share this",
                                interests: result.insight.highlights.map(\.yourEntry),
                                size: 230, popIn: true)
                        .frame(maxWidth: .infinity)

                    VStack(alignment: .leading, spacing: Space.s) {
                        Eyebrow("Specific things you share")
                            .padding(.horizontal, Space.xs)

                        ForEach(Array(result.insight.highlights.enumerated()), id: \.element.id) { index, highlight in
                            RowPill(block: true) {
                                IconOrb(systemImage: "sparkles", size: 44)
                            } content: {
                                RowText.title(highlight.statement)
                                // Evidence: the entry in each profile that
                                // supports the claim. Collapsed when both
                                // profiles hold the identical entry.
                                RowText.subtitle(highlight.yourEntry == highlight.theirEntry
                                     ? "Both of you list “\(highlight.yourEntry)”"
                                     : "You listed “\(highlight.yourEntry)” · they listed “\(highlight.theirEntry)”")
                                if let point = result.insight.point(for: highlight) {
                                    TalkingPromptLine(point: point)
                                }
                            }
                            .opacity(revealed ? 1 : 0)
                            .offset(y: revealed ? 0 : 12)
                            .animation(reduceMotion ? nil
                                       : BumpMotion.emphasizedIn.delay(0.15 + Double(index) * 0.09),
                                       value: revealed)
                        }

                        Text("Ranked by how specific they are, not by how rare they are. We don't have data on how common an interest is, so we don't claim to.")
                            .font(BumpFont.caption2)
                            .foregroundStyle(BumpColor.faint)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.horizontal, Space.xs)
                    }
                } else {
                    Card(padding: 22) {
                        Text("Your lists don't overlap yet, which is its own kind of interesting.")
                            .font(BumpFont.body)
                            .foregroundStyle(BumpColor.navy)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                if !result.insight.unattachedPoints.isEmpty {
                    TalkingPointsSection(points: result.insight.unattachedPoints)
                }

                VStack(alignment: .leading, spacing: Space.s) {
                    Eyebrow("Something to talk about")
                        .padding(.horizontal, Space.xs)
                    // A template is never passed off as an AI result: the
                    // source label rides above the bubble.
                    ChatBubble(isMe: true, who: result.insight.openerSource.label) {
                        Text(result.insight.opener)
                            .font(BumpFont.archivo(Archivo.semibold, 19, relativeTo: .title3))
                    }
                }
                .opacity(revealed ? 1 : 0)
                .animation(reduceMotion ? nil : BumpMotion.emphasizedIn.delay(0.3), value: revealed)

                VStack(spacing: Space.s) {
                    Button(action: onSave) {
                        TrailingIconLabel("Save connection", systemImage: "bookmark.fill")
                    }
                    .buttonStyle(.bumpPrimary)
                    Button("Bump again", action: onAgain)
                        .buttonStyle(.bumpSecondary)
                }
                .padding(.top, Space.s)
            }
        }
        .onAppear { revealed = true }
    }
}

#Preview {
    RevealView(result: PreviewFixtures.result, myName: "Jared", onSave: {}, onAgain: {})
}
