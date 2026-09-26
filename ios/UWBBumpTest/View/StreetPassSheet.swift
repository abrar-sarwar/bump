import SwiftUI

/// The StreetPass teaser: shown as soon as a nearby encounter qualifies,
/// while the app is foregrounded. Never a full profile — just enough to be
/// curious, and at most one mutual interest.
struct StreetPassSheet: View {
    let encounter: StreetPassEncounter
    var onBumpThem: () -> Void
    var onNotNow: () -> Void

    var body: some View {
        VStack(spacing: Space.l) {
            Avatar(name: encounter.displayName, size: 96, photo: encounter.avatarThumbnail)
                .padding(.top, Space.m)

            VStack(spacing: Space.s) {
                Text("hey, this person just walked by you.")
                    .font(BumpFont.body)
                    .foregroundStyle(BumpColor.secondaryText)
                    .multilineTextAlignment(.center)
                Text("Bump them?")
                    .font(BumpFont.screenTitle)
                    .foregroundStyle(BumpColor.navy)
            }

            if let statement = encounter.mutualInterestStatement {
                StatusPill(text: statement, tone: .good)
            }

            VStack(spacing: Space.s) {
                Button("Bump them", action: onBumpThem)
                    .buttonStyle(.bumpPrimary)
                Button("Not now", action: onNotNow)
                    .buttonStyle(.bumpSecondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(Space.gutter)
        .accessibilityElement(children: .contain)
    }
}

#Preview {
    ZStack {
        BumpColor.background.ignoresSafeArea()
        StreetPassSheet(
            encounter: .init(id: "demo#0002", displayName: "Priya (demo)", avatarThumbnail: nil,
                             mutualInterestStatement: "You're both into photography."),
            onBumpThem: {}, onNotNow: {}
        )
    }
}
