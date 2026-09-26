import SwiftUI

struct RootView: View {
    @StateObject private var store: Store
    @StateObject private var engine: BumpEngine
    @Environment(\.scenePhase) private var scenePhase

    @State private var stage: Stage

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
                NavigationStack {
                    ProfileEditor(profile: $store.profile, isOnboarding: true) {
                        guard store.profile.isComplete else { return }
                        Haptics.success()
                        stage = .main
                    }
                }
                .transition(.opacity)

            case .main:
                TabView {
                    BumpScreen(engine: engine, store: store)
                        .tabItem { Label("Bump", systemImage: "hand.tap.fill") }
                    ConnectionsScreen(store: store)
                        .tabItem { Label("Connections", systemImage: "person.2.fill") }
                    YouScreen(store: store, engine: engine)
                        .tabItem { Label("You", systemImage: "person.crop.circle") }
                }
                .tint(BumpColor.action)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: stage)
        .onChange(of: scenePhase) { _, phase in engine.handleScenePhase(phase) }
        .onChange(of: store.settings) { _, _ in engine.applySettings() }
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
        case .connections, .you, .tools:
            store.profile = PreviewFixtures.profile
            if demo == .connections { PreviewFixtures.seed(store) }
            stage = .main
        }
        #endif
    }
}
