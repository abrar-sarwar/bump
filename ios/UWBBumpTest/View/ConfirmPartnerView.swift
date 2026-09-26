import SwiftUI

/// Mutual confirmation. Nothing is exchanged until BOTH sides tap confirm.
struct ConfirmPartnerView: View {
    let proposal: BumpEngine.Proposal
    var onConfirm: () -> Void
    var onDecline: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown = false

    var body: some View {
        VStack(spacing: Space.l) {
            ZStack {
                Circle()
                    .fill(BumpColor.primaryContainer)
                    .frame(width: 148, height: 148)
                Avatar(name: proposal.partner.displayName, size: 112)
                    .overlay(Circle().strokeBorder(BumpColor.surfaceContainerLowest, lineWidth: 4))
            }
            .scaleEffect(shown ? 1 : 0.8)
            .opacity(shown ? 1 : 0)
            .padding(.top, Space.m)

            VStack(spacing: Space.s) {
                Text("Did you bump with")
                    .font(BumpFont.bodyLarge)
                    .foregroundStyle(BumpColor.onSurfaceVariant)
                Text(proposal.partner.displayName)
                    .font(BumpFont.displaySmall)
                    .foregroundStyle(BumpColor.onSurface)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if proposal.manual {
                StatusPill(text: "You picked them manually", tone: .warn, icon: "hand.point.up.left.fill")
            } else if proposal.uwbCorroborated {
                StatusPill(text: "Your phones were touching", tone: .good, icon: "checkmark.seal.fill")
            }

            VStack(spacing: Space.sm) {
                Button("Confirm & share interests", action: onConfirm)
                    .buttonStyle(.bumpPrimary)
                Button("Not this person", action: onDecline)
                    .buttonStyle(.bumpSecondary)
            }

            Label("Your interests are only shared after you both confirm.", systemImage: "lock.fill")
                .font(BumpFont.bodySmall)
                .foregroundStyle(BumpColor.onSurfaceVariant)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .onAppear {
            if reduceMotion { shown = true } else { withAnimation(Motion.expressive) { shown = true } }
        }
        .accessibilityElement(children: .contain)
    }
}

#Preview {
    ZStack {
        BumpColor.surface.ignoresSafeArea()
        ConfirmPartnerView(
            proposal: .init(id: "p1",
                            partner: .init(id: "x", displayName: "Priya"),
                            uwbCorroborated: true, manual: false),
            onConfirm: {}, onDecline: {}
        )
        .padding(Space.gutter)
    }
}
