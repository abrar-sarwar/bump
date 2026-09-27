import SwiftUI

/// The payoff screen, in the site's "overlap" language: the shared badge
/// cycling through what you both listed, the evidence as pill rows, and the
/// opener as a suggestion card. No artificial delay; the reveal animates as
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
    private var suggestedQuestions: [String] {
        ([result.insight.opener] + result.insight.talkingPoints.map(\.prompt))
            .filter { !$0.isEmpty }
            .reduce(into: [String]()) { questions, prompt in
                if !questions.contains(prompt) && questions.count < 3 { questions.append(prompt) }
            }
    }

    var body: some View {
        Screen(backdrop: .hero) {
            VStack(alignment: .leading, spacing: Space.l) {

                VStack(spacing: Space.s) {
                    HStack(spacing: Space.m) {
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
                    SharedBadge(kicker: "You're both into",
                                interests: result.insight.highlights.map(\.sharedLabel),
                                themeHints: result.insight.highlights.map {
                                    InterestCatalog.themeHint(forHighlight: $0.interestID, entry: $0.theirEntry,
                                                              in: result.partner.interests)
                                },
                                size: 320, popIn: true)
                        .frame(maxWidth: .infinity)

                    VStack(alignment: .leading, spacing: Space.s) {
                        Eyebrow("Try asking")
                            .padding(.horizontal, Space.xs)
                        Card(padding: 14) {
                            VStack(alignment: .leading, spacing: 0) {
                                ForEach(Array(suggestedQuestions.enumerated()), id: \.offset) { index, prompt in
                                    if index > 0 { Divider() }
                                    HStack(alignment: .top, spacing: Space.s) {
                                        Text(String(format: "%02d", index + 1))
                                            .font(BumpFont.caption2)
                                            .foregroundStyle(BumpColor.primary)
                                        Text(prompt)
                                            .font(BumpFont.captionEmphasis)
                                            .foregroundStyle(BumpColor.navy)
                                            .fixedSize(horizontal: false, vertical: true)
                                    }
                                    .padding(.vertical, Space.s)
                                }
                            }
                        }
                    }
                } else {
                    Card(padding: 22) {
                        Text("Your lists don't overlap yet, which is its own kind of interesting.")
                            .font(BumpFont.body)
                            .foregroundStyle(BumpColor.navy)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                if !hasOverlap && !result.insight.unattachedPoints.isEmpty {
                    TalkingPointsSection(points: result.insight.unattachedPoints)
                }

                if !hasOverlap { VStack(alignment: .leading, spacing: Space.s) {
                    Eyebrow("Something to talk about")
                        .padding(.horizontal, Space.xs)
                    Card {
                        VStack(alignment: .leading, spacing: Space.xs) {
                            Text(result.insight.opener)
                                .font(BumpFont.archivo(Archivo.semibold, 19, relativeTo: .title3))
                            Text(result.insight.openerSource.label)
                                .font(BumpFont.caption2)
                                .foregroundStyle(BumpColor.faint)
                        }
                    }
                }
                .opacity(revealed ? 1 : 0)
                .animation(reduceMotion ? nil : BumpMotion.emphasizedIn.delay(0.3), value: revealed)
                }

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
