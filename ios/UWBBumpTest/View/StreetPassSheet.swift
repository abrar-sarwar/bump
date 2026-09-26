import SwiftUI

/// The StreetPass pass card: shown as soon as a nearby encounter qualifies,
/// while the app is foregrounded. Shaped like the system "AirPods nearby"
/// card — short, bottom-anchored, avatar-led — rather than a full page.
/// Never a full profile: just enough to be curious, and at most one mutual
/// interest. It stays until the person acts (swipe down or "Not now").
struct StreetPassSheet: View {
    let encounter: StreetPassEncounter
    var onBumpThem: () -> Void
    var onNotNow: () -> Void

    @ScaledMetric(relativeTo: .body) private var avatarSize: CGFloat = 104

    var body: some View {
        VStack(spacing: Space.m) {
            // Hero: the person, the way the AirPods card leads with the device.
            Avatar(name: encounter.displayName, size: avatarSize, photo: encounter.avatarThumbnail)
                .padding(.top, Space.s)

            VStack(spacing: Space.xs) {
                Text(encounter.displayName)
                    .font(BumpFont.titleLarge)
                    .foregroundStyle(BumpColor.onSurface)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                Text("just walked by you")
                    .font(BumpFont.body)
                    .foregroundStyle(BumpColor.onSurfaceVariant)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let statement = encounter.mutualInterestStatement {
                StatusPill(text: statement, tone: .good)
            }

            Spacer(minLength: 0)

            VStack(spacing: Space.xs) {
                Button("Bump them", action: onBumpThem)
                    .buttonStyle(.bumpPrimary)
                Button("Not now", action: onNotNow)
                    .buttonStyle(.bumpText)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, Space.gutter)
        .padding(.top, Space.m)
        .padding(.bottom, Space.s)
        .accessibilityElement(children: .contain)
    }
}

#Preview("With mutual interest") {
    StreetPassSheet(
        encounter: .init(id: "demo#0002", displayName: "Priya (demo)", avatarThumbnail: nil,
                         mutualInterestStatement: "You're both into photography."),
        onBumpThem: {}, onNotNow: {}
    )
    .background(BumpColor.surfaceContainerLowest)
}

#Preview("No mutual interest") {
    StreetPassSheet(
        encounter: .init(id: "demo#0003", displayName: "Alexandra Fernández-Whitmore",
                         avatarThumbnail: nil, mutualInterestStatement: nil),
        onBumpThem: {}, onNotNow: {}
    )
    .background(BumpColor.surfaceContainerLowest)
}
