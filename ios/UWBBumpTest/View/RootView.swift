import SwiftUI

struct RootView: View {
    @StateObject private var store: Store
    @StateObject private var engine: BumpEngine
    @Environment(\.scenePhase) private var scenePhase

    @State private var stage: Stage
    @State private var tab: BumpTabBar.Tab = .bump
    /// DEBUG demo only: a pre-seeded onboarding model with sample data.
    @State private var demoOnboarding: OnboardingModel?

    enum Stage { case welcome, onboarding, main }

    init() {
        let store = Store()
        _store = StateObject(wrappedValue: store)
        _engine = StateObject(wrappedValue: BumpEngine(store: store))
        _stage = State(initialValue: store.profile.isComplete ? .main : .welcome)
    }

    var body: some View {
        VStack(spacing: 0) {
            if DemoMode.active != nil { DemoBadge() }
            content
        }
        .task { applyDemoIfRequested() }
    }

    @ViewBuilder
    private var content: some View {
        Group {
            switch stage {
            case .welcome:
                WelcomeView { stage = .onboarding }
                    .transition(.opacity)

            case .onboarding:
                OnboardingFlow(store: store, model: demoOnboarding) {
                    guard store.profile.isComplete else { return }
                    stage = .main
                }
                .transition(.opacity)

            case .main:
                // All three destinations stay alive (like a TabView) so their
                // navigation state survives switching; the M3 navigation bar
                // below swaps which one is visible with a fade-through.
                ZStack {
                    tabContent(.bump) { BumpScreen(engine: engine, store: store) }
                    tabContent(.connections) { ConnectionsScreen(store: store) }
                    tabContent(.you) { YouScreen(store: store, engine: engine) }
                }
                .safeAreaInset(edge: .bottom, spacing: 0) { BumpTabBar(selection: $tab) }
                .tint(BumpColor.primary)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: stage)
        .onChange(of: scenePhase) { _, phase in engine.handleScenePhase(phase) }
        .onChange(of: store.settings) { _, _ in engine.applySettings() }
        .onChange(of: store.onboardingResets) { _, _ in
            demoOnboarding = nil
            stage = .welcome
        }
        .preferredColorScheme(.light)   // the brand is a warm light palette
    }

    @ViewBuilder
    private func tabContent<V: View>(_ which: BumpTabBar.Tab, @ViewBuilder _ view: () -> V) -> some View {
        let shown = tab == which
        view()
            .opacity(shown ? 1 : 0)
            .scaleEffect(shown ? 1 : 0.985)
            .allowsHitTesting(shown)
            .accessibilityHidden(!shown)
            .animation(Motion.effects, value: tab)
    }

    /// DEBUG-only seeding so every screen can be inspected in the Simulator.
    private func applyDemoIfRequested() {
        #if DEBUG
        guard let demo = DemoMode.active else { return }
        let sample = Wire.Member(id: "demo#0001", displayName: "Sample Partner (demo)", supportsUWB: true)
        switch demo {
        case .onboarding:
            store.profile = Profile(); stage = .onboarding
        case .onboardingIntro, .onboardingQuestion, .onboardingCard:
            store.profile = Profile()
            let step: OnboardingModel.Step = demo == .onboardingIntro ? .intro
                : demo == .onboardingQuestion ? .questions : .card
            demoOnboarding = PreviewFixtures.onboarding(step)
            stage = .onboarding
        case .ready:
            store.profile = PreviewFixtures.profile; stage = .main
            engine.demoSet(.ready, members: [sample])
        case .confirm:
            store.profile = PreviewFixtures.profile; stage = .main
            engine.demoSet(.confirming(.init(id: "demo", partner: sample,
                                             uwbCorroborated: true, manual: false)),
                           members: [sample])
        case .reveal:
            store.profile = PreviewFixtures.profile; stage = .main
            engine.demoSet(.connected(PreviewFixtures.result), members: [sample])
        case .timedOut:
            store.profile = PreviewFixtures.profile; stage = .main
            engine.demoSet(.timedOut, members: [sample])
        case .ambiguous:
            store.profile = PreviewFixtures.profile; stage = .main
            engine.demoSet(.ambiguous(3), members: [sample])
        case .unsupported:
            store.profile = PreviewFixtures.profile; stage = .main
            engine.demoSet(.unavailable("This iPhone isn't reporting motion data, so BUMP can't feel a bump. You can still connect by picking someone from the room."),
                           members: [sample])
        case .connections, .you, .tools, .home, .tutorial:
            store.profile = PreviewFixtures.profile
            if demo == .connections { PreviewFixtures.seed(store); tab = .connections }
            if demo == .you || demo == .tools { tab = .you }
            stage = .main
        }
        #endif
    }
}
