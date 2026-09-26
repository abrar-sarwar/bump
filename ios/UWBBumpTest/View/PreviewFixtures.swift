import Foundation

/// Fixtures for SwiftUI previews and simulator UI checks ONLY.
///
/// These are obviously fictional people. They are never used at runtime, never
/// presented as nearby phones, never presented as live sensor readings, and a
/// connection built from them is never recorded as a successful physical test.
/// nothing here touches `Store`'s on-disk files unless a preview asks for an
/// in-memory store.
enum PreviewFixtures {

    static let profile = Profile(
        displayName: "Jared",
        bio: "Building things at 2am.",
        interests: [
            InterestCatalog.byID["jazz"]!,
            InterestCatalog.byID["baking"]!,
            InterestCatalog.byID["photography"]!,
            InterestCatalog.byID["rpgs"]!,
            InterestCatalog.byID["coffee"]!,
        ]
    )

    static let partner = SharedProfile(
        displayName: "Sample Partner (demo)",
        bio: "Demo data. Not a real person.",
        interests: [
            InterestCatalog.byID["jazz"]!,
            InterestCatalog.byID["photography"]!,
            InterestCatalog.byID["hiking"]!,
            InterestCatalog.byID["espresso"]!,
        ],
        details: [SharedFact(id: "demo-goal", kind: .goal, text: "Learn to bake bread")]
    )

    static var insight: ConnectionInsight {
        ConnectionInsight(
            highlights: InterestMatcher.overlap(profile.shareable, partner),
            opener: "What's one jazz record you never get tired of?",
            openerSource: .fallbackTemplate,
            talkingPoints: TalkingPointMatcher.templatePoints(
                TalkingPointMatcher.candidates(profile.shareable, partner))
        )
    }

    static var result: BumpEngine.Result {
        BumpEngine.Result(partner: partner, insight: insight,
                          evidence: .motionAndUWB, roomName: "demo", metOn: Date())
    }

    /// Stable ids for the two demo connections, so re-running a demo re-seeds
    /// the same two rows instead of stacking up another copy every launch
    /// (`Store.save` is idempotent by id).
    private static let firstConnectionID = UUID(uuidString: "00000000-0000-0000-0000-00000000dec0")!
    private static let secondConnectionID = UUID(uuidString: "00000000-0000-0000-0000-00000000dec1")!

    /// Clearly-labelled passers-by, for the notifications feed.
    static var streetpasses: [StreetpassEvent] {
        [
            StreetpassEvent(peerName: "Passer-by One (demo)",
                            seenAt: Date().addingTimeInterval(-40 * 60), roomName: "nearby"),
            StreetpassEvent(peerName: "Passer-by Two (demo)",
                            seenAt: Date().addingTimeInterval(-6 * 3_600), roomName: "nearby"),
            StreetpassEvent(peerName: "Passer-by Three (demo)",
                            seenAt: Date().addingTimeInterval(-2 * 86_400), roomName: "demo"),
        ]
    }

    /// Add clearly-labelled demo rows to a store, for simulator screenshots.
    @MainActor
    static func seed(_ store: Store) {
        store.save(SavedConnection(id: firstConnectionID,
                                   partnerName: partner.displayName,
                                   partnerBio: partner.bio,
                                   metOn: Date().addingTimeInterval(-86_400),
                                   roomName: "demo",
                                   insight: insight,
                                   pairingEvidence: .motionAndUWB))
        store.save(SavedConnection(id: secondConnectionID,
                                   partnerName: "Second Sample (demo)",
                                   partnerBio: "Demo data. Not a real person.",
                                   metOn: Date().addingTimeInterval(-3 * 86_400),
                                   roomName: "demo",
                                   insight: ConnectionInsight(highlights: [], opener: "What brought you here tonight?",
                                                              openerSource: .fallbackTemplate),
                                   pairingEvidence: .manualSelection))
        for pass in streetpasses {
            store.recordStreetpass(name: pass.peerName, roomName: pass.roomName, at: pass.seenAt)
        }
    }

    /// An in-memory store so a preview never writes over a real profile.
    @MainActor
    static func populatedStore() -> Store {
        let store = Store(inMemory: true)
        store.profile = profile
        store.save(SavedConnection(id: firstConnectionID,
                                   partnerName: partner.displayName,
                                   partnerBio: partner.bio,
                                   metOn: Date().addingTimeInterval(-86_400),
                                   roomName: "demo",
                                   insight: insight,
                                   pairingEvidence: .motionAndUWB))
        for pass in streetpasses {
            store.recordStreetpass(name: pass.peerName, roomName: pass.roomName, at: pass.seenAt)
        }
        return store
    }

    // MARK: Onboarding (SAMPLE DATA: clearly fictional, never sent anywhere)
    #if DEBUG

    static let sampleIntro = "Hi, I'm Sam. I play jazz piano and I've been getting into climbing. I work at a robotics lab. I'd love to meet people building hardware."

    @MainActor
    static func onboardingStore() -> Store {
        let store = Store(inMemory: true)
        store.privacy.cloud = .allowed
        return store
    }

    @MainActor
    static func onboarding(_ step: OnboardingModel.Step) -> OnboardingModel {
        let model = OnboardingModel(store: onboardingStore(), cloud: { nil })
        model.name = "Sam (sample)"
        typealias Item = OnboardingModel.Item
        let items: [Item] = [
            Item(id: "s1", kind: .interest, text: "Jazz piano", evidence: "I play jazz piano", origin: .grok, fromIntro: true),
            Item(id: "s2", kind: .interest, text: "Climbing", evidence: "I've been getting into climbing", origin: .grok, fromIntro: true),
            Item(id: "s3", kind: .experience, text: "Works at a robotics lab", evidence: "I work at a robotics lab", origin: .grok, fromIntro: true),
            Item(id: "s4", kind: .goal, text: "Meet people building hardware", evidence: "meet people building hardware", origin: .grok, fromIntro: true),
            Item(id: "s5", kind: .interest, text: "Coffee", evidence: "pour-over coffee", origin: .grok, included: false),
        ]
        let q = OnboardingModel.Question(text: "You mentioned climbing. Where do you usually go?", origin: .grok)
        switch step {
        case .name:
            break
        case .intro:
            model.seedSample(step: .intro, transcript: sampleIntro, bio: "", items: [], answered: [],
                             current: nil, fromVoice: true)
        case .questions:
            model.seedSample(step: .questions, transcript: sampleIntro, bio: "Jazz pianist, new boulderer, robotics by day.",
                             items: Array(items.prefix(4)),
                             answered: [.init(question: .init(text: "What kind of hardware are you building?", origin: .grok), answer: "Small legged robots")],
                             current: q, fromVoice: true)
        case .card:
            model.seedSample(step: .card, transcript: sampleIntro, bio: "Jazz pianist, new boulderer, robotics by day.",
                             items: items, answered: [], current: nil, fromVoice: true)
        }
        return model
    }
    #endif
}
