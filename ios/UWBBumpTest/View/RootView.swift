import SwiftUI

struct RootView: View {
    @StateObject private var store: Store
    @StateObject private var engine: BumpEngine
    @StateObject private var streetPassEngine: StreetPassEngine
    @Environment(\.scenePhase) private var scenePhase

    @State private var stage: Stage
    @State private var tab: MainTab = .bump
    /// DEBUG demo only: a pre-seeded onboarding model with sample data.
    @State private var demoOnboarding: OnboardingModel?
    /// Height of the StreetPass pass card's single detent. @ScaledMetric so the
    /// card grows with Dynamic Type instead of clipping its buttons.
    @ScaledMetric(relativeTo: .body) private var passCardHeight: CGFloat = 470
    /// Decides when to ask about an interaction that already happened. Held
    /// here, not in a screen, because it must remember what was waved off for
    /// the rest of the launch.
    @State private var prompter = RatingPrompter()
    /// The app's single rating target. Published as `\.ratingTarget` so the
    /// Connections tab and a connection's detail screen can raise the same card.
    /// One copy on purpose: with a `@State` of its own, `promptForRatingIfDue`
    /// could not see a card raised on the Connections tab, would set this while
    /// a sheet was already up, and SwiftUI would silently drop the second one.
    @State private var connectionToRate: SavedConnection?
    /// Set when a bump has just been saved, so the Connections tab pushes that
    /// person instead of dropping the user back on the radar.
    @State private var savedConnection: SavedConnection?

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
            }
            promptForRatingIfDue()
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
                // The system tab bar is hidden; the site's frosted floating
                // pill (its header nav) stands in, with a blue active tab.
                TabView(selection: $tab) {
                    BumpScreen(engine: engine, store: store, onSaved: handleSavedConnection)
                        .tag(MainTab.bump)
                        .toolbar(.hidden, for: .tabBar)
                    ConnectionsScreen(store: store,
                                      pushedConnection: $savedConnection,
                                      tab: $tab)
                        .tag(MainTab.connections)
                        .toolbar(.hidden, for: .tabBar)
                    YouScreen(store: store, engine: engine)
                        .tag(MainTab.you)
                        .toolbar(.hidden, for: .tabBar)
                }
                .tint(BumpColor.action)
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    FloatingTabBar(selection: $tab)
                }
                .sheet(item: streetPassSheetBinding) { encounter in
                    StreetPassSheet(
                        encounter: encounter,
                        onBumpThem: {
                            streetPassEngine.dismissPendingEncounter()
                            engine.autoStart()
                        },
                        onNotNow: { streetPassEngine.dismissPendingEncounter() }
                    )
                    .presentationDetents([.height(passCardHeight)])
                    .presentationCornerRadius(Radius.extraLargeIncreased)
                    .presentationBackground(BumpColor.surfaceContainerLowest)
                    .presentationDragIndicator(.visible)
                }
                .rateInteraction(item: $connectionToRate, store: store,
                                 onSkip: { prompter.dismiss($0) })
            }
        }
        .animation(.easeInOut(duration: 0.25), value: stage)
        .onChange(of: scenePhase) { _, phase in
            engine.handleScenePhase(phase)
            streetPassEngine.handleScenePhase(phase)
            // Coming back to the app is the signal that a conversation is over,
            // which is why the question is asked here and not as the two of you
            // part — at that moment you are still talking.
            if phase == .active { promptForRatingIfDue() }
        }
        .onChange(of: stage) { _, newStage in
            if DemoMode.active == nil, newStage == .main { streetPassEngine.start() }
        }
        .onChange(of: store.settings) { _, _ in engine.applySettings() }
        .onChange(of: store.onboardingResets) { _, _ in
            demoOnboarding = nil
            stage = .welcome
        }
        .preferredColorScheme(.light)   // the brand is a warm light palette
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

    /// Raises the rating card when something is due. Silent under a DEBUG demo,
    /// before the main stage, while a card is already up, and while a StreetPass
    /// card is up — two sheets at once means SwiftUI drops one of them.
    private func promptForRatingIfDue() {
        guard DemoMode.active == nil,
              stage == .main,
              connectionToRate == nil,
              savedConnection == nil,
              streetPassEngine.pendingEncounter == nil else { return }
        connectionToRate = prompter.next(connections: store.connections,
                                         ratings: store.ratings)
    }

    /// A bump has just been kept: show the person, not the radar.
    private func handleSavedConnection(_ connection: SavedConnection) {
        savedConnection = connection
        tab = .connections
    }

    private var streetPassSheetBinding: Binding<StreetPassEncounter?> {
        Binding(
            get: { streetPassEngine.pendingEncounter },
            set: { if $0 == nil { streetPassEngine.dismissPendingEncounter() } }
        )
    }
}

// MARK: - Floating tab bar

enum MainTab: Hashable, CaseIterable {
    case bump, connections, you

    var title: String {
        switch self {
        case .bump: return "Bump"
        case .connections: return "Friends"
        case .you: return "You"
        }
    }

    var systemImage: String {
        switch self {
        case .bump: return "iphone.radiowaves.left.and.right"
        case .connections: return "person.2.fill"
        case .you: return "person.crop.circle"
        }
    }
}

/// The site's header pill, as a tab bar: frosted, floating, the active tab a
/// solid blue pill.
struct FloatingTabBar: View {
    @Binding var selection: MainTab

    var body: some View {
        HStack(spacing: 4) {
            ForEach(MainTab.allCases, id: \.self) { tab in
                let on = tab == selection
                Button {
                    withAnimation(BumpMotion.standard) { selection = tab }
                } label: {
                    VStack(spacing: 2) {
                        Image(systemName: tab.systemImage)
                            .font(.system(size: 19, weight: .semibold))
                        Text(tab.title)
                            .font(BumpFont.archivo(Archivo.semibold, 11.5, relativeTo: .caption2))
                    }
                    .foregroundStyle(on ? BumpColor.onPrimary : BumpColor.secondaryText)
                    .frame(maxWidth: .infinity, minHeight: 56)
                    .background {
                        if on {
                            RoundedRectangle(cornerRadius: 17, style: .continuous).fill(BumpColor.primary)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(tab.title)
                .accessibilityAddTraits(on ? [.isButton, .isSelected] : .isButton)
            }
        }
        .padding(5)
        .background(FrostedBackground(shape: RoundedRectangle(cornerRadius: 22, style: .continuous), raised: true))
        .padding(.horizontal, Space.m)
        .padding(.bottom, Space.xs)
    }
}
