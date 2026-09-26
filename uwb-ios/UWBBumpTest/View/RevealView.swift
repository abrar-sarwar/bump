import SwiftUI

/// The payoff screen. No artificial delay — the reveal animates as soon as the
/// result exists.
struct RevealView: View {
    let result: BumpEngine.Result
    let myName: String
    var onSave: () -> Void
    var onAgain: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var revealed = false

    private var hasOverlap: Bool { !result.insight.highlights.isEmpty }

    var body: some View {
        Screen {
            VStack(alignment: .leading, spacing: Space.l) {

                HStack(spacing: Space.m) {
                    Avatar(name: myName, size: 52)
                    Avatar(name: result.partner.displayName, size: 52, tint: BumpColor.illustrationWarm)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(myName.isEmpty ? "You" : myName) + \(result.partner.displayName)")
                            .font(BumpFont.bodyEmphasis)
                            .foregroundStyle(BumpColor.navy)
                        Text(result.evidence.label)
                            .font(BumpFont.caption)
                            .foregroundStyle(BumpColor.secondaryText)
                    }
                }
                .padding(.top, Space.l)

                Text(hasOverlap ? "You have more in common than you think." : "Nice to meet you.")
                    .font(BumpFont.screenTitle)
                    .foregroundStyle(BumpColor.navy)
                    .fixedSize(horizontal: false, vertical: true)

                if hasOverlap {
                    VStack(alignment: .leading, spacing: Space.s) {
                        Text("Specific things you share")
                            .font(BumpFont.caption)
                            .foregroundStyle(BumpColor.secondaryText)

                        ForEach(Array(result.insight.highlights.enumerated()), id: \.element.id) { index, highlight in
                            Card {
                                VStack(alignment: .leading, spacing: Space.xs) {
                                    Text(highlight.statement)
                                        .font(BumpFont.bodyEmphasis)
                                        .foregroundStyle(BumpColor.navy)
                                        .fixedSize(horizontal: false, vertical: true)
                                    // Evidence: the entry in each profile that
                                    // supports the claim. Collapsed when both
                                    // profiles hold the identical entry.
                                    Text(highlight.yourEntry == highlight.theirEntry
                                         ? "Both of you list “\(highlight.yourEntry)”"
                                         : "You listed “\(highlight.yourEntry)” · they listed “\(highlight.theirEntry)”")
                                        .font(BumpFont.caption)
                                        .foregroundStyle(BumpColor.secondaryText)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                            .opacity(revealed ? 1 : 0)
                            .offset(y: revealed ? 0 : 12)
                            .animation(reduceMotion ? nil
                                       : .easeOut(duration: 0.35).delay(Double(index) * 0.09),
                                       value: revealed)
                        }

                        Text("Ranked by how specific they are — not by how rare they are. We don't have data on how common an interest is, so we don't claim to.")
                            .font(BumpFont.caption)
                            .foregroundStyle(BumpColor.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                } else {
                    Card {
                        Text("Your lists don't overlap yet — which is its own kind of interesting.")
                            .font(BumpFont.body)
                            .foregroundStyle(BumpColor.navy)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                VStack(alignment: .leading, spacing: Space.s) {
                    Text("Something to talk about")
                        .font(BumpFont.caption)
                        .foregroundStyle(BumpColor.secondaryText)
                    Card {
                        VStack(alignment: .leading, spacing: Space.s) {
                            Text(result.insight.opener)
                                .font(BumpFont.sectionTitle)
                                .foregroundStyle(BumpColor.navy)
                                .fixedSize(horizontal: false, vertical: true)
                            // A template is never passed off as an AI result.
                            Text(result.insight.openerSource.label)
                                .font(BumpFont.caption)
                                .foregroundStyle(BumpColor.secondaryText)
                        }
                    }
                    .opacity(revealed ? 1 : 0)
                    .animation(reduceMotion ? nil : .easeOut(duration: 0.4).delay(0.3), value: revealed)
                }

                VStack(spacing: Space.s) {
                    Button("Save connection", action: onSave)
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
