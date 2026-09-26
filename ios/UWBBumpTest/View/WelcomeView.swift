import SwiftUI

/// The site's hero on a phone: the backdrop, the two phones with bubbles
/// floating around them, the wordmark artwork, one action.
struct WelcomeView: View {
    var onStart: () -> Void

    var body: some View {
        ZStack {
            BumpColor.background.ignoresSafeArea()
            Backdrop(style: .hero).ignoresSafeArea()
            VStack(spacing: Space.m) {
                Spacer(minLength: Space.l)

                PhonesIllustration(animated: true)
                    .padding(.vertical, 60)
                    .floaters([
                        Floater(text: FloaterLine.lecture, alignment: .topLeading, offset: CGSize(width: 0, height: 4), rotation: -4),
                        Floater(text: FloaterLine.film, isMe: true, alignment: .bottomTrailing, offset: CGSize(width: 0, height: -8), rotation: 4),
                    ])
                    .padding(.horizontal, Space.gutter)

                Wordmark(size: .hero)
                    .padding(.horizontal, Space.gutter)

                Text("Meet someone. Find your overlap.")
                    .font(BumpFont.sectionTitle)
                    .foregroundStyle(BumpColor.navy)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, Space.xl)

                Text("Tap phones with someone new. BUMP finds the specific things you actually have in common, and gives you something to say.")
                    .font(BumpFont.body)
                    .foregroundStyle(BumpColor.secondaryText)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, Space.l)

                Spacer(minLength: Space.m)

                Button(action: onStart) {
                    TrailingIconLabel("Get started", systemImage: "arrow.right")
                }
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
