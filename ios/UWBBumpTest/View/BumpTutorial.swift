import SwiftUI

/// A short walkthrough of how bumping works. Shown the first time someone
/// opens the Bump tab, and any time from "How it works".
struct BumpTutorial: View {
    var interests: [Interest] = []
    var onDone: () -> Void

    private var badgePicks: [Interest] {
        var seen = Set<String>()
        return interests.filter { !$0.label.trimmed().isEmpty && seen.insert($0.label.lowercased()).inserted }
    }

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
             body: "Bump their phone.",
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
            Backdrop(style: .soft).ignoresSafeArea()
            VStack(spacing: 0) {
                HStack {
                    Eyebrow("How it works")
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
                        pageView(item, active: page == index)
                            .tag(index)
                            .accessibilityElement(children: .combine)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))

                StepIndicator(current: page, total: pages.count)
                    .padding(.bottom, Space.l)

                Button {
                    if page == pages.count - 1 { onDone() }
                    else { withAnimation(.easeInOut(duration: 0.25)) { page += 1 } }
                } label: {
                    TrailingIconLabel(page == pages.count - 1 ? "Let's bump" : "Next", systemImage: "arrow.right")
                }
                .buttonStyle(.bumpPrimary)
                .padding(.horizontal, Space.gutter)
                .padding(.bottom, Space.l)
            }
        }
    }

    @ViewBuilder
    private func pageView(_ item: Page, active: Bool) -> some View {
        if item.art == .share {
            // The badge alone, centred in the free space; the words sit low,
            // just above the page dots.
            VStack(spacing: 0) {
                Spacer(minLength: Space.m)
                art(item.art, active: active)
                Spacer(minLength: Space.m)
                titleBlock(item)
                    .padding(.bottom, Space.xl)
            }
        } else {
            VStack(spacing: Space.l) {
                Spacer(minLength: Space.m)
                art(item.art, active: active)
                    .frame(height: 260)
                titleBlock(item)
                Spacer()
            }
        }
    }

    private func titleBlock(_ item: Page) -> some View {
        VStack(spacing: Space.s) {
            ScreenTitle(item.title, alignment: .center)
            Text(item.body)
                .font(BumpFont.body)
                .foregroundStyle(BumpColor.secondaryText)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, Space.xl)
    }

    // MARK: Art

    @ViewBuilder
    private func art(_ art: Art, active: Bool) -> some View {
        switch art {
        case .open:
            ZStack {
                PulseRings(active: active && !reduceMotion)
                HStack(spacing: Space.l) {
                    Avatar(name: "You", size: 72)
                    Avatar(name: "Them", size: 72, tint: BumpColor.illustrationWarm)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, Space.gutter)
        case .tap:
            PhonesIllustration(animated: active)
                .padding(.vertical, 40)
                .padding(.horizontal, Space.gutter)
        case .confirm:
            // The site's hero floater "did you bump with dev?", as the moment.
            Card {
                VStack(alignment: .leading, spacing: Space.m) {
                    HStack(spacing: Space.m) {
                        Avatar(name: "Them", size: 48, tint: BumpColor.illustrationWarm)
                        Text("Did you bump with them?")
                            .font(BumpFont.bodyEmphasis)
                            .foregroundStyle(BumpColor.navy)
                    }
                    HStack(spacing: Space.s) {
                        Text("Not them")
                            .font(BumpFont.captionEmphasis)
                            .foregroundStyle(BumpColor.navy)
                            .frame(maxWidth: .infinity, minHeight: 40)
                            .frostedCapsule()
                        Label("Confirm", systemImage: "checkmark")
                            .font(BumpFont.captionEmphasis)
                            .foregroundStyle(BumpColor.onPrimaryContainer)
                            .frame(maxWidth: .infinity, minHeight: 40)
                            .background(Capsule().fill(BumpColor.primaryContainer))
                    }
                }
            }
            .frame(width: 290)
            .rotationEffect(.degrees(-2))
            .accessibilityHidden(true)
        case .share:
            // Pops in and cycles what two people might have in common.
            SharedBadge(kicker: "You both share this",
                        interests: badgePicks.isEmpty ? ["Something unexpected"] : badgePicks.map(\.label),
                        themeHints: badgePicks.map { InterestCatalog.themeHint(for: $0) },
                        size: 300,
                        popIn: active)
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
                    .stroke(BumpColor.primary.opacity(0.28), lineWidth: 1.5)
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

#Preview {
    BumpTutorial(interests: [
        Interest(id: "photography", label: "35mm photography", parent: "design"),
        Interest(id: "climbing", label: "Climbing", parent: "movement"),
        Interest(id: "cold-brew", label: "Cold brew", parent: "coffee"),
    ], onDone: {})
}
