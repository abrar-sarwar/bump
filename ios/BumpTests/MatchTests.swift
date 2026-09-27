import XCTest
@testable import UWBBumpTest

// MARK: - Fixtures

private enum Fixture {

    static func profile(goals: [String] = [], experiences: [String] = [],
                        interests: [String] = ["jazz"]) -> SharedProfile {
        SharedProfile(displayName: "Partner",
                      bio: "",
                      interests: interests.compactMap { InterestCatalog.byID[$0] },
                      details: goals.enumerated().map {
                          SharedFact(id: "g\($0.offset)", kind: .goal, text: $0.element)
                      } + experiences.enumerated().map {
                          SharedFact(id: "e\($0.offset)", kind: .experience, text: $0.element)
                      })
    }

    static func connection(id: UUID = UUID(),
                           partnerProfile: SharedProfile? = profile()) -> SavedConnection {
        SavedConnection(id: id,
                        partnerName: "Partner",
                        partnerBio: "",
                        metOn: Date(),
                        roomName: "room",
                        insight: ConnectionInsight(highlights: [],
                                                   opener: "What got you into it?",
                                                   openerSource: .fallbackTemplate),
                        pairingEvidence: .motionAndUWB,
                        partnerProfile: partnerProfile)
    }

    static func rating(_ id: UUID, _ wantsToConnect: Bool?) -> InteractionRating {
        InteractionRating(id: id, landedInterestIDs: [], wantsToConnect: wantsToConnect)
    }
}

// MARK: - MatchEvaluator

final class MatchEvaluatorTests: XCTestCase {

    private let evaluator = MatchEvaluator()
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    /// The whole truth table: three states on each side, one match.
    func testOnlyAnExplicitYesOnBothSidesMatches() {
        let mine: [Bool?] = [true, false, nil]
        let theirs: [PartnerLike] = [.wantsToConnect, .passed, .unknown]
        for me in mine {
            for them in theirs {
                let id = UUID()
                let match = evaluator.evaluate(rating: Fixture.rating(id, me),
                                               partnerLike: them,
                                               existing: nil,
                                               now: now)
                let shouldMatch = (me == true && them == .wantsToConnect)
                XCTAssertEqual(match != nil, shouldMatch,
                               "mine=\(String(describing: me)) theirs=\(them)")
                if shouldMatch {
                    XCTAssertEqual(match?.id, id)
                    XCTAssertEqual(match?.matchedOn, now)
                }
            }
        }
    }

    /// Never asked at all is not a yes, however keen the other person is.
    func testNoRatingNeverMatches() {
        XCTAssertNil(evaluator.evaluate(rating: nil, partnerLike: .wantsToConnect,
                                       existing: nil, now: now))
    }

    /// A match that already exists is not reported again, so re-rating a matched
    /// connection cannot celebrate or notify twice.
    func testExistingMatchIsNotReportedAgain() {
        let id = UUID()
        let existing = MutualMatch(id: id, matchedOn: now.addingTimeInterval(-99))
        XCTAssertNil(evaluator.evaluate(rating: Fixture.rating(id, true),
                                       partnerLike: .wantsToConnect,
                                       existing: existing,
                                       now: now))
    }

    /// A no given first, then changed to a yes, still matches.
    func testAnswerCanBeChangedFromNoToYesAndStillMatch() {
        let id = UUID()
        XCTAssertNil(evaluator.evaluate(rating: Fixture.rating(id, false),
                                       partnerLike: .wantsToConnect,
                                       existing: nil, now: now))
        XCTAssertNotNil(evaluator.evaluate(rating: Fixture.rating(id, true),
                                          partnerLike: .wantsToConnect,
                                          existing: nil, now: now))
    }
}

// MARK: - Resolvers

final class MutualLikeResolverTests: XCTestCase {

    /// The stand-in must be stable: a profile that unlocked must not appear to
    /// lock itself again on the next launch.
    func testLocalResolverIsStableForTheSameConnection() {
        let connection = Fixture.connection()
        let resolver = LocalMutualLikeResolver()
        let first = resolver.partnerLike(for: connection)
        for _ in 0..<20 {
            XCTAssertEqual(resolver.partnerLike(for: connection), first)
        }
    }

    /// And it must never invent an `.unknown`, which would silently mean "no".
    func testLocalResolverAlwaysGivesAnAnswer() {
        let resolver = LocalMutualLikeResolver()
        for _ in 0..<200 {
            let like = resolver.partnerLike(for: Fixture.connection())
            XCTAssertTrue(like == .wantsToConnect || like == .passed)
        }
    }

    func testFixedResolverAnswersForTheNamedConnectionsOnly() {
        let yes = Fixture.connection()
        let no = Fixture.connection()
        let resolver = FixedMutualLikeResolver(yes: [yes.id])
        XCTAssertEqual(resolver.partnerLike(for: yes), .wantsToConnect)
        XCTAssertEqual(resolver.partnerLike(for: no), .passed)
    }
}

// MARK: - Store

@MainActor
final class MatchStoreTests: XCTestCase {

    func testRecordingAMatchUnlocksTheConnection() {
        let store = Store(inMemory: true)
        let connection = Fixture.connection()
        store.save(connection)
        XCTAssertFalse(store.isMatched(connection.id))

        store.recordMatch(MutualMatch(id: connection.id))
        XCTAssertTrue(store.isMatched(connection.id))
        XCTAssertNotNil(store.match(for: connection.id))
    }

    /// The first match wins: a later call cannot move the date of a moment that
    /// already happened.
    func testRecordingTwiceKeepsTheFirstDate() {
        let store = Store(inMemory: true)
        let id = UUID()
        let first = Date(timeIntervalSince1970: 1_000)
        store.recordMatch(MutualMatch(id: id, matchedOn: first))
        store.recordMatch(MutualMatch(id: id, matchedOn: Date()))
        XCTAssertEqual(store.match(for: id)?.matchedOn, first)
    }

    /// Flipping your own answer to a no does NOT revoke a profile the other
    /// person has already been shown.
    func testMatchSurvivesTheUserChangingTheirAnswer() {
        let store = Store(inMemory: true)
        let connection = Fixture.connection()
        store.save(connection)
        store.saveRating(Fixture.rating(connection.id, true))
        store.recordMatch(MutualMatch(id: connection.id))

        store.saveRating(Fixture.rating(connection.id, false))
        XCTAssertTrue(store.isMatched(connection.id))
    }

    func testDeletingAConnectionForgetsItsMatch() {
        let store = Store(inMemory: true)
        let connection = Fixture.connection()
        store.save(connection)
        store.recordMatch(MutualMatch(id: connection.id))

        store.delete(connection)
        XCTAssertFalse(store.isMatched(connection.id))
    }

    func testDeletingByOffsetForgetsItsMatch() {
        let store = Store(inMemory: true)
        let keep = Fixture.connection()
        let doomed = Fixture.connection()
        store.save(keep)
        store.save(doomed)   // inserted at 0
        store.recordMatch(MutualMatch(id: doomed.id))
        store.recordMatch(MutualMatch(id: keep.id))

        store.deleteConnections(at: IndexSet(integer: 0))
        XCTAssertFalse(store.isMatched(doomed.id))
        XCTAssertTrue(store.isMatched(keep.id))
    }
}

// MARK: - On-disk form

final class MutualMatchCodingTests: XCTestCase {

    func testRoundTripsThroughTheFlatOnDiskArray() throws {
        let a = MutualMatch(id: UUID(), matchedOn: Date(timeIntervalSince1970: 100))
        let b = MutualMatch(id: UUID(), matchedOn: Date(timeIntervalSince1970: 200))
        let index = [a.id: a, b.id: b]

        let data = try JSONEncoder().encode(MutualMatch.persistable(index))
        let decoded = try JSONDecoder().decode([MutualMatch].self, from: data)

        XCTAssertEqual(decoded.map(\.id), [b.id, a.id], "newest first on disk")
        XCTAssertEqual(MutualMatch.index(decoded), index)
    }

    /// A duplicated entry resolves to the EARLIEST: the moment it first happened.
    func testDuplicateEntriesResolveToTheEarliest() {
        let id = UUID()
        let early = MutualMatch(id: id, matchedOn: Date(timeIntervalSince1970: 100))
        let late = MutualMatch(id: id, matchedOn: Date(timeIntervalSince1970: 900))
        XCTAssertEqual(MutualMatch.index([late, early])[id], early)
        XCTAssertEqual(MutualMatch.index([early, late])[id], early)
    }
}

// MARK: - The thumb on a rating

final class RatingThumbTests: XCTestCase {

    /// A `ratings.json` written before the thumb existed must still load, with
    /// every answer reading as unanswered rather than as a no.
    func testRatingWithoutTheThumbDecodesAsUnanswered() throws {
        let json = """
        [{"id":"\(UUID().uuidString)","ratedOn":0,"landedInterestIDs":["jazz"]}]
        """
        let decoded = try JSONDecoder().decode([InteractionRating].self,
                                               from: Data(json.utf8))
        XCTAssertEqual(decoded.count, 1)
        XCTAssertNil(decoded[0].wantsToConnect)
        XCTAssertEqual(decoded[0].landedInterestIDs, ["jazz"])
    }

    func testEachThumbValueRoundTrips() throws {
        for value: Bool? in [true, false, nil] {
            let rating = Fixture.rating(UUID(), value)
            let data = try JSONEncoder().encode(rating)
            let decoded = try JSONDecoder().decode(InteractionRating.self, from: data)
            XCTAssertEqual(decoded.wantsToConnect, value)
            XCTAssertEqual(decoded, rating)
        }
    }

    /// Unanswered is not a no. If these compared equal, skipping the question
    /// would be indistinguishable from declining it.
    func testUnansweredIsNotTheSameAsNo() {
        let id = UUID()
        XCTAssertNotEqual(Fixture.rating(id, nil), Fixture.rating(id, false))
    }
}

// MARK: - What the unlock reveals

final class UnlockedProfileTests: XCTestCase {

    /// A `connections.json` written before partner cards were kept must still
    /// load; those connections simply have nothing to unlock.
    func testConnectionWithoutAPartnerProfileDecodes() throws {
        let stored = Fixture.connection(partnerProfile: nil)
        let data = try JSONEncoder().encode([stored])
        let decoded = try JSONDecoder().decode([SavedConnection].self, from: data)
        XCTAssertNil(decoded.first?.partnerProfile)
    }

    func testPartnerProfileSurvivesARoundTrip() throws {
        let stored = Fixture.connection(partnerProfile: Fixture.profile(goals: ["Bake bread"]))
        let data = try JSONEncoder().encode([stored])
        let decoded = try JSONDecoder().decode([SavedConnection].self, from: data)
        XCTAssertEqual(decoded.first?.partnerProfile, stored.partnerProfile)
    }

    /// The three unlocked headings partition the card the same way the owner's own
    /// profile does, and interests stay out of `details`.
    func testExperiencesAndGoalsPartitionTheDetails() {
        let profile = Fixture.profile(goals: ["Bake bread", "Open mic"],
                                     experiences: ["Toured for two summers"])
        XCTAssertEqual(profile.goals.map(\.text), ["Bake bread", "Open mic"])
        XCTAssertEqual(profile.experiences.map(\.text), ["Toured for two summers"])
        XCTAssertEqual(profile.goals.count + profile.experiences.count, profile.details.count)
    }
}
