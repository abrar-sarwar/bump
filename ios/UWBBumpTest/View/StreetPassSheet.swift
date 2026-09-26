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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Drives the radar loop; never set under Reduce Motion.
    @State private var animating = false

    var body: some View {
        VStack(spacing: Space.m) {
            // Hero: the person, the way the AirPods card leads with the device.
            // The radar sits in a fixed-size frame behind the avatar, so the
            // rings never change the card's height as they expand.
            Avatar(name: encounter.displayName, size: avatarSize, photo: encounter.avatarThumbnail)
                .background {
                    PassRadar(diameter: avatarSize, animating: animating && !reduceMotion)
                }
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
        .onAppear { if !reduceMotion { animating = true } }
    }
}

/// StreetPass-style radar: rings that expand out from behind the avatar and
/// fade. Decorative only, and static under Reduce Motion — the caller passes
/// `animating: false` in that case, so nothing ever starts.
private struct PassRadar: View {
    let diameter: CGFloat
    let animating: Bool

    private static let ringCount = 3
    private static let period: TimeInterval = 2.4

    var body: some View {
        ZStack {
            ForEach(0..<Self.ringCount, id: \.self) { index in
                Circle()
                    .strokeBorder(BumpColor.brand, lineWidth: 1.5)
                    .frame(width: diameter, height: diameter)
                    .scaleEffect(animating ? 1.9 : 1)
                    .opacity(animating ? 0 : 0.35)
                    .animation(animating
                               ? .easeOut(duration: Self.period)
                                   .repeatForever(autoreverses: false)
                                   .delay(Self.period / Double(Self.ringCount) * Double(index))
                               : nil,
                               value: animating)
            }
        }
        // Room for the largest ring, so the layout never moves with the motion.
        .frame(width: diameter * 1.9, height: diameter * 1.9)
        .accessibilityHidden(true)
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
