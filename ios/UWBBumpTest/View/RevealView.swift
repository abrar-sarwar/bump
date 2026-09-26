import SwiftUI

/// The payoff screen. No artificial delay: the reveal animates as soon as the
/// result exists.
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
        Screen {
            VStack(alignment: .leading, spacing: Space.l) {

                // Hero: the two people, meeting.
                VStack(alignment: .leading, spacing: Space.m) {
                    HStack(spacing: -18) {
                        Avatar(name: myName, size: 72, photo: myPhoto)
                            .overlay(Circle().strokeBorder(BumpColor.primaryContainer, lineWidth: 3))
                            .offset(x: revealed ? 0 : -16)
                        Avatar(name: result.partner.displayName, size: 72, tint: BumpColor.illustrationWarm,
                               photo: result.partner.photo)
                            .overlay(Circle().strokeBorder(BumpColor.primaryContainer, lineWidth: 3))
                            .offset(x: revealed ? 0 : 16)
                    }
                    .padding(.top, Space.m)

                    VStack(alignment: .leading, spacing: Space.s) {
                        Text(hasOverlap ? "You have more in common than you think." : "Nice to meet you.")
                            .font(BumpFont.displaySmall)
                            .foregroundStyle(BumpColor.onPrimaryContainer)
                            .fixedSize(horizontal: false, vertical: true)
                        Text("\(myName.isEmpty ? "You" : myName) + \(result.partner.displayName)")
                            .font(BumpFont.titleMedium)
                            .foregroundStyle(BumpColor.onPrimaryContainer)
                            .fixedSize(horizontal: false, vertical: true)
                        HStack(spacing: 6) {
                            Image(systemName: "checkmark.seal.fill").font(.system(size: 12, weight: .bold))
                            Text(result.evidence.label).font(BumpFont.labelMedium)
                        }
                        .foregroundStyle(BumpColor.onPrimaryContainer)
                        .padding(.horizontal, 10)
                        .frame(height: 28)
                        .background(Capsule().fill(BumpColor.surfaceContainerLowest.opacity(0.6)))
                    }
                }
                .padding(Space.l)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: Radius.extraLarge, style: .continuous)
                        .fill(BumpColor.primaryContainer)
                        .overlay(alignment: .topTrailing) {
                            LobedShape(lobes: 7, amplitude: 0.1)
                                .fill(BumpColor.brand.opacity(0.28))
                                .frame(width: 180, height: 180)
                                .offset(x: 50, y: -60)
                        }
                        .clipShape(RoundedRectangle(cornerRadius: Radius.extraLarge, style: .continuous))
                )
                .scaleEffect(revealed ? 1 : 0.96)
                .opacity(revealed ? 1 : 0)

                if hasOverlap {
                    VStack(alignment: .leading, spacing: Space.s) {
                        Eyebrow(text: "Specific things you share")

                        ForEach(Array(result.insight.highlights.enumerated()), id: \.element.id) { index, highlight in
                            HighlightCard(highlight: highlight, point: result.insight.point(for: highlight))
                                .opacity(revealed ? 1 : 0)
                                .offset(y: revealed ? 0 : 16)
                                .animation(reduceMotion ? nil
                                           : Motion.spatial.delay(0.12 + Double(index) * 0.08),
                                           value: revealed)
                        }

                        Text("Ranked by how specific they are, not by how rare they are. We don't have data on how common an interest is, so we don't claim to.")
                            .font(BumpFont.bodySmall)
                            .foregroundStyle(BumpColor.onSurfaceVariant)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                } else {
                    Card {
                        Text("Your lists don't overlap yet, which is its own kind of interesting.")
                            .font(BumpFont.bodyLarge)
                            .foregroundStyle(BumpColor.onSurface)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                if !result.insight.unattachedPoints.isEmpty {
                    TalkingPointsSection(points: result.insight.unattachedPoints)
                }

                VStack(alignment: .leading, spacing: Space.s) {
                    Eyebrow(text: "Something to talk about")
                    OpenerCard(opener: result.insight.opener, source: result.insight.openerSource.label)
                        .opacity(revealed ? 1 : 0)
                        .offset(y: revealed ? 0 : 16)
                        .animation(reduceMotion ? nil : Motion.spatial.delay(0.35), value: revealed)
                }

                VStack(spacing: Space.sm) {
                    Button("Save connection", systemImage: "person.badge.plus", action: onSave)
                        .buttonStyle(.bumpPrimary)
                    Button("Bump again", action: onAgain)
                        .buttonStyle(.bumpSecondary)
                }
                .padding(.top, Space.s)
            }
        }
        .onAppear {
            if reduceMotion { revealed = true } else { withAnimation(Motion.expressive) { revealed = true } }
        }
    }
}

/// One shared, specific thing, with the evidence from both cards.
struct HighlightCard: View {
    let highlight: SharedHighlight
    var point: TalkingPoint?

    var body: some View {
        Card {
            HStack(alignment: .top, spacing: Space.m) {
                Image(systemName: "sparkle")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(BumpColor.tertiary)
                    .frame(width: 40, height: 40)
                    .background(Circle().fill(BumpColor.tertiaryContainer))
                VStack(alignment: .leading, spacing: Space.xs) {
                    Text(highlight.statement)
                        .font(BumpFont.titleMedium)
                        .foregroundStyle(BumpColor.onSurface)
                        .fixedSize(horizontal: false, vertical: true)
                    // Evidence: the entry in each profile that supports the
                    // claim. Collapsed when both profiles hold the identical entry.
                    Text(highlight.yourEntry == highlight.theirEntry
                         ? "Both of you list “\(highlight.yourEntry)”"
                         : "You listed “\(highlight.yourEntry)” · they listed “\(highlight.theirEntry)”")
                        .font(BumpFont.bodySmall)
                        .foregroundStyle(BumpColor.onSurfaceVariant)
                        .fixedSize(horizontal: false, vertical: true)
                    if let point {
                        TalkingPromptLine(point: point)
                    }
                }
            }
        }
    }
}

/// The conversation opener, as a big tonal hero card.
struct OpenerCard: View {
    let opener: String
    let source: String

    var body: some View {
        Card(style: .tertiaryTonal, padding: Space.l) {
            VStack(alignment: .leading, spacing: Space.sm) {
                Image(systemName: "quote.opening")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(BumpColor.tertiary)
                Text(opener)
                    .font(BumpFont.headlineSmall)
                    .foregroundStyle(BumpColor.onTertiaryContainer)
                    .fixedSize(horizontal: false, vertical: true)
                // A template is never passed off as an AI result.
                Text(source)
                    .font(BumpFont.labelMedium)
                    .foregroundStyle(BumpColor.onTertiaryContainer.opacity(0.7))
            }
        }
    }
}

#Preview {
    RevealView(result: PreviewFixtures.result, myName: "Jared", onSave: {}, onAgain: {})
}
