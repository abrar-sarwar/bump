import SwiftUI

/// A short walkthrough of how bumping works. Shown the first time someone
/// opens the Bump tab, and any time from "How it works".
struct BumpTutorial: View {
    var onDone: () -> Void

    @State private var page = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private struct Page {
        let title: String
        let body: String
        let art: Art
    }

    private enum Art { case open, tap, confirm, share }

    private let pages: [Page] = [
        Page(title: "Find someone to meet",
             body: "You both open BUMP and tap Start bumping. No codes, no accounts. BUMP finds the phones around you.",
             art: .open),
        Page(title: "Tap your phones together",
             body: "A gentle tap, back to back. That's how BUMP knows who you just met, and nobody else.",
             art: .tap),
        Page(title: "Both say yes",
             body: "You each confirm who you bumped. Nothing is shared until you both do.",
             art: .confirm),
        Page(title: "See what you share",
             body: "Your cards swap, and BUMP shows what you have in common plus a few things to talk about.",
             art: .share),
    ]

    var body: some View {
        ZStack {
            BumpColor.background.ignoresSafeArea()
            VStack(spacing: 0) {
                HStack {
                    Spacer()
                    Button("Skip", action: onDone)
                        .font(BumpFont.bodyEmphasis)
                        .foregroundStyle(BumpColor.secondaryText)
                        .opacity(page == pages.count - 1 ? 0 : 1)
                }
                .padding(.horizontal, Space.gutter)
                .padding(.top, Space.m)

                TabView(selection: $page) {
                    ForEach(Array(pages.enumerated()), id: \.offset) { index, item in
                        VStack(spacing: Space.l) {
                            Spacer(minLength: Space.m)
                            art(item.art, active: page == index)
                                .frame(height: 220)
                            VStack(spacing: Space.s) {
                                Text(item.title)
                                    .font(BumpFont.screenTitle)
                                    .foregroundStyle(BumpColor.navy)
                                    .multilineTextAlignment(.center)
                                    .fixedSize(horizontal: false, vertical: true)
                                Text(item.body)
                                    .font(BumpFont.body)
                                    .foregroundStyle(BumpColor.secondaryText)
                                    .multilineTextAlignment(.center)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .padding(.horizontal, Space.xl)
                            Spacer()
                        }
                        .tag(index)
                        .accessibilityElement(children: .combine)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))

                StepIndicator(current: page, total: pages.count)
                    .padding(.bottom, Space.l)

                Button(page == pages.count - 1 ? "Let's bump" : "Next") {
                    if page == pages.count - 1 { onDone() }
                    else { withAnimation(.easeInOut(duration: 0.25)) { page += 1 } }
                }
                .buttonStyle(.bumpPrimary)
                .padding(.horizontal, Space.gutter)
                .padding(.bottom, Space.l)
            }
        }
    }

    // MARK: Art

    @ViewBuilder
    private func art(_ art: Art, active: Bool) -> some View {
        switch art {
        case .open:
            ZStack {
                PulseRings(active: active && !reduceMotion)
                PhonesIllustration(animated: false)
            }
        case .tap:
            PhonesIllustration(animated: active)
        case .confirm:
            HStack(spacing: Space.xl) {
                ConfirmBadge(tint: BumpColor.brand)
                ConfirmBadge(tint: BumpColor.illustrationWarm)
            }
        case .share:
            VStack(spacing: Space.s) {
                HStack(spacing: -12) {
                    Avatar(name: "You", size: 64)
                    Avatar(name: "Them", size: 64, tint: BumpColor.illustrationWarm)
                }
                FlowLayout {
                    InterestChip(title: "Climbing", selected: true)
                    InterestChip(title: "Cold brew", selected: true)
                    InterestChip(title: "Collecting")
                }
                .frame(width: 260)
            }
        }
    }
}

/// Soft rings radiating out, for "looking for phones nearby".
struct PulseRings: View {
    var active: Bool
    @State private var expand = false

    var body: some View {
        ZStack {
            ForEach(0..<3) { i in
                Circle()
                    .stroke(BumpColor.brand.opacity(0.35), lineWidth: 2)
                    .scaleEffect(expand ? 1.6 : 0.6)
                    .opacity(expand ? 0 : 1)
                    .animation(active
                               ? .easeOut(duration: 2.4).repeatForever(autoreverses: false).delay(Double(i) * 0.8)
                               : nil,
                               value: expand)
            }
        }
        .frame(width: 200, height: 200)
        .onAppear { if active { expand = true } }
        .onChange(of: active) { _, on in expand = on }
        .accessibilityHidden(true)
    }
}

private struct ConfirmBadge: View {
    let tint: Color
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(tint)
                .frame(width: 78, height: 140)
            Circle().fill(.white).frame(width: 48, height: 48)
            Image(systemName: "checkmark")
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(BumpColor.positive)
        }
        .accessibilityHidden(true)
    }
}

#Preview {
    BumpTutorial(onDone: {})
}
