import SwiftUI

/// Mutual confirmation. Nothing is exchanged until BOTH sides tap confirm.
struct ConfirmPartnerView: View {
    let proposal: BumpEngine.Proposal
    var onConfirm: () -> Void
    var onDecline: () -> Void

    var body: some View {
        VStack(spacing: Space.l) {
            Avatar(name: proposal.partner.displayName, size: 96)
                .padding(.top, Space.m)

            VStack(spacing: Space.s) {
                Text("Did you bump with")
                    .font(BumpFont.body)
                    .foregroundStyle(BumpColor.secondaryText)
                Text(proposal.partner.displayName)
                    .font(BumpFont.screenTitle)
                    .foregroundStyle(BumpColor.navy)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if proposal.manual {
                StatusPill(text: "You picked them manually", tone: .warn)
            } else if proposal.uwbCorroborated {
                StatusPill(text: "Your phones were touching", tone: .good)
            }

            VStack(spacing: Space.s) {
                Button("Confirm & share interests", action: onConfirm)
                    .buttonStyle(.bumpPrimary)
                Button("Not this person", action: onDecline)
                    .buttonStyle(.bumpSecondary)
            }

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
