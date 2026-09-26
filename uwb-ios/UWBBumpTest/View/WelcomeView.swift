import SwiftUI

struct WelcomeView: View {
    var onStart: () -> Void

    var body: some View {
        ZStack {
            BumpColor.background.ignoresSafeArea()
            VStack(spacing: Space.l) {
                Spacer(minLength: Space.l)

                Wordmark(size: .hero)
                    .padding(.horizontal, Space.gutter)

                Text("Meet someone. Find your overlap.")
                    .font(BumpFont.screenTitle)
                    .foregroundStyle(BumpColor.navy)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, Space.xl)

                PhonesIllustration(animated: true)
                    .padding(.vertical, Space.s)

                Text("Tap phones with someone new. BUMP finds the specific things you actually have in common — and gives you something to say.")
                    .font(BumpFont.body)
                    .foregroundStyle(BumpColor.secondaryText)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, Space.xl)

                Spacer(minLength: Space.m)

                Button("Get started", action: onStart)
                    .buttonStyle(.bumpPrimary)
                    .padding(.horizontal, Space.gutter)
                    .padding(.bottom, Space.l)
            }
        }
    }
}

#Preview {
    WelcomeView(onStart: {})
}
