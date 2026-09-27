import XCTest
@testable import UWBBumpTest

// MARK: - Fixtures

private enum Fixture {

    static func highlight(_ id: String, specificity: Int = 2) -> SharedHighlight {
        SharedHighlight(interestID: id,
                        statement: "You're both into \(id).",
                        yourEntry: id.capitalized,
                        theirEntry: id.capitalized,
                        specificity: specificity)
    }

    static func insight(_ ids: [String]) -> ConnectionInsight {
        ConnectionInsight(highlights: ids.map { highlight($0) },
                          opener: "What got you into it?",
                          openerSource: .fallbackTemplate)
    }

    /// `metOn` is expressed as seconds BEFORE `reference`, so age is explicit.
    static func connection(id: UUID = UUID(),
                           secondsAgo: TimeInterval,
                           reference: Date = Date(),
                           interests: [String] = ["jazz"]) -> SavedConnection {
        SavedConnection(id: id,
                        partnerName: "Partner",
                        partnerBio: "",
                        metOn: reference.addingTimeInterval(-secondsAgo),
                        roomName: "room",
                        insight: insight(interests),
                        pairingEvidence: .motionAndUWB)
    }

    static func ratings(_ pairs: [(UUID, [String])]) -> [UUID: InteractionRating] {
        Dictionary(uniqueKeysWithValues: pairs.map {
            ($0.0, InteractionRating(id: $0.0, landedInterestIDs: $0.1))
        })
    }
}

// MARK: - RatingPrompter

final class RatingPrompterTests: XCTestCase {

    private let now = Date(timeIntervalSince1970: 1_000_000)

    private func prompter(dwell: TimeInterval = 120,
                         stale: TimeInterval = 86_400) -> RatingPrompter {
        RatingPrompter(minimumDwell: dwell, staleAfter: stale)
    }

    func testPromptsForAnUnratedConnectionPastTheDwellFloor() {
        let c = Fixture.connection(secondsAgo: 300, reference: now)
        let p = prompter()
        XCTAssertEqual(p.next(connections: [c], ratings: [:], now: now)?.id, c.id)
    }

    func testStaysSilentWhileTheConversationIsProbablyStillHappening() {
        let c = Fixture.connection(secondsAgo: 30, reference: now)
        let p = prompter()
        XCTAssertNil(p.next(connections: [c], ratings: [:], now: now),
                     "30s after the bump they are still standing there")
    }

    func testStopsAskingOnceTheMemoryIsStale() {
        let c = Fixture.connection(secondsAgo: 86_401, reference: now)
        let p = prompter()
        XCTAssertNil(p.next(connections: [c], ratings: [:], now: now),
                     "past staleAfter it is no longer worth asking unprompted")
    }

    func testNeverRePromptsAnAlreadyRatedConnection() {
        let c = Fixture.connection(secondsAgo: 300, reference: now)
        let p = prompter()
        XCTAssertNil(p.next(connections: [c], ratings: Fixture.ratings([(c.id, ["jazz"])]), now: now))
    }

    func testAnEmptyAnswerStillCountsAsRated() {
        let c = Fixture.connection(secondsAgo: 300, reference: now)
        let p = prompter()
        XCTAssertNil(p.next(connections: [c], ratings: Fixture.ratings([(c.id, [])]), now: now),
                     "'nothing landed' is an answer, not an absence of one")
    }

    func testSkipsConnectionsWithNothingToAskAbout() {
        var c = Fixture.connection(secondsAgo: 300, reference: now)
        c.insight = Fixture.insight([])
        let p = prompter()
        XCTAssertNil(p.next(connections: [c], ratings: [:], now: now),
                     "a question with no possible answers must never be asked")
    }

    func testPicksTheOldestEligibleConnectionBecauseItIsClosestToGoingStale() {
        let recent = Fixture.connection(secondsAgo: 200, reference: now)
        let older = Fixture.connection(secondsAgo: 5_000, reference: now)
        let p = prompter()
        XCTAssertEqual(p.next(connections: [recent, older], ratings: [:], now: now)?.id, older.id)
    }

    func testDismissSilencesThatConnectionForTheRestOfTheSession() {
        let c = Fixture.connection(secondsAgo: 300, reference: now)
        var p = prompter()
        XCTAssertNotNil(p.next(connections: [c], ratings: [:], now: now))
        p.dismiss(c.id)
        XCTAssertNil(p.next(connections: [c], ratings: [:], now: now),
                     "'Not now' must not reappear on the next foreground")
    }

    func testDismissingOneConnectionDoesNotSilenceAnother() {
        let a = Fixture.connection(secondsAgo: 5_000, reference: now)
        let b = Fixture.connection(secondsAgo: 300, reference: now)
        var p = prompter()
        p.dismiss(a.id)
        XCTAssertEqual(p.next(connections: [a, b], ratings: [:], now: now)?.id, b.id)
    }
}

// MARK: - InterestTrends

final class InterestTrendsTests: XCTestCase {

    private let now = Date(timeIntervalSince1970: 1_000_000)

    func testEmptyHistoryProducesAnEmptySparseSummary() {
        let s = InterestTrends.summarize(connections: [], ratings: [:])
        XCTAssertEqual(s.totalConnections, 0)
        XCTAssertEqual(s.ratedConnections, 0)
        XCTAssertTrue(s.stats.isEmpty)
        XCTAssertTrue(s.isTooSparse)
    }

    func testCountsSurfacedEvenWhenNothingHasBeenRated() {
        let a = Fixture.connection(secondsAgo: 100, reference: now, interests: ["jazz"])
        let b = Fixture.connection(secondsAgo: 200, reference: now, interests: ["jazz", "baking"])
        let s = InterestTrends.summarize(connections: [a, b], ratings: [:])

        XCTAssertEqual(s.stats.first { $0.id == "jazz" }?.surfaced, 2)
        XCTAssertEqual(s.stats.first { $0.id == "jazz" }?.rated, 0)
        XCTAssertEqual(s.stats.first { $0.id == "jazz" }?.landed, 0)
        XCTAssertTrue(s.isTooSparse, "no answers at all cannot be a trend")
    }

    func testLandedIsCountedAgainstRatedNotAgainstSurfaced() {
        let rated = Fixture.connection(secondsAgo: 100, reference: now, interests: ["jazz"])
        let unrated = Fixture.connection(secondsAgo: 200, reference: now, interests: ["jazz"])
        let s = InterestTrends.summarize(connections: [rated, unrated],
                                        ratings: Fixture.ratings([(rated.id, ["jazz"])]))
        let jazz = s.stats.first { $0.id == "jazz" }
        XCTAssertEqual(jazz?.surfaced, 2)
        XCTAssertEqual(jazz?.rated, 1, "only one of the two was answered for")
        XCTAssertEqual(jazz?.landed, 1)
    }

    func testAnEmptyAnswerCountsAsRatedButNotLanded() {
        let c = Fixture.connection(secondsAgo: 100, reference: now, interests: ["jazz"])
        let s = InterestTrends.summarize(connections: [c], ratings: Fixture.ratings([(c.id, [])]))
        let jazz = s.stats.first { $0.id == "jazz" }
        XCTAssertEqual(jazz?.rated, 1)
        XCTAssertEqual(jazz?.landed, 0)
        XCTAssertEqual(s.ratedConnections, 1)
    }

    func testLandedNeverExceedsRatedAndRatedNeverExceedsSurfaced() {
        let ids = ["jazz", "baking", "photography"]
        let connections = (0..<6).map {
            Fixture.connection(secondsAgo: TimeInterval(100 * ($0 + 1)), reference: now, interests: ids)
        }
        let ratings = Fixture.ratings(connections.map { ($0.id, ids) })
        let s = InterestTrends.summarize(connections: connections, ratings: ratings)

        for stat in s.stats {
            XCTAssertLessThanOrEqual(stat.landed, stat.rated, "\(stat.id) claims more landings than answers")
            XCTAssertLessThanOrEqual(stat.rated, stat.surfaced, "\(stat.id) claims more answers than appearances")
        }
    }

    func testSparseUntilEnoughConnectionsHaveBeenRated() {
        let connections = (0..<3).map {
            Fixture.connection(secondsAgo: TimeInterval(100 * ($0 + 1)), reference: now)
        }
        let two = Fixture.ratings(connections.prefix(2).map { ($0.id, ["jazz"]) })
        XCTAssertTrue(InterestTrends.summarize(connections: connections, ratings: two).isTooSparse)

        let three = Fixture.ratings(connections.map { ($0.id, ["jazz"]) })
        XCTAssertFalse(InterestTrends.summarize(connections: connections, ratings: three).isTooSparse)
    }

    func testRanksByLandedThenSurfacedThenIDSoTheOrderIsStable() {
        // jazz lands twice, baking once; photography only ever surfaces.
        let a = Fixture.connection(secondsAgo: 100, reference: now, interests: ["jazz", "baking", "photography"])
        let b = Fixture.connection(secondsAgo: 200, reference: now, interests: ["jazz", "photography"])
        let ratings = Fixture.ratings([(a.id, ["jazz", "baking"]), (b.id, ["jazz"])])
        let s = InterestTrends.summarize(connections: [a, b], ratings: ratings)

        XCTAssertEqual(s.stats.map(\.id), ["jazz", "baking", "photography"])
        XCTAssertEqual(InterestTrends.summarize(connections: [a, b], ratings: ratings).stats.map(\.id),
                       s.stats.map(\.id), "same input must give the same order")
    }
}

// MARK: - Store persistence

@MainActor
final class RatingStoreTests: XCTestCase {

    func testSaveRatingIsIdempotentByConnectionID() {
        let store = Store(inMemory: true)
        let c = Fixture.connection(secondsAgo: 300)
        store.save(c)

        store.saveRating(InteractionRating(id: c.id, landedInterestIDs: ["jazz"]))
        store.saveRating(InteractionRating(id: c.id, landedInterestIDs: ["baking"]))

        XCTAssertEqual(store.ratings.count, 1, "re-rating replaces, it does not accumulate")
        XCTAssertEqual(store.rating(for: c.id)?.landedInterestIDs, ["baking"])
    }

    func testLandedIDsAreStoredSortedSoEqualAnswersCompareEqual() {
        let id = UUID()
        // Pinned `ratedOn`: the two would otherwise differ by a few microseconds
        // and this test is about the id list, not the timestamp.
        let when = Date(timeIntervalSince1970: 1_000_000)
        XCTAssertEqual(InteractionRating(id: id, ratedOn: when, landedInterestIDs: ["jazz", "baking"]),
                       InteractionRating(id: id, ratedOn: when, landedInterestIDs: ["baking", "jazz"]))
    }

    func testUnratedConnectionsExcludesAnsweredOnes() {
        let store = Store(inMemory: true)
        let a = Fixture.connection(secondsAgo: 300)
        let b = Fixture.connection(secondsAgo: 400)
        store.save(a); store.save(b)
        store.saveRating(InteractionRating(id: a.id, landedInterestIDs: []))

        XCTAssertEqual(store.unratedConnections.map(\.id), [b.id])
    }

    func testDeletingAConnectionDropsItsRating() {
        let store = Store(inMemory: true)
        let c = Fixture.connection(secondsAgo: 300)
        store.save(c)
        store.saveRating(InteractionRating(id: c.id, landedInterestIDs: ["jazz"]))

        store.delete(c)
        XCTAssertTrue(store.ratings.isEmpty, "a deleted connection must not leave its rating behind")
    }

    func testDeletingByOffsetsDropsTheRatingsOfExactlyThoseRows() {
        let store = Store(inMemory: true)
        // save inserts at index 0, so the store order is c, b, a.
        let a = Fixture.connection(secondsAgo: 300)
        let b = Fixture.connection(secondsAgo: 400)
        let c = Fixture.connection(secondsAgo: 500)
        store.save(a); store.save(b); store.save(c)
        for x in [a, b, c] { store.saveRating(InteractionRating(id: x.id, landedInterestIDs: ["jazz"])) }

        store.deleteConnections(at: IndexSet(integer: 0))       // removes c

        XCTAssertEqual(store.connections.map(\.id), [b.id, a.id])
        XCTAssertNil(store.rating(for: c.id))
        XCTAssertNotNil(store.rating(for: b.id), "the surviving rows keep their answers")
        XCTAssertNotNil(store.rating(for: a.id))
    }
}
