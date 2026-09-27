import SwiftUI

struct RootView: View {
    @StateObject private var store: Store
    @StateObject private var engine: BumpEngine
    @StateObject private var streetPassEngine: StreetPassEngine
    @Environment(\.scenePhase) private var scenePhase

    @State private var stage: Stage
    @State private var tab: BumpTabBar.Tab = .bump
    /// DEBUG demo only: a pre-seeded onboarding model with sample data.
    @State private var demoOnboarding: OnboardingModel?
    /// Height of the StreetPass pass card's single detent. @ScaledMetric so the
    /// card grows with Dynamic Type instead of clipping its buttons.
    @ScaledMetric(relativeTo: .body) private var passCardHeight: CGFloat = 470
    /// Decides which saved connection is worth asking about, and when.
    @State private var prompter = RatingPrompter()
    /// The connection whose rating card is up, however it was raised — by the
    /// automatic prompt, from the Connections list, from a connection's detail
    /// screen or from the Insights screen.
    ///
    /// Deliberately the app's ONLY copy of this state. When each screen kept its
    /// own, `promptForRatingIfDue` could not see a card raised on the Connections
    /// tab, so returning to the foreground would set this while a sheet was
    /// already up: SwiftUI drops the second sheet, and the value then stays
    /// non-nil with nothing on screen, blocking every later prompt that launch.
    @State private var connectionToRate: SavedConnection?

    enum Stage { case welcome, onboarding, main }

    init() {
        let store = Store()
        _store = StateObject(wrappedValue: store)
        _engine = StateObject(wrappedValue: BumpEngine(store: store))
        _streetPassEngine = StateObject(wrappedValue: StreetPassEngine(store: store))
        _stage = State(initialValue: store.profile.isComplete ? .main : .welcome)
    }

    var body: some View {
        VStack(spacing: 0) {
            if DemoMode.active != nil { DemoBadge() }
            content
        }
        .task {
            applyDemoIfRequested()
            // A returning user starts at .main (see init), so .onChange(of:
            // stage) never fires for them — this is the reliable start path.
            // start() is idempotent, so overlapping with the stage/scenePhase
            // paths is harmless. Skipped under a DEBUG demo so fixture screens
            // never bring up real transport/ranging.
            if DemoMode.active == nil, stage == .main {
                streetPassEngine.start()
                // A cold launch after a bump should ask too, not wait for the
                // next background/foreground round trip.
                promptForRatingIfDue()
            }
        }
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
                // The pass card: a short, bottom-anchored card in the spirit of
                // the system "AirPods nearby" card, not a full page. A single
                // fixed detent keeps it compact; it scales with Dynamic Type.
                .sheet(item: streetPassSheetBinding) { encounter in
                    StreetPassSheet(
                        encounter: encounter,
                        onBumpThem: {
                            streetPassEngine.dismissPendingEncounter()
                            engine.startNearby()
                        },
                        onNotNow: { streetPassEngine.dismissPendingEncounter() }
                    )
                    .presentationDetents([.height(passCardHeight)])
                    .presentationCornerRadius(Radius.extraLargeIncreased)
                    .presentationBackground(BumpColor.surfaceContainerLowest)
                    .presentationDragIndicator(.visible)
                }
                // The rating card. Same treatment as StreetPass, but
                // retrospective: it asks about a bump that already happened.
                // Presented here rather than per-screen so there is one card and
                // one piece of state for every way of reaching it.
                .rateInteraction(item: $connectionToRate,
                                 store: store,
                                 onSkip: { prompter.dismiss($0) })
            }
        }
        .animation(.easeInOut(duration: 0.25), value: stage)
        .onChange(of: scenePhase) { _, phase in
            engine.handleScenePhase(phase)
            // Becoming active also starts StreetPass, which is the third way a
            // DEBUG demo could otherwise bring up real transport and ranging.
            if DemoMode.active == nil { streetPassEngine.handleScenePhase(phase) }
            // Coming back to the app is the signal that the interaction is over:
            // they saved the connection, put the phone away, talked, and returned.
            if phase == .active { promptForRatingIfDue() }
        }
        .onChange(of: stage) { _, newStage in
            // Skipped under a DEBUG demo for the same reason as the .task path:
            // a fixture screen must never bring up real transport or ranging.
            if newStage == .main, DemoMode.active == nil { streetPassEngine.start() }
        }
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
        case .streetpass:
            store.profile = PreviewFixtures.profile; stage = .main
            streetPassEngine.demoSet(.init(id: "demo#0002", displayName: "Priya (demo)",
                                           avatarThumbnail: nil,
                                           mutualInterestStatement: "You're both into photography.",
                                           teasedMutualStatements: ["You're both into bouldering.",
                                                                    "You both like espresso."]))
        case .rate, .insights:
            // Seed rated demo history so both new screens have something to show,
            // then open the card (.rate) or leave the tab for .insights, which is
            // one tap away behind "What lands".
            store.profile = PreviewFixtures.profile
            PreviewFixtures.seedRatings(store)
            tab = .connections
            stage = .main
            if demo == .rate { connectionToRate = store.unratedConnections.first }

        case .connections, .you, .tools, .home, .tutorial, .notifications:
            store.profile = PreviewFixtures.profile
            if demo == .connections { PreviewFixtures.seed(store); tab = .connections }
            if demo == .notifications { PreviewFixtures.seed(store); tab = .bump }
            if demo == .you || demo == .tools { tab = .you }
            stage = .main
        }
        #endif
    }

    /// Asks about the oldest unrated connection still inside the recall window.
    ///
    /// Skipped while a StreetPass card is up — SwiftUI cannot present two sheets
    /// from one view, and someone standing in front of you beats a question about
    /// someone who already left. Also skipped under a DEBUG demo, and while a
    /// prompt is already showing.
    private func promptForRatingIfDue() {
        guard DemoMode.active == nil,
              stage == .main,
              connectionToRate == nil,
              streetPassEngine.pendingEncounter == nil else { return }
        connectionToRate = prompter.next(connections: store.connections,
                                         ratings: store.ratings)
    }

    private var streetPassSheetBinding: Binding<StreetPassEncounter?> {
        Binding(
            get: { streetPassEngine.pendingEncounter },
            set: { if $0 == nil { streetPassEngine.dismissPendingEncounter() } }
        )
    }
}
