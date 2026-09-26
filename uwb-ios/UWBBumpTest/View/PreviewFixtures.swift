import Foundation

/// Fixtures for SwiftUI previews and simulator UI checks ONLY.
///
/// These are obviously fictional people. They are never used at runtime, never
/// presented as nearby phones, never presented as live sensor readings, and a
/// connection built from them is never recorded as a successful physical test —
/// nothing here touches `Store`'s on-disk files unless a preview asks for an
/// in-memory store.
enum PreviewFixtures {

    static let profile = Profile(
        displayName: "Jared",
        bio: "Building things at 2am.",
        interests: [
            InterestCatalog.byID["jazz-piano"]!,
            InterestCatalog.byID["sourdough"]!,
            InterestCatalog.byID["typography"]!,
            InterestCatalog.byID["speedrunning"]!,
        ]
    )

    static let partner = SharedProfile(
        displayName: "Sample Partner (demo)",
        bio: "Demo data — not a real person.",
        interests: [
            InterestCatalog.byID["jazz-piano"]!,
            InterestCatalog.byID["typography"]!,
            InterestCatalog.byID["birding"]!,
        ]
    )

    static var insight: ConnectionInsight {
        ConnectionInsight(
            highlights: InterestMatcher.overlap(profile.shareable, partner),
            opener: "What's one jazz standard you never get tired of playing?",
            openerSource: .fallbackTemplate
        )
    }

    static var result: BumpEngine.Result {
        BumpEngine.Result(partner: partner, insight: insight,
                          evidence: .motionAndUWB, roomName: "demo", metOn: Date())
    }

    /// Add clearly-labelled demo rows to a store, for simulator screenshots.
    @MainActor
    static func seed(_ store: Store) {
        store.save(SavedConnection(partnerName: partner.displayName,
                                   partnerBio: partner.bio,
                                   metOn: Date().addingTimeInterval(-86_400),
                                   roomName: "demo",
                                   insight: insight,
                                   pairingEvidence: .motionAndUWB))
        store.save(SavedConnection(partnerName: "Second Sample (demo)",
                                   partnerBio: "Demo data — not a real person.",
                                   metOn: Date().addingTimeInterval(-3 * 86_400),
                                   roomName: "demo",
                                   insight: ConnectionInsight(highlights: [], opener: "What brought you here tonight?",
                                                              openerSource: .fallbackTemplate),
                                   pairingEvidence: .manualSelection))
    }

    /// An in-memory store so a preview never writes over a real profile.
    @MainActor
    static func populatedStore() -> Store {
        let store = Store(inMemory: true)
        store.profile = profile
        store.save(SavedConnection(partnerName: partner.displayName,
                                   partnerBio: partner.bio,
                                   metOn: Date().addingTimeInterval(-86_400),
                                   roomName: "demo",
                                   insight: insight,
                                   pairingEvidence: .motionAndUWB))
        return store
    }
}
