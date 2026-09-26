import SwiftUI

struct WelcomeView: View {
    var onStart: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown = false

    var body: some View {
        ZStack {
            BumpColor.surface.ignoresSafeArea()

            // A soft tonal blob behind the hero, M3 Expressive style.
            LobedShape(lobes: 5, amplitude: 0.12)
                .fill(BumpColor.primaryContainer.opacity(0.55))
                .frame(width: 420, height: 420)
                .offset(x: 120, y: -260)
                .rotationEffect(.degrees(shown ? 18 : 0))
                .ignoresSafeArea()
                .accessibilityHidden(true)

            VStack(spacing: Space.l) {
                Spacer(minLength: Space.l)

                Wordmark(size: .hero)
                    .padding(.horizontal, Space.gutter)
                    .opacity(shown ? 1 : 0)
                    .offset(y: shown ? 0 : 12)

                Text("Meet someone.\nFind your overlap.")
                    .font(BumpFont.displaySmall)
                    .foregroundStyle(BumpColor.onSurface)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, Space.xl)
                    .opacity(shown ? 1 : 0)
                    .offset(y: shown ? 0 : 12)

                PhonesIllustration(animated: true)
                    .padding(.vertical, Space.s)
                    .scaleEffect(shown ? 1 : 0.9)
                    .opacity(shown ? 1 : 0)

                Text("Tap phones with someone new. BUMP finds the specific things you actually have in common, and gives you something to say.")
                    .font(BumpFont.bodyLarge)
                    .foregroundStyle(BumpColor.onSurfaceVariant)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, Space.xl)
                    .opacity(shown ? 1 : 0)

                Spacer(minLength: Space.m)

                VStack(spacing: Space.sm) {
                    Button("Get started", action: onStart)
                        .buttonStyle(.bumpPrimary)
                    Text("No account. Nothing leaves your phone without asking.")
                        .font(BumpFont.bodySmall)
                        .foregroundStyle(BumpColor.onSurfaceVariant)
                }
                .padding(.horizontal, Space.gutter)
                .padding(.bottom, Space.l)
                .opacity(shown ? 1 : 0)
            }
        }
        .onAppear {
            if reduceMotion { shown = true } else { withAnimation(Motion.spatialSlow.delay(0.05)) { shown = true } }
        }
    }
}

#Preview {
    WelcomeView(onStart: {})
}
