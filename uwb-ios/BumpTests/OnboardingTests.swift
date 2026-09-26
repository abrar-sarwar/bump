import XCTest
@testable import UWBBumpTest

// Everything in this file is MOCKED: no network, no xAI, no microphone.
// `StubCloud` stands in for the BUMP server. Live-API checks live in
// `bump-api/scripts/smoke.js` and are run by hand with a real key.

// MARK: - Stubs

/// A scripted stand-in for the BUMP server.
final class StubCloud: OnboardingCloud, ConversationService.CloudPhraser, @unchecked Sendable {
    var draftResult: Result<BumpAPIClient.Draft, BumpAPIError> = .failure(.offline)
    var followupResult: Result<BumpAPIClient.Followup, BumpAPIError> = .failure(.offline)
    var pointsResult: Result<BumpAPIClient.TalkingPoints, BumpAPIError> = .failure(.offline)
    var delay: TimeInterval = 0
    private(set) var calls: [String] = []
    private(set) var lastFollowupKnown: [String] = []

    static let grok = BumpAPIClient.Generator(provider: "xai", model: "grok-test")

    private func wait() async throws {
        if delay > 0 { try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000)) }
    }

    func transcribe(fileURL: URL, onUploaded: @escaping @Sendable () -> Void) async throws -> BumpAPIClient.Transcription {
        calls.append("transcribe")
        throw BumpAPIError.offline
    }

    func draft(transcript: String) async throws -> BumpAPIClient.Draft {
        calls.append("draft")
        try await wait()
        return try draftResult.get()
    }

    func followup(known: [(kind: ProfileFact.Kind, label: String)], asked: [String], answer: String) async throws -> BumpAPIClient.Followup {
        calls.append("followup")
        lastFollowupKnown = known.map(\.label)
        try await wait()
        return try followupResult.get()
    }

    func talkingPoints(_ candidates: [BumpAPIClient.Candidate], timeout: TimeInterval) async throws -> BumpAPIClient.TalkingPoints {
        calls.append("talkingPoints")
        try await wait()
        return try pointsResult.get()
    }
}

private func fact(_ kind: String, _ label: String, _ source: String) -> BumpAPIClient.ProposedFact {
    .init(kind: kind, label: label, source: source)
}

private let intro = "Hi, I'm Sam. I play jazz piano and I've been getting into climbing. I'd love to meet people building hardware."

@MainActor
private func waitUntilIdle(_ model: OnboardingModel, timeout: TimeInterval = 3) async {
    let start = Date()
    // Yield first so a just-started task can flip `busy`.
    try? await Task.sleep(nanoseconds: 20_000_000)
    while model.busy != .idle && Date().timeIntervalSince(start) < timeout {
        try? await Task.sleep(nanoseconds: 20_000_000)
    }
}

// MARK: - Catalogue regressions

final class CatalogRegressionTests: XCTestCase {

    func testCoffeeIsNotEspresso() {
        XCTAssertEqual(InterestCatalog.canonical(from: "coffee")?.id, "coffee")
        XCTAssertNotEqual(InterestCatalog.canonical(from: "Coffee")?.id, "espresso")
        XCTAssertEqual(InterestCatalog.canonical(from: "Espresso")?.id, "espresso")
    }

    func testJazzIsNotJazzPiano() {
        XCTAssertEqual(InterestCatalog.canonical(from: "jazz")?.id, "jazz")
        // "Jazz piano" is no longer a catalogue entry: it stays the person's own
        // words, grouped under Music, and still never equals plain "Jazz".
        XCTAssertEqual(InterestCatalog.canonical(from: "Jazz piano")?.id, "custom:jazz piano")
        XCTAssertEqual(InterestCatalog.canonical(from: "Jazz piano")?.parent, "music")
    }

    func testBroadAndSpecificStayDistinctInOverlap() {
        let jazz = SharedProfile(displayName: "A", bio: "", interests: [InterestCatalog.canonical(from: "jazz")!])
        let piano = SharedProfile(displayName: "B", bio: "", interests: [InterestCatalog.canonical(from: "jazz piano")!])
        XCTAssertTrue(InterestMatcher.overlap(jazz, piano).isEmpty, "jazz and jazz piano are NOT the same interest")

        let coffee = SharedProfile(displayName: "A", bio: "", interests: [InterestCatalog.canonical(from: "coffee")!])
        let espresso = SharedProfile(displayName: "B", bio: "", interests: [InterestCatalog.canonical(from: "espresso")!])
        XCTAssertTrue(InterestMatcher.overlap(coffee, espresso).isEmpty)

        let music = SharedProfile(displayName: "A", bio: "", interests: [InterestCatalog.byID["music"]!])
        XCTAssertTrue(InterestMatcher.overlap(music, jazz).isEmpty, "a broad category never becomes a specific one")
    }

    func testRelatedButDifferentCustomInterestsDoNotMatch() {
        let karate = SharedProfile(displayName: "A", bio: "", interests: [InterestCatalog.canonical(from: "karate")!])
        let bjj = SharedProfile(displayName: "B", bio: "", interests: [InterestCatalog.canonical(from: "bjj")!])
        XCTAssertTrue(InterestMatcher.overlap(karate, bjj).isEmpty)
        XCTAssertEqual(InterestCatalog.canonical(from: "karate")?.parent, "movement")
    }

    func testCatalogueIsConsistent() {
        let ids = Set(InterestCatalog.all.map(\.id))
        XCTAssertEqual(ids.count, InterestCatalog.all.count, "ids are unique")
        let labels = InterestCatalog.all.map { InterestCatalog.normalize($0.label) }
        XCTAssertEqual(Set(labels).count, labels.count, "labels are unique")
        XCTAssertLessThanOrEqual(InterestCatalog.all.count, 150, "bump-api accepts at most 150 catalogue labels")
        for (key, id) in InterestCatalog.synonyms { XCTAssertTrue(ids.contains(id), "synonym \(key) → missing \(id)") }
        let broad = Set(InterestCatalog.groups.map(\.category.id))
        for (key, parent) in InterestCatalog.parentHints {
            XCTAssertTrue(broad.contains(parent), "hint \(key) → missing topic \(parent)")
            XCTAssertNil(InterestCatalog.byID[key], "\(key) is in the catalogue, so it doesn't need a hint")
        }
        XCTAssertEqual(Set(LocalDrafter.categoryQuestions.keys), broad, "every topic has a follow-up question")
    }

    func testBroadTopicsOpenIntoVariations() {
        let collecting = InterestCatalog.groups.first { $0.category.id == "collecting" }!
        XCTAssertTrue(collecting.children.map(\.label).contains("Figures"))
        XCTAssertTrue(collecting.children.map(\.label).contains("Rocks & minerals"))
        XCTAssertEqual(InterestCatalog.canonical(from: "collecting vinyl")?.id, "vinyl", "older profiles keep matching")
        let coffee = InterestCatalog.groups.first { $0.category.id == "coffee" }!
        XCTAssertTrue(coffee.children.map(\.id).contains("espresso"))
        // Variation and topic never match as shared; they become complementary.
        let a = SharedProfile(displayName: "A", bio: "", interests: [InterestCatalog.byID["coffee"]!])
        let b = SharedProfile(displayName: "B", bio: "", interests: [InterestCatalog.byID["cold-brew"]!])
        XCTAssertTrue(InterestMatcher.overlap(a, b).isEmpty)
        XCTAssertEqual(TalkingPointMatcher.candidates(a, b).first?.kind, .complementary)
    }

    func testSharedCustomInterestHidesItsBroadTopic() {
        let a = SharedProfile(displayName: "A", bio: "", interests: ["Music", "Jazz piano"].compactMap(InterestCatalog.canonical(from:)))
        let b = SharedProfile(displayName: "B", bio: "", interests: ["Music", "jazz piano"].compactMap(InterestCatalog.canonical(from:)))
        XCTAssertEqual(InterestMatcher.overlap(a, b).map(\.interestID), ["custom:jazz piano"])
    }

    func testRemovedMisleadingSynonymsStayRemoved() {
        // Each of these used to silently narrow or broaden what someone said.
        for key in ["coffee", "jazz", "pour over", "latte art", "keyboards", "kayaking",
                    "bjj", "karate", "jiu jitsu", "tabletop", "bread baking", "jogging", "climbing gym"] {
            XCTAssertNil(InterestCatalog.synonyms[key], "\(key) must not be a synonym")
        }
        XCTAssertNotEqual(InterestCatalog.canonical(from: "pour over")?.id, "espresso")
        XCTAssertNotEqual(InterestCatalog.canonical(from: "keyboards")?.id, "mechanical-keyboards")
    }
}

// MARK: - Grounding

final class GroundingTests: XCTestCase {

    func testSupportsIsCaseAndPunctuationInsensitiveButWordBounded() {
        XCTAssertTrue(Grounding.supports(intro, "i play JAZZ piano"))
        XCTAssertTrue(Grounding.supports("I\u{2019}m into climbing", "I'm into climbing"))
        XCTAssertFalse(Grounding.supports(intro, "ja"), "partial words are not evidence")
        XCTAssertFalse(Grounding.supports(intro, "I play the violin"))
    }

    func testFactsWithoutEvidenceAreDroppedAndDuplicatesRemoved() {
        let facts = Grounding.facts([
            fact("interest", "Jazz piano", "I play jazz piano"),
            fact("interest", "Jazz Piano", "I play jazz piano"),        // duplicate
            fact("interest", "Surfing", "I love surfing"),              // not said
            fact("hobby", "Climbing", "getting into climbing"),     // unknown kind
            fact("goal", "Meet hardware people", "meet people building hardware"),
        ], groundedIn: intro, limit: 12)
        XCTAssertEqual(facts.map(\.text), ["Jazz piano", "Meet hardware people"])
        XCTAssertEqual(facts.first?.evidence, "I play jazz piano")
    }

    func testClippingCountsUnicodeScalarsLikeTheServer() {
        let flags = String(repeating: "🇺🇸", count: 10)       // 20 scalars, 10 characters
        let clipped = flags.clipped(7)
        XCTAssertLessThanOrEqual(clipped.unicodeScalars.count, 7)
        XCTAssertTrue(clipped.allSatisfy { $0 == "🇺🇸" }, "never leaves half a flag")
        XCTAssertEqual("short".clipped(60), "short")
    }

    func testQuestionsMustBeQuestionsWithoutScoresOrRepeats() {
        XCTAssertNil(Grounding.question("Tell me more.", notIn: []))
        XCTAssertNil(Grounding.question("You're 90% compatible — why?", notIn: []))
        XCTAssertNil(Grounding.question("Where do you climb?", notIn: ["where do you climb?"]))
        XCTAssertEqual(Grounding.question("Where do you climb?", notIn: []), "Where do you climb?")
    }
}

// MARK: - Local drafting

final class LocalDrafterTests: XCTestCase {

    func testFindsSpecificInterestsAndNeverNarrows() {
        let text = "I love electronic music. I drink way too much coffee."
        let s = LocalDrafter.extract(from: text)
        let ids = s.filter { $0.kind == .interest }.compactMap { InterestCatalog.canonical(from: $0.label)?.id }
        XCTAssertTrue(ids.contains("electronic"))
        XCTAssertFalse(ids.contains("music"), "longest match wins")
        XCTAssertTrue(ids.contains("coffee"))
        XCTAssertFalse(ids.contains("espresso"))
        for suggestion in s {
            XCTAssertTrue(Grounding.supports(text, suggestion.source))
        }
    }

    func testGoalsAndExperiencesKeepTheirWords() {
        let text = "I work at a robotics lab. I'm hoping to find a climbing partner."
        let s = LocalDrafter.extract(from: text)
        XCTAssertTrue(s.contains { $0.kind == .experience && $0.label.hasPrefix("I work at a robotics lab") })
        XCTAssertTrue(s.contains { $0.kind == .goal && $0.label == "Find a climbing partner" })
        for suggestion in s { XCTAssertTrue(Grounding.supports(text, suggestion.source)) }
    }

    func testQuestionsSkipWhatWasAlreadySaid() {
        // Broad "music" with no specific → ask about music.
        XCTAssertEqual(LocalDrafter.nextQuestion(known: [(.interest, "Music")], asked: []),
                       LocalDrafter.categoryQuestions["music"])
        // Already specific → don't ask about music again.
        let q = LocalDrafter.nextQuestion(known: [(.interest, "Music"), (.interest, "Jazz")], asked: [])
        XCTAssertNotEqual(q, LocalDrafter.categoryQuestions["music"])
        // Goal known → no goal question.
        let q2 = LocalDrafter.nextQuestion(known: [(.goal, "Find a band")], asked: [])
        XCTAssertNotEqual(q2, LocalDrafter.goalQuestion)
        // Hard cap.
        XCTAssertNil(LocalDrafter.nextQuestion(known: [], asked: ["a?", "b?", "c?"]))
    }
}

// MARK: - Talking points

final class TalkingPointTests: XCTestCase {

    private func p(_ interests: [String], details: [SharedFact] = []) -> SharedProfile {
        SharedProfile(displayName: "X", bio: "", interests: interests.compactMap(InterestCatalog.canonical(from:)),
                      details: details)
    }

    func testSharedAndComplementaryAreSeparate() {
        let a = p(["Climbing", "Jazz piano"])
        let b = p(["Climbing", "jazz"])
        let c = TalkingPointMatcher.candidates(a, b)
        XCTAssertEqual(c.filter { $0.kind == .shared }.map(\.id), ["shared:climbing"])
        let related = c.filter { $0.kind == .complementary }
        XCTAssertEqual(related.count, 1)
        XCTAssertEqual(Set([related[0].mine, related[0].theirs]), ["Jazz piano", "Jazz"])
    }

    func testGoalMeetsExperience() {
        let a = p([], details: [SharedFact(id: "g1", kind: .goal, text: "Learn robotics")])
        let b = p(["Robotics"])
        let c = TalkingPointMatcher.candidates(a, b)
        XCTAssertEqual(c.count, 1)
        XCTAssertEqual(c[0].kind, .complementary)
        XCTAssertEqual(c[0].mine, "Learn robotics")
        XCTAssertEqual(c[0].theirs, "Robotics")
    }

    func testNothingInCommonMeansNoPoints() {
        XCTAssertTrue(TalkingPointMatcher.candidates(p(["Chess"]), p(["Baking"])).isEmpty)
    }

    func testTemplatesAreNeutralQuestions() {
        let c = TalkingPointMatcher.candidates(p(["Climbing", "Jazz piano"]), p(["Climbing", "jazz"]))
        for point in TalkingPointMatcher.templatePoints(c) {
            XCTAssertTrue(point.prompt.hasSuffix("?"))
            XCTAssertEqual(point.source, .fallbackTemplate)
            XCTAssertFalse(point.prompt.lowercased().contains("ask them"))
        }
    }

    func testMirroringFlipsEvidenceForThePartner() {
        let insight = ConnectionInsight(
            highlights: [SharedHighlight(interestID: "x", statement: "s", yourEntry: "Mine", theirEntry: "Theirs", specificity: 2)],
            opener: "Q?", openerSource: .grok,
            talkingPoints: [TalkingPoint(id: "t", kind: .complementary, prompt: "Q?", yourEntry: "Jazz piano", theirEntry: "Jazz", source: .grok)])
        let m = insight.mirrored()
        XCTAssertEqual(m.highlights[0].yourEntry, "Theirs")
        XCTAssertEqual(m.talkingPoints[0].yourEntry, "Jazz")
        XCTAssertEqual(m.talkingPoints[0].theirEntry, "Jazz piano")
        XCTAssertEqual(m.opener, insight.opener, "both phones show the same text")
    }
}

// MARK: - Insight generation (During)

final class InsightTests: XCTestCase {

    private let mine = SharedProfile(displayName: "A", bio: "secret bio", interests: [InterestCatalog.byID["climbing"]!])
    private let theirs = SharedProfile(displayName: "B", bio: "", interests: [InterestCatalog.byID["climbing"]!])

    func testGrokResultIsValidatedAndLabelled() async {
        let stub = StubCloud()
        stub.pointsResult = .success(.init(points: [
            .init(candidateId: "shared:climbing", prompt: "Where do you both like to climb?"),
            .init(candidateId: "invented:skydiving", prompt: "Skydiving next?"),
        ], opener: "What got you both into climbing?", generator: StubCloud.grok))
        let insight = await ConversationService.makeInsight(mine: mine, theirs: theirs, cloud: stub)
        XCTAssertEqual(insight.openerSource, .grok)
        XCTAssertEqual(insight.talkingPoints.map(\.id), ["shared:climbing"], "unknown candidate ids are dropped")
        XCTAssertEqual(insight.talkingPoints.first?.kind, .shared, "kind comes from our matcher, not the model")
    }

    func testMalformedGrokFallsBackAndIsNeverLabelledGrok() async {
        let stub = StubCloud()
        stub.pointsResult = .success(.init(points: [], opener: "no question mark", generator: StubCloud.grok))
        let insight = await ConversationService.makeInsight(mine: mine, theirs: theirs, cloud: stub)
        XCTAssertNotEqual(insight.openerSource, .grok)
        XCTAssertTrue(insight.talkingPoints.allSatisfy { $0.source != .grok })
        XCTAssertFalse(insight.talkingPoints.isEmpty, "deterministic points still appear")
    }

    func testScoresAreRejected() async {
        let stub = StubCloud()
        stub.pointsResult = .success(.init(points: [.init(candidateId: "shared:climbing", prompt: "You're 95% compatible — why?")],
                                           opener: "You're 95% compatible — why?", generator: StubCloud.grok))
        let insight = await ConversationService.makeInsight(mine: mine, theirs: theirs, cloud: stub)
        XCTAssertNotEqual(insight.openerSource, .grok)
        XCTAssertFalse(insight.opener.contains("%"))
    }

    func testSlowGrokIsAbandonedQuickly() async {
        let stub = StubCloud()
        stub.delay = 5
        stub.pointsResult = .success(.init(points: [], opener: "Late?", generator: StubCloud.grok))
        let start = Date()
        let insight = await ConversationService.makeInsight(mine: mine, theirs: theirs, cloud: stub, cloudBudget: 0.3)
        // Grok is abandoned at 0.3 s. On a host with Apple Intelligence the
        // on-device opener may then use up to its own budget, but never beyond
        // the overall ceiling.
        XCTAssertLessThan(Date().timeIntervalSince(start), ConversationService.totalBudget + 1.5)
        XCTAssertNotEqual(insight.openerSource, .grok)
        XCTAssertEqual(stub.calls, ["talkingPoints"], "one try, no retries")
    }

    func testNoCloudMeansNoCloudCall() async {
        let insight = await ConversationService.makeInsight(mine: mine, theirs: theirs, cloud: nil)
        XCTAssertNotEqual(insight.openerSource, .grok)
    }

    func testOnlyOneOfTwoNearbyHostsStepsDown() {
        // Both hosts evaluate the rule about each other; exactly one yields.
        XCTAssertTrue(BumpEngine.shouldYield(me: "Sam#B2", otherHost: "Ada#A1"))
        XCTAssertFalse(BumpEngine.shouldYield(me: "Ada#A1", otherHost: "Sam#B2"))
        XCTAssertFalse(BumpEngine.shouldYield(me: "Ada#A1", otherHost: "Ada#A1"), "never yield to yourself")
        XCTAssertFalse(BumpEngine.shouldYield(me: "Ada#A1", otherHost: ""))
    }

    func testGeneratorChoiceNeedsBothConsentsAndIsSymmetric() {
        let yes = Wire.PartnerCaps(cloudConsent: true, grokReady: true)
        let consentNoServer = Wire.PartnerCaps(cloudConsent: true, grokReady: false)
        let no = Wire.PartnerCaps(cloudConsent: false, grokReady: false)

        // Both allow, only B can reach Grok → B generates, on both phones.
        XCTAssertEqual(BumpEngine.generator(me: "a", partner: "b", myCaps: consentNoServer, theirCaps: yes, coordinatorPick: "a"), "b")
        XCTAssertEqual(BumpEngine.generator(me: "b", partner: "a", myCaps: yes, theirCaps: consentNoServer, coordinatorPick: "a"), "b")

        // One person said no → the coordinator's pick stands and Grok isn't used.
        XCTAssertEqual(BumpEngine.generator(me: "a", partner: "b", myCaps: no, theirCaps: yes, coordinatorPick: "a"), "a")
        XCTAssertEqual(BumpEngine.generator(me: "b", partner: "a", myCaps: yes, theirCaps: no, coordinatorPick: "a"), "a")

        // Both can → lowest id, regardless of Apple Intelligence.
        XCTAssertEqual(BumpEngine.generator(me: "z", partner: "c", myCaps: yes, theirCaps: yes, coordinatorPick: "z"), "c")
        XCTAssertEqual(BumpEngine.generator(me: "c", partner: "z", myCaps: yes, theirCaps: yes, coordinatorPick: "z"), "c")
    }
}

// MARK: - Onboarding flow

@MainActor
final class OnboardingModelTests: XCTestCase {

    private func model(cloud: PrivacyPreferences.Cloud = .allowed, stub: StubCloud?) -> (OnboardingModel, Store) {
        let store = Store(inMemory: true)
        store.privacy.cloud = cloud
        let m = OnboardingModel(store: store, cloud: { stub })
        m.name = "Sam"
        m.step = .intro
        m.typing = true
        return (m, store)
    }

    private func goodDraft() -> BumpAPIClient.Draft {
        .init(bio: .init(text: "I play jazz piano and boulder.", sources: ["I play jazz piano"]),
              facts: [fact("interest", "Jazz piano", "I play jazz piano"),
                      fact("interest", "Climbing", "getting into climbing"),
                      fact("goal", "Meet people building hardware", "meet people building hardware")],
              question: "Where do you usually climb?", generator: StubCloud.grok)
    }

    func testSuccessfulGrokOnboarding() async {
        let stub = StubCloud()
        stub.draftResult = .success(goodDraft())
        stub.followupResult = .success(.init(facts: [fact("experience", "Climbs at Stone Gardens", "Stone Gardens")],
                                             question: nil, generator: StubCloud.grok))
        let (m, store) = model(stub: stub)
        m.transcript = intro
        m.draftProfile()
        await waitUntilIdle(m)

        XCTAssertEqual(m.step, .questions)
        XCTAssertEqual(m.current?.origin, .grok)
        XCTAssertEqual(m.bio, "I play jazz piano and boulder.")
        XCTAssertTrue(m.items.allSatisfy { $0.origin == .grok && $0.evidence != nil })

        m.answer = "Mostly at Stone Gardens"
        m.submitAnswer()
        await waitUntilIdle(m)
        XCTAssertEqual(m.step, .card, "Grok returned no further question")
        XCTAssertTrue(m.items.contains { $0.text == "Climbs at Stone Gardens" && $0.evidence == "Stone Gardens" })
        XCTAssertFalse(stub.lastFollowupKnown.isEmpty, "follow-up sends what was kept, not the transcript")

        XCTAssertTrue(m.finish())
        XCTAssertEqual(store.profile.interests.map(\.id), ["custom:jazz piano", "climbing"])
        XCTAssertEqual(store.profile.goals.map(\.text), ["Meet people building hardware"])
        XCTAssertEqual(store.profile.interestEvidence["custom:jazz piano"], "I play jazz piano")
    }

    func testSkippingFreeTextStillWorks() async {
        let stub = StubCloud()
        let (m, store) = model(stub: stub)
        m.skipIntro()
        XCTAssertEqual(m.step, .card)
        XCTAssertFalse(m.canFinish)
        m.toggleCatalog(InterestCatalog.byID["chess"]!)
        XCTAssertTrue(m.finish())
        XCTAssertEqual(store.profile.interests.map(\.id), ["chess"])
        XCTAssertTrue(stub.calls.isEmpty, "nothing was sent")
    }

    func testSkippingAQuestion() async {
        let stub = StubCloud()
        stub.draftResult = .success(goodDraft())
        stub.followupResult = .success(.init(facts: [fact("interest", "Surfing", "surfing")], question: "What are you building?",
                                             generator: StubCloud.grok))
        let (m, _) = model(stub: stub)
        m.transcript = intro
        m.draftProfile()
        await waitUntilIdle(m)
        m.skipQuestion()
        await waitUntilIdle(m)
        XCTAssertEqual(m.answered.first?.answer, nil)
        XCTAssertFalse(m.items.contains { $0.text == "Surfing" }, "a skipped answer yields no facts")
        XCTAssertEqual(m.current?.text, "What are you building?")
    }

    func testEditingAndApprovalControlWhatIsSaved() async {
        let stub = StubCloud()
        var draft = goodDraft()
        draft = .init(bio: nil, facts: draft.facts + [fact("interest", "Espresso", "coffee")],
                      question: nil, generator: StubCloud.grok)
        stub.draftResult = .success(draft)
        let (m, store) = model(stub: stub)
        m.transcript = intro + " I drink too much coffee."
        m.draftProfile()
        await waitUntilIdle(m)
        XCTAssertEqual(m.step, .card)

        // Person corrects Grok's over-specific guess, and unchecks one item.
        let espresso = m.items.first { $0.text == "Espresso" }!
        m.rename(espresso.id, to: "coffee")
        let climbing = m.items.first { $0.text == "Climbing" }!
        m.toggle(climbing.id)
        XCTAssertTrue(m.finish())

        XCTAssertTrue(store.profile.interests.contains { $0.id == "coffee" })
        XCTAssertFalse(store.profile.interests.contains { $0.id == "espresso" })
        XCTAssertFalse(store.profile.interests.contains { $0.id == "climbing" }, "unchecked items are not saved")
    }

    func testMissingCredentialsFallsBackToThePhone() async {
        let stub = StubCloud()
        stub.draftResult = .failure(.server(status: 503, code: "not_configured"))
        let (m, _) = model(stub: stub)
        m.transcript = intro
        m.draftProfile()
        await waitUntilIdle(m)
        XCTAssertTrue(m.items.allSatisfy { $0.origin == .onPhone })
        XCTAssertTrue(m.items.contains { $0.text == "Jazz" })
        XCTAssertNotNil(m.notice)
        XCTAssertTrue(m.notice!.contains("no Grok key"))
        XCTAssertNotEqual(m.current?.origin, .grok)
    }

    func testOfflineFallsBack() async {
        let stub = StubCloud()
        stub.draftResult = .failure(.offline)
        let (m, _) = model(stub: stub)
        m.transcript = intro
        m.draftProfile()
        await waitUntilIdle(m)
        XCTAssertTrue(m.items.allSatisfy { $0.origin == .onPhone })
        XCTAssertTrue(m.notice?.contains("couldn't reach") ?? false)
    }

    func testNoServerConfiguredFallsBackWithoutCalling() async {
        let (m, _) = model(stub: nil)       // resolve() found no URL
        m.transcript = intro
        m.draftProfile()
        await waitUntilIdle(m)
        XCTAssertFalse(m.items.isEmpty)
        XCTAssertTrue(m.items.allSatisfy { $0.origin == .onPhone })
    }

    func testTimeoutFallsBack() async {
        let stub = StubCloud()
        stub.delay = 3
        stub.draftResult = .success(goodDraft())
        let (m, _) = model(stub: stub)
        m.deadlines.draft = 0.2
        m.transcript = intro
        m.draftProfile()
        await waitUntilIdle(m, timeout: 2)
        XCTAssertEqual(m.busy, .idle)
        XCTAssertTrue(m.items.allSatisfy { $0.origin == .onPhone })
        XCTAssertTrue(m.notice?.contains("too long") ?? false)
    }

    func testMalformedResponseIsRejected() async {
        let stub = StubCloud()
        // Nothing grounded in what the person said.
        stub.draftResult = .success(.init(bio: .init(text: "Loves skydiving.", sources: ["I love skydiving"]),
                                          facts: [fact("interest", "Skydiving", "I love skydiving")],
                                          question: "Why skydiving?", generator: StubCloud.grok))
        let (m, _) = model(stub: stub)
        m.transcript = intro
        m.draftProfile()
        await waitUntilIdle(m)
        XCTAssertFalse(m.items.contains { $0.text == "Skydiving" })
        XCTAssertTrue(m.items.allSatisfy { $0.origin == .onPhone })
        XCTAssertNotEqual(m.bio, "Loves skydiving.")
        XCTAssertTrue(m.notice?.contains("checks") ?? false)
    }

    func testLocalOnlyNeverCallsTheCloud() async {
        let stub = StubCloud()
        stub.draftResult = .success(goodDraft())
        let (m, _) = model(cloud: .localOnly, stub: stub)
        m.transcript = intro
        m.draftProfile()
        await waitUntilIdle(m)
        if m.current != nil { m.answer = "Mostly small robots"; m.submitAnswer() }
        await waitUntilIdle(m)
        XCTAssertTrue(stub.calls.isEmpty, "local-only must not contact the server")
        XCTAssertNil(m.notice, "local-only is a choice, not a failure")
        XCTAssertTrue(m.items.allSatisfy { $0.origin == .onPhone })
    }

    func testUndecidedNeverCallsTheCloud() async {
        let stub = StubCloud()
        let (m, _) = model(cloud: .undecided, stub: stub)
        m.transcript = intro
        m.draftProfile()
        await waitUntilIdle(m)
        XCTAssertTrue(stub.calls.isEmpty)
    }

    func testLeavingCancelsAndLateResponsesAreIgnored() async {
        let stub = StubCloud()
        stub.delay = 0.5
        stub.draftResult = .success(goodDraft())
        let (m, _) = model(stub: stub)
        m.transcript = intro
        m.draftProfile()
        try? await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertEqual(m.busy, .drafting)
        m.goBack()
        XCTAssertEqual(m.step, .name)
        try? await Task.sleep(nanoseconds: 800_000_000)
        XCTAssertTrue(m.items.isEmpty, "a late draft must not land after leaving")
        XCTAssertEqual(m.step, .name)
    }

    func testAnswersSurviveBackAndForth() async {
        let stub = StubCloud()
        stub.draftResult = .success(goodDraft())
        let (m, _) = model(stub: stub)
        m.transcript = intro
        m.draftProfile()
        await waitUntilIdle(m)
        m.answer = "half-typed"
        m.goBack()
        XCTAssertEqual(m.step, .intro)
        XCTAssertEqual(m.transcript, intro)
        m.draftProfile()                     // unchanged text → no new request
        XCTAssertEqual(stub.calls.filter { $0 == "draft" }.count, 1)
        XCTAssertEqual(m.step, .questions)
        XCTAssertEqual(m.answer, "half-typed")
    }

    func testBackFromCardNeverLandsOnAnEmptyQuestionStep() async {
        let stub = StubCloud()
        stub.draftResult = .success(goodDraft())
        stub.followupResult = .success(.init(facts: [], question: nil, generator: StubCloud.grok))
        let (m, _) = model(stub: stub)
        m.transcript = intro
        m.draftProfile()
        await waitUntilIdle(m)
        m.skipQuestion()
        await waitUntilIdle(m)
        XCTAssertEqual(m.step, .card)
        m.goBack()
        XCTAssertEqual(m.step, .intro, "no question is waiting, so back goes to the intro")
        m.draftProfile()                      // unchanged → straight back to the card
        XCTAssertEqual(m.step, .card)
    }

    func testAfterAGrokFailureTheSameTextRetriesGrok() async {
        let stub = StubCloud()
        stub.draftResult = .failure(.offline)
        let (m, _) = model(stub: stub)
        m.transcript = intro
        m.draftProfile()
        await waitUntilIdle(m)
        stub.draftResult = .success(goodDraft())
        m.goBack(); m.goBack()                    // back to the intro
        m.step = .intro
        m.draftProfile()
        await waitUntilIdle(m)
        XCTAssertEqual(stub.calls.filter { $0 == "draft" }.count, 2)
        XCTAssertTrue(m.items.contains { $0.origin == .grok })
    }

    func testAtMostThreeQuestions() async {
        let stub = StubCloud()
        stub.draftResult = .success(goodDraft())
        stub.followupResult = .success(.init(facts: [], question: nil, generator: StubCloud.grok))
        let (m, _) = model(stub: stub)
        m.transcript = intro
        m.draftProfile()
        await waitUntilIdle(m)
        for i in 0..<3 {
            stub.followupResult = .success(.init(facts: [], question: "Question number \(i + 2)?", generator: StubCloud.grok))
            m.skipQuestion()
            await waitUntilIdle(m)
        }
        XCTAssertEqual(m.answered.count, 3)
        XCTAssertEqual(m.step, .card)
        XCTAssertNil(m.current)
    }
}

// MARK: - Privacy & compatibility

final class ProfileCompatibilityTests: XCTestCase {

    func testProfileSavedByThePreviousVersionStillLoads() throws {
        let old = #"{"displayName":"Ada","bio":"hi","interests":[{"id":"chess","label":"Chess","parent":"games","specificity":2,"custom":false}]}"#
        let profile = try JSONDecoder().decode(Profile.self, from: Data(old.utf8))
        XCTAssertEqual(profile.displayName, "Ada")
        XCTAssertEqual(profile.interests.map(\.id), ["chess"])
        XCTAssertTrue(profile.details.isEmpty)
        XCTAssertTrue(profile.isComplete)
    }

    func testConnectionSavedByThePreviousVersionStillLoads() throws {
        let old = #"[{"id":"6F9619FF-8B86-D011-B42D-00C04FC964FF","partnerName":"Bo","partnerBio":"","metOn":700000000,"roomName":"r","insight":{"highlights":[],"opener":"Hi?","openerSource":"fallbackTemplate"},"pairingEvidence":"motionOnly"}]"#
        let list = try JSONDecoder().decode([SavedConnection].self, from: Data(old.utf8))
        XCTAssertEqual(list.first?.partnerName, "Bo")
        XCTAssertEqual(list.first?.insight.talkingPoints, [])
    }

    func testSettingsSavedByThePreviousVersionStillLoad() throws {
        let old = #"{"motionThreshold":20,"motionCooldown":1.5,"pairingWindow":0.5,"ambiguityMargin":0.05,"pairingBuffer":0.25,"uwbProximity":0.15,"uwbFreshness":1.5,"detectionMode":"combined"}"#
        let settings = try JSONDecoder().decode(Store.Settings.self, from: Data(old.utf8))
        XCTAssertNil(settings.apiBaseURL)
    }

    func testRichProfileRoundTrips() throws {
        let profile = Profile(displayName: "Ada", bio: "b", interests: [InterestCatalog.byID["chess"]!],
                              details: [ProfileFact(kind: .goal, text: "Find a club", evidence: "I want to find a club")],
                              interestEvidence: ["chess": "I play chess"])
        let decoded = try JSONDecoder().decode(Profile.self, from: JSONEncoder().encode(profile))
        XCTAssertEqual(decoded, profile)
    }

    @MainActor
    func testResetOnboardingClearsProfileAndCloudChoiceButKeepsConnections() {
        let store = Store(inMemory: true)
        store.profile = Profile(displayName: "Ada", bio: "", interests: [InterestCatalog.byID["chess"]!])
        store.privacy.cloud = .allowed
        store.settings.apiBaseURL = "http://192.168.1.2:8787"
        store.save(SavedConnection(partnerName: "Bo", partnerBio: "", metOn: Date(), roomName: "r",
                                   insight: ConnectionInsight(highlights: [], opener: "Hi?", openerSource: .fallbackTemplate),
                                   pairingEvidence: .motionOnly))
        store.resetOnboarding()
        XCTAssertFalse(store.profile.isComplete)
        XCTAssertEqual(store.privacy.cloud, .undecided)
        XCTAssertEqual(store.connections.count, 1)
        XCTAssertEqual(store.settings.apiBaseURL, "http://192.168.1.2:8787")
        XCTAssertEqual(store.onboardingResets, 1)
    }

    func testSharedCardCarriesNoEvidenceTranscriptOrPreferences() throws {
        let profile = Profile(displayName: "Ada", bio: "b", interests: [InterestCatalog.byID["chess"]!],
                              details: [ProfileFact(kind: .goal, text: "Find a club", evidence: "PRIVATE-QUOTE-1")],
                              interestEvidence: ["chess": "PRIVATE-QUOTE-2"])
        let json = String(data: try JSONEncoder().encode(profile.shareable), encoding: .utf8)!
        XCTAssertFalse(json.contains("PRIVATE-QUOTE"))
        XCTAssertFalse(json.contains("evidence"))
        XCTAssertFalse(json.contains("cloud"))
        XCTAssertTrue(json.contains("Find a club"), "approved details do reach the partner")
    }

    func testPhotoIsShrunkAndSharedOnlyAsPartOfTheCard() throws {
        // A big, noisy photo: must come out small enough for one wire frame.
        let size = CGSize(width: 2400, height: 1600)
        let big = UIGraphicsImageRenderer(size: size).image { ctx in
            for i in 0..<400 {
                UIColor(hue: CGFloat(i % 37) / 37, saturation: 0.8, brightness: 0.9, alpha: 1).setFill()
                ctx.fill(CGRect(x: CGFloat((i * 97) % 2400), y: CGFloat((i * 53) % 1600), width: 90, height: 70))
            }
        }.jpegData(compressionQuality: 1)!
        let small = try XCTUnwrap(ProfilePhoto.prepare(big))
        XCTAssertLessThanOrEqual(small.count, ProfilePhoto.maxBytes)
        let image = try XCTUnwrap(UIImage(data: small))
        XCTAssertEqual(image.size.width, image.size.height, "square")

        let profile = Profile(displayName: "Ada", interests: [InterestCatalog.byID["chess"]!], photo: small)
        XCTAssertEqual(profile.shareable.photo, small)
        let frame = try Wire.encode(.profile(proposalID: "p", profile: profile.shareable, caps: .none))
        XCTAssertLessThanOrEqual(frame.count, Wire.maxFrame, "fits one bounded frame")
        let decoded = try JSONDecoder().decode(Profile.self, from: JSONEncoder().encode(profile))
        XCTAssertEqual(decoded.photo, small)
    }

    func testBadIncomingPhotosAreDropped() {
        XCTAssertNil(ProfilePhoto.sanitized(Data(repeating: 1, count: 100)), "not an image")
        XCTAssertNil(ProfilePhoto.sanitized(Data(repeating: 1, count: ProfilePhoto.maxIncomingBytes + 1)), "too big")
        XCTAssertNil(ProfilePhoto.prepare(Data("nope".utf8)))
    }

    func testProfileMessageRoundTripsWithCapsOnly() throws {
        let caps = Wire.PartnerCaps(cloudConsent: true, grokReady: false)
        let data = try Wire.encode(.profile(proposalID: "p", profile: SharedProfile(displayName: "A", bio: "", interests: []), caps: caps))
        guard case .profile(_, _, let decoded) = try Wire.decode(data).body else { return XCTFail() }
        XCTAssertEqual(decoded, caps)
        XCTAssertEqual(Wire.version, 2)
    }
}
