import SwiftUI

/// Mutual confirmation. Nothing is exchanged until BOTH sides tap confirm.
/// Styled as the site's hero moment "did you bump with dev?", full size.
struct ConfirmPartnerView: View {
    let proposal: BumpEngine.Proposal
    var onConfirm: () -> Void
    var onDecline: () -> Void

    var body: some View {
        VStack(spacing: Space.l) {
            Card(padding: 22) {
                VStack(spacing: Space.l) {
                    Avatar(name: proposal.partner.displayName, size: 104, tint: BumpColor.illustrationWarm)
                        .padding(.top, Space.s)

                    VStack(spacing: Space.s) {
                        Eyebrow("Did you bump with")
                        ScreenTitle(proposal.partner.displayName, alignment: .center)
                    }

                    StatusPill(
                        text: proposal.manual ? "Matched thru manual pick" :
                            (proposal.uwbCorroborated ? "Matched thru BUMP" : "Matched thru motion"),
                        tone: proposal.manual ? .warn : .good
                    )

                    VStack(spacing: Space.s) {
                        Button(action: onConfirm) {
                            TrailingIconLabel("Confirm & share interests", systemImage: "checkmark")
                        }
                        .buttonStyle(.bumpPrimary)
                        Button("Not this person", action: onDecline)
                            .buttonStyle(.bumpSecondary)
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .padding(.top, Space.m)

            Text("Your interests are only shared after you both confirm.")
                .font(BumpFont.caption)
                .foregroundStyle(BumpColor.secondaryText)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .contain)
    }
}

#Preview {
    ZStack {
        BumpColor.background.ignoresSafeArea()
        ConfirmPartnerView(
            proposal: .init(id: "p1",
                            partner: .init(id: "x", displayName: "Priya"),
                            uwbCorroborated: true, manual: false),
            onConfirm: {}, onDecline: {}
        )
        .padding(Space.gutter)
    }
}
