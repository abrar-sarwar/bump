import XCTest
@testable import UWBBumpTest

// MARK: - Motion gate

final class SpikeGateTests: XCTestCase {

    func testFiresOnceOnCrossingAndNotWhileStillHigh() {
        var gate = SpikeGate(threshold: 20, rearmFactor: 0.5, cooldown: 1.5)
        XCTAssertEqual(gate.feed(magnitude: 2, now: 0), .belowThreshold)
        XCTAssertEqual(gate.feed(magnitude: 25, now: 0.1), .spike(25))
        // Sustained shaking must not retrigger.
        XCTAssertEqual(gate.feed(magnitude: 30, now: 0.2), .stillHigh)
        XCTAssertEqual(gate.feed(magnitude: 22, now: 0.3), .stillHigh)
    }

    func testRearmsOnlyBelowHysteresisFloor() {
        var gate = SpikeGate(threshold: 20, rearmFactor: 0.5, cooldown: 0)
        _ = gate.feed(magnitude: 25, now: 0)
        // 12 is below threshold but above the 10 m/s² rearm floor: still disarmed.
        XCTAssertEqual(gate.feed(magnitude: 12, now: 0.1), .belowThreshold)
        XCTAssertEqual(gate.feed(magnitude: 25, now: 0.2), .stillHigh)
        // Drop under the floor, now it can fire again.
        XCTAssertEqual(gate.feed(magnitude: 4, now: 0.3), .belowThreshold)
        XCTAssertEqual(gate.feed(magnitude: 25, now: 0.4), .spike(25))
    }

    func testCooldownSuppressesASecondSpike() {
        var gate = SpikeGate(threshold: 20, rearmFactor: 0.5, cooldown: 1.5)
        XCTAssertEqual(gate.feed(magnitude: 25, now: 0), .spike(25))
        _ = gate.feed(magnitude: 1, now: 0.5)                       // rearm
        XCTAssertEqual(gate.feed(magnitude: 25, now: 1.0), .suppressedByCooldown(25))
        _ = gate.feed(magnitude: 1, now: 1.2)                       // rearm again
        XCTAssertEqual(gate.feed(magnitude: 25, now: 1.6), .spike(25))
    }

    func testUnitsConversionIsExplicit() {
        // 1 g of user acceleration must read as 9.80665 m/s², not 1.
        XCTAssertEqual(MotionDetector.G, 9.80665, accuracy: 0.00001)
        let oneG = sqrt(1.0 * 1.0) * MotionDetector.G
        XCTAssertEqual(oneG, 9.80665, accuracy: 0.001)
    }
}

// MARK: - Pairing

final class PairingMatcherTests: XCTestCase {

    private func matcher(_ tweak: (inout PairingMatcher.Config) -> Void = { _ in }) -> PairingMatcher {
        var config = PairingMatcher.Config()
        tweak(&config)
        var m = PairingMatcher()
        m.config = config
        return m
    }

    private func event(_ participant: String, _ at: TimeInterval) -> PairingMatcher.Event {
        .init(id: "\(participant)-\(at)", participant: participant, arrival: at)
    }

    func testTwoIsolatedBumpsMatch() {
        var m = matcher()
        XCTAssertNil(m.submit(event("a", 0)))
        XCTAssertNil(m.submit(event("b", 0.100)))
        let out = m.resolve(now: 0.400)
        XCTAssertEqual(out.count, 1)
        guard case .matched(let x, let y, let gap, let uwb) = out[0] else { return XCTFail("no match") }
        XCTAssertEqual([x, y].sorted(), ["a", "b"])
        XCTAssertEqual(gap, 0.100, accuracy: 0.0001)
        XCTAssertFalse(uwb)
    }

    func testWindowBoundaryInclusiveThenTimeout() {
        var inside = matcher()
        _ = inside.submit(event("a", 0)); _ = inside.submit(event("b", 0.500))
        XCTAssertEqual(inside.resolve(now: 0.8).count, 1, "500 ms is inside a 500 ms window")

        var outside = matcher()
        _ = outside.submit(event("a", 0)); _ = outside.submit(event("b", 0.501))
        XCTAssertTrue(outside.resolve(now: 0.8).isEmpty)
        let late = outside.resolve(now: 3.2)
        XCTAssertEqual(late.count, 2)
        XCTAssertTrue(late.allSatisfy { if case .timedOut = $0 { return true }; return false })
    }

    func testClosestPairBeatsEarlyGreedyMatch() {
        var m = matcher()
        _ = m.submit(event("a", 0))
        XCTAssertTrue(m.resolve(now: 0.250).isEmpty, "a has nobody yet")
        _ = m.submit(event("b", 0.300))
        _ = m.submit(event("c", 0.310))
        let out = m.resolve(now: 0.560)
        guard case .matched(let x, let y, let gap, _) = out.first else { return XCTFail("no match") }
        XCTAssertEqual([x, y].sorted(), ["b", "c"], "the 10 ms pair must win over greedy a+b")
        XCTAssertEqual(gap, 0.010, accuracy: 0.0001)
    }

    func testThreeSimultaneousBumpsAreAmbiguousNotGuessed() {
        var m = matcher()
        _ = m.submit(event("a", 0)); _ = m.submit(event("b", 0.010)); _ = m.submit(event("c", 0.020))
        let out = m.resolve(now: 0.300)
        XCTAssertEqual(out.count, 1)
        guard case .ambiguous(let people, _) = out[0] else { return XCTFail("expected ambiguity") }
        XCTAssertEqual(people, ["a", "b", "c"])
    }

    func testTwoSeparatedPairsBothMatch() {
        var m = matcher()
        _ = m.submit(event("a", 0)); _ = m.submit(event("b", 0.010))
        _ = m.submit(event("c", 0.250)); _ = m.submit(event("d", 0.260))
        let out = m.resolve(now: 0.520)
        XCTAssertEqual(out.count, 2)
        let pairs = out.compactMap { outcome -> String? in
            if case .matched(let x, let y, _, _) = outcome { return [x, y].sorted().joined() }
            return nil
        }.sorted()
        XCTAssertEqual(pairs, ["ab", "cd"])
    }

    func testFourSimultaneousBumpsAreAllAmbiguous() {
        var m = matcher()
        for (i, p) in ["a", "b", "c", "d"].enumerated() { _ = m.submit(event(p, Double(i) * 0.005)) }
        let out = m.resolve(now: 0.300)
        guard case .ambiguous(let people, _) = out.first else { return XCTFail("expected ambiguity") }
        XCTAssertEqual(people, ["a", "b", "c", "d"])
    }

    func testBucketBoundaryDoesNotSplitARealPair() {
        // 490 / 510 ms would fall in different 500 ms buckets; rolling windows match.
        var m = matcher()
        _ = m.submit(event("a", 0.490)); _ = m.submit(event("b", 0.510))
        XCTAssertEqual(m.resolve(now: 0.800).count, 1)
    }

    func testNoSelfPairingAndDuplicatesRejected() {
        var m = matcher()
        XCTAssertNil(m.submit(event("a", 0)))
        // While a's bump is still pending, any second bump from a is a duplicate.
        XCTAssertEqual(m.submit(event("a", 0.050)), .duplicatePending)
        XCTAssertEqual(m.submit(event("a", 2.000)), .duplicatePending)
        XCTAssertTrue(m.resolve(now: 0.400).isEmpty, "a phone can never match itself")
    }

    func testCooldownAppliesOnceTheEarlierBumpHasCleared() {
        var m = matcher()
        XCTAssertNil(m.submit(event("a", 0)))
        _ = m.resolve(now: 2.6)                       // a times out and leaves pending
        XCTAssertTrue(m.pending.isEmpty)
        // Nothing pending now, so the per-participant rate limit is what bites.
        XCTAssertEqual(m.submit(event("a", 2.7)), nil, "2.7 s is well past the 1 s cooldown")
        _ = m.resolve(now: 5.3)
        XCTAssertEqual(m.submit(event("a", 5.4)), nil)
        XCTAssertEqual(m.submit(event("b", 5.45)), nil)
        // b bumping twice in quick succession after its first clears:
        _ = m.resolve(now: 8.0)
        XCTAssertEqual(m.submit(event("b", 8.1)), nil)
        _ = m.resolve(now: 10.7)
        XCTAssertEqual(m.submit(event("b", 8.6)), .cooldown, "inside the 1 s window since b's last")
    }

    func testIdenticalEventIDIsIdempotent() {
        var m = matcher()
        let e = event("a", 0)
        XCTAssertNil(m.submit(e))
        XCTAssertEqual(m.submit(e), .duplicatePending, "re-delivery must change nothing")
        XCTAssertEqual(m.pending.count, 1)
    }

    func testLockedParticipantCannotEnterASecondProposal() {
        var m = matcher()
        m.lock(["a"])
        XCTAssertEqual(m.submit(event("a", 0)), .locked)
        m.unlock(["a"])
        XCTAssertNil(m.submit(event("a", 1.5)))
    }

    func testDisconnectClearsPendingAndProximity() {
        var m = matcher()
        _ = m.submit(event("a", 0)); _ = m.submit(event("b", 0.100))
        m.remove(participant: "a")
        XCTAssertEqual(m.pending.count, 1)
        XCTAssertTrue(m.resolve(now: 0.400).isEmpty, "b has nobody left to match")
    }

    func testTimeoutFiresOnceOnly() {
        var m = matcher()
        _ = m.submit(event("a", 0))
        XCTAssertTrue(m.resolve(now: 2.0).isEmpty)
        XCTAssertEqual(m.resolve(now: 2.5).count, 1)
        XCTAssertTrue(m.resolve(now: 5.0).isEmpty, "not re-emitted")
    }

    // MARK: UWB evidence

    func testFreshProximityPromotesAPairOverACloserArrival() {
        var m = matcher()
        // b/c are closer in arrival, but a/b have physical UWB evidence.
        _ = m.submit(event("a", 0)); _ = m.submit(event("b", 0.200)); _ = m.submit(event("c", 0.205))
        m.record(.init(observer: "a", peer: "b", distance: 0.08, at: 0.150))
        let out = m.resolve(now: 0.460)
        guard case .matched(let x, let y, _, let uwb) = out.first else { return XCTFail("no match") }
        XCTAssertEqual([x, y].sorted(), ["a", "b"])
        XCTAssertTrue(uwb)
    }

    func testStaleProximityIsNotEvidence() {
        var m = matcher { $0.uwbFreshness = 1.0 }
        XCTAssertFalse(m.hasFreshProximity("a", "b", now: 5.0))
        m.record(.init(observer: "a", peer: "b", distance: 0.05, at: 1.0))
        XCTAssertTrue(m.hasFreshProximity("a", "b", now: 1.5))
        XCTAssertFalse(m.hasFreshProximity("a", "b", now: 3.0), "an old measurement says nothing about now")
    }

    func testProximityIsAttributedToTheRightPairOnly() {
        var m = matcher()
        m.record(.init(observer: "a", peer: "b", distance: 0.05, at: 1.0))
        XCTAssertTrue(m.hasFreshProximity("b", "a", now: 1.2), "symmetric")
        XCTAssertFalse(m.hasFreshProximity("a", "c", now: 1.2), "must not leak to another peer")
    }

    func testFarProximityIsNotContactEvidence() {
        var m = matcher { $0.uwbProximity = 0.15 }
        m.record(.init(observer: "a", peer: "b", distance: 0.90, at: 1.0))
        XCTAssertFalse(m.hasFreshProximity("a", "b", now: 1.1))
    }
}

// MARK: - Interests

final class InterestMatcherTests: XCTestCase {

    private func profile(_ labels: [String]) -> SharedProfile {
        SharedProfile(displayName: "T", bio: "",
                      interests: labels.compactMap { InterestCatalog.canonical(from: $0) })
    }

    func testNormalizationFoldsCaseWhitespaceAndPunctuation() {
        XCTAssertEqual(InterestCatalog.normalize("  Jazz   Piano!! "), "jazz piano")
        XCTAssertEqual(InterestCatalog.canonical(from: "HIP-HOP")?.id, "hip-hop")
        XCTAssertEqual(InterestCatalog.canonical(from: "hip hop")?.id, "hip-hop", "synonym")
        XCTAssertEqual(InterestCatalog.canonical(from: "jazz")?.id, "jazz", "broad stays broad")
        XCTAssertEqual(InterestCatalog.canonical(from: "  ")?.id, nil)
    }

    func testSpecificOverlapPreferredAndBroadParentSuppressed() {
        let a = profile(["Music", "Jazz", "Photography"])
        let b = profile(["Music", "Jazz"])
        let out = InterestMatcher.overlap(a, b)
        XCTAssertEqual(out.map(\.interestID), ["jazz"],
                       "the broad 'music' category is suppressed because a child matched")
        XCTAssertEqual(out[0].specificity, 2)
    }

    func testBroadOverlapStillReportedWhenNoSpecificChildMatches() {
        let a = profile(["Music", "Jazz piano"])
        let b = profile(["Music", "Vinyl"])
        let out = InterestMatcher.overlap(a, b)
        XCTAssertEqual(out.map(\.interestID), ["music"])
        XCTAssertTrue(out[0].statement.contains("music"))
    }

    func testNothingIsInventedWhenThereIsNoOverlap() {
        let out = InterestMatcher.overlap(profile(["Jazz piano"]), profile(["Bouldering"]))
        XCTAssertTrue(out.isEmpty, "no overlap must produce no claims at all")
    }

    func testSynonymsCanonicaliseSoEvidenceMatchesBothProfiles() {
        // A typed synonym becomes the catalogue interest, so both sides' evidence
        // is the canonical entry that is genuinely in each profile.
        let a = profile(["hip hop"])         // synonym
        let b = profile(["Hip-hop"])         // canonical label
        let out = InterestMatcher.overlap(a, b)
        XCTAssertEqual(out.count, 1)
        XCTAssertEqual(out[0].yourEntry, "Hip-hop")
        XCTAssertEqual(out[0].theirEntry, "Hip-hop")
    }

    func testEvidenceKeepsTheUsersOwnWordingForCustomInterests() {
        // Nothing in the catalogue matches, so the user's exact text is the
        // evidence on both sides — never rewritten, never invented.
        let a = profile(["competitive duck herding"])
        let b = profile(["Competitive Duck Herding"])
        let out = InterestMatcher.overlap(a, b)
        XCTAssertEqual(out.count, 1)
        XCTAssertEqual(out[0].yourEntry, "competitive duck herding")
        XCTAssertEqual(out[0].theirEntry, "Competitive Duck Herding")
    }

    func testCustomInterestsMatchEachOtherButNotStrangers() {
        let a = profile(["competitive duck herding"])
        let b = profile(["Competitive Duck Herding"])
        XCTAssertEqual(InterestMatcher.overlap(a, b).count, 1)
        XCTAssertTrue(InterestMatcher.overlap(a, profile(["duck"])).isEmpty)
    }

    func testResultIsDeterministicAndCappedAtThree() {
        let labels = ["Jazz", "Photography", "Climbing", "Baking", "Chess"]
        let a = profile(labels), b = profile(labels)
        let first = InterestMatcher.overlap(a, b)
        let second = InterestMatcher.overlap(a, b)
        XCTAssertEqual(first.count, 3)
        XCTAssertEqual(first.map(\.interestID), second.map(\.interestID),
                       "both phones must compute the same order")
    }

    func testInterestArrayOverlapMatchesSharedProfileOverlap() {
        let mine = ["Jazz", "Photography"].compactMap { InterestCatalog.canonical(from: $0) }
        let theirs = ["Jazz", "Climbing"].compactMap { InterestCatalog.canonical(from: $0) }
        let out = InterestMatcher.overlap(mine, theirs, limit: 1)
        XCTAssertEqual(out.map(\.interestID), ["jazz"])
    }

    func testInterestArrayOverlapNeverExceedsLimit() {
        let labels = ["Jazz", "Photography", "Climbing", "Baking", "Chess"]
        let mine = labels.compactMap { InterestCatalog.canonical(from: $0) }
        XCTAssertEqual(InterestMatcher.overlap(mine, mine, limit: 1).count, 1)
    }

    func testInterestArrayOverlapEmptyWhenNoOverlap() {
        let mine = [InterestCatalog.canonical(from: "Jazz piano")!]
        let theirs = [InterestCatalog.canonical(from: "Bouldering")!]
        XCTAssertTrue(InterestMatcher.overlap(mine, theirs, limit: 1).isEmpty)
    }
}

// MARK: - Conversation

final class ConversationServiceTests: XCTestCase {

    func testFallbackUsesTheRealOverlap() {
        let mine = SharedProfile(displayName: "A", bio: "", interests: [InterestCatalog.byID["climbing"]!])
        let theirs = SharedProfile(displayName: "B", bio: "", interests: [InterestCatalog.byID["climbing"]!])
        let highlights = InterestMatcher.overlap(mine, theirs)
        let opener = ConversationService.fallbackOpener(highlights: highlights, theirs: theirs)
        XCTAssertTrue(opener.lowercased().contains("climbing"))
        XCTAssertTrue(opener.hasSuffix("?"))
    }

    func testFallbackIsWarmAndHonestWhenNothingIsShared() {
        let theirs = SharedProfile(displayName: "B", bio: "", interests: [])
        let opener = ConversationService.fallbackOpener(highlights: [], theirs: theirs)
        XCTAssertTrue(opener.hasSuffix("?"))
        XCTAssertFalse(opener.lowercased().contains("you both"), "must not claim a shared interest")
    }

    func testInsightFallsBackAndLabelsItselfHonestly() async {
        let mine = SharedProfile(displayName: "A", bio: "", interests: [InterestCatalog.byID["photography"]!])
        let theirs = SharedProfile(displayName: "B", bio: "", interests: [InterestCatalog.byID["photography"]!])
        let insight = await ConversationService.makeInsight(mine: mine, theirs: theirs)
        XCTAssertEqual(insight.highlights.count, 1)
        XCTAssertFalse(insight.opener.isEmpty)
        if insight.openerSource == .fallbackTemplate {
            XCTAssertEqual(insight.openerSource.label, "Suggested question",
                           "a template must never be labelled as AI output")
        }
    }
}

// MARK: - Wire protocol

final class WireTests: XCTestCase {

    func testRoundTrip() throws {
        let data = try Wire.encode(.bumpEvent(localSequence: 3, magnitude: 22.5))
        let envelope = try Wire.decode(data)
        guard case .bumpEvent(let seq, let magnitude) = envelope.body else { return XCTFail("wrong body") }
        XCTAssertEqual(seq, 3)
        XCTAssertEqual(magnitude, 22.5, accuracy: 0.001)
        XCTAssertEqual(envelope.v, Wire.version)
    }

    func testOversizeFrameIsRejectedBeforeDecoding() {
        let junk = Data(repeating: 0x41, count: Wire.maxFrame + 1)
        XCTAssertThrowsError(try Wire.decode(junk)) { error in
            XCTAssertEqual(error as? Wire.WireError, .tooLarge(junk.count))
        }
    }

    func testVersionMismatchIsRejectedWithAUsefulMessage() throws {
        let json = #"{"v":99,"id":"x","body":{"bumpTimedOut":{}}}"#.data(using: .utf8)!
        XCTAssertThrowsError(try Wire.decode(json)) { error in
            guard case .badVersion(99)? = error as? Wire.WireError else { return XCTFail("wrong error") }
            XCTAssertTrue(error.localizedDescription.contains("same app version"))
        }
    }

    func testMalformedJSONDoesNotCrash() {
        XCTAssertThrowsError(try Wire.decode(Data([0x7B, 0x00, 0xFF])))
    }

    func testSeenMessagesDropsDuplicatesAndStaysBounded() {
        var seen = SeenMessages(limit: 3)
        XCTAssertTrue(seen.accept("a"))
        XCTAssertFalse(seen.accept("a"), "duplicate")
        XCTAssertTrue(seen.accept("b"))
        XCTAssertTrue(seen.accept("c"))
        XCTAssertTrue(seen.accept("d"))          // evicts "a"
        XCTAssertTrue(seen.accept("a"), "evicted ids may be seen again; the set stays bounded")
    }

    func testMemberCarriesNoInterests() throws {
        // Guard against ever widening what gets broadcast to the room.
        let member = Wire.Member(id: "x#1234", displayName: "Sam", supportsUWB: true)
        let json = String(data: try JSONEncoder().encode(member), encoding: .utf8)!
        XCTAssertFalse(json.contains("interest"))
        XCTAssertFalse(json.contains("bio"))
    }
}

// MARK: - Persistence

@MainActor
final class StoreTests: XCTestCase {

    private func connection(_ name: String) -> SavedConnection {
        SavedConnection(partnerName: name, partnerBio: "", metOn: Date(), roomName: "r",
                        insight: ConnectionInsight(highlights: [], opener: "Hi?", openerSource: .fallbackTemplate),
                        pairingEvidence: .motionOnly)
    }

    func testSaveIsIdempotentByID() {
        let store = Store(inMemory: true)
        let c = connection("Ada")
        store.save(c); store.save(c)
        XCTAssertEqual(store.connections.count, 1, "a retried save must not duplicate")
    }

    func testDeleteRemovesTheRightRow() {
        let store = Store(inMemory: true)
        let a = connection("Ada"), b = connection("Bo")
        store.save(a); store.save(b)
        store.delete(a)
        XCTAssertEqual(store.connections.map(\.partnerName), ["Bo"])
    }

    func testProfileRoundTripsThroughJSON() throws {
        let profile = Profile(displayName: "Ada", bio: "hi",
                              interests: [InterestCatalog.byID["chess"]!])
        let decoded = try JSONDecoder().decode(Profile.self, from: JSONEncoder().encode(profile))
        XCTAssertEqual(decoded, profile)
        XCTAssertTrue(decoded.isComplete)
    }

    func testIncompleteProfileIsRejectedByTheGate() {
        XCTAssertFalse(Profile(displayName: "", bio: "", interests: []).isComplete)
        XCTAssertFalse(Profile(displayName: "Ada", bio: "", interests: []).isComplete)
        XCTAssertTrue(Profile(displayName: "Ada", bio: "",
                              interests: [InterestCatalog.byID["chess"]!]).isComplete)
    }

    func testManualSelectionIsNeverRecordedAsADetectedBump() {
        let manual = SavedConnection(partnerName: "X", partnerBio: "", metOn: Date(), roomName: "r",
                                     insight: ConnectionInsight(highlights: [], opener: "?", openerSource: .fallbackTemplate),
                                     pairingEvidence: .manualSelection)
        XCTAssertEqual(manual.pairingEvidence.label, "Picked manually")
        XCTAssertNotEqual(manual.pairingEvidence, .motionOnly)
        XCTAssertNotEqual(manual.pairingEvidence, .motionAndUWB)
    }
}

// MARK: - Streetpass log

@MainActor
final class StreetpassStoreTests: XCTestCase {

    func testNewestFirst() {
        let store = Store(inMemory: true)
        let t0 = Date(timeIntervalSince1970: 1_000_000)
        store.recordStreetpass(name: "Ada", roomName: "nearby", at: t0)
        store.recordStreetpass(name: "Grace", roomName: "nearby", at: t0 + 3_600)
        XCTAssertEqual(store.streetpasses.map(\.peerName), ["Grace", "Ada"])
    }

    func testRepeatInsideTheWindowIsTheSameEncounter() {
        let store = Store(inMemory: true)
        let t0 = Date(timeIntervalSince1970: 1_000_000)
        store.recordStreetpass(name: "Ada", roomName: "nearby", at: t0)
        // A Multipeer reconnect a minute later is not a second encounter.
        store.recordStreetpass(name: "Ada", roomName: "nearby", at: t0 + 60)
        XCTAssertEqual(store.streetpasses.count, 1)
    }

    func testRepeatOutsideTheWindowIsANewEncounter() {
        let store = Store(inMemory: true)
        let t0 = Date(timeIntervalSince1970: 1_000_000)
        store.recordStreetpass(name: "Ada", roomName: "nearby", at: t0)
        store.recordStreetpass(name: "Ada", roomName: "nearby",
                               at: t0 + Store.streetpassDedupeWindow + 1)
        XCTAssertEqual(store.streetpasses.count, 2)
    }

    func testBlankNameIsIgnored() {
        let store = Store(inMemory: true)
        store.recordStreetpass(name: "   ", roomName: "nearby")
        XCTAssertTrue(store.streetpasses.isEmpty)
    }

    func testTheLogIsCapped() {
        let store = Store(inMemory: true)
        let t0 = Date(timeIntervalSince1970: 1_000_000)
        for i in 0..<(Store.streetpassLimit + 25) {
            store.recordStreetpass(name: "Person \(i)", roomName: "nearby",
                                   at: t0 + Double(i))
        }
        XCTAssertEqual(store.streetpasses.count, Store.streetpassLimit)
        // The oldest rows are the ones dropped.
        XCTAssertEqual(store.streetpasses.first?.peerName,
                       "Person \(Store.streetpassLimit + 24)")
    }

    func testClearingRemovesOnlyPassersBy() {
        let store = Store(inMemory: true)
        store.save(SavedConnection(partnerName: "Ada", partnerBio: "", metOn: Date(), roomName: "r",
                                   insight: ConnectionInsight(highlights: [], opener: "?", openerSource: .fallbackTemplate),
                                   pairingEvidence: .motionOnly))
        store.recordStreetpass(name: "Grace", roomName: "nearby")
        store.clearStreetpasses()
        XCTAssertTrue(store.streetpasses.isEmpty)
        XCTAssertEqual(store.connections.count, 1)
    }
}

// MARK: - Reliability regressions (two-phone field failures)

@MainActor
final class ReliabilityTests: XCTestCase {

    private func engine() -> BumpEngine {
        let store = Store(inMemory: true)
        store.settings.transport = .nearby    // these exercise the offline path
        store.profile = Profile(displayName: "Ada", bio: "",
                                interests: [InterestCatalog.byID["chess"]!])
        let e = BumpEngine(store: store)
        // The Simulator has no accelerometer; pretend it does so the sensing
        // path can be exercised.
        e.motion.availabilityOverride = true
        e.resetAndReconnect()
        return e
    }

    typealias R = BumpEngine.ReadinessInputs

    func testReadyRequiresAConnectedPeerNotJustAStartedService() {
        var i = R(phase: .ready, room: .joined(code: "nearby"), motionRunning: true)
        XCTAssertEqual(BumpEngine.readiness(i), .lookingForPhones(hint: nil))
        i.joinInFlight = true
        XCTAssertEqual(BumpEngine.readiness(i), .connecting)
        i.connectedPeers = 1
        XCTAssertEqual(BumpEngine.readiness(i), .listening)
    }

    func testReadyRequiresMotionActuallyRunning() {
        let i = R(phase: .ready, room: .hosting(code: "nearby"), connectedPeers: 1, motionRunning: false)
        XCTAssertNotEqual(BumpEngine.readiness(i), .listening,
                          "phase .ready with the accelerometer off must not read as ready")
    }

    func testALongSearchExplainsLocalNetworkInsteadOfSpinning() {
        let i = R(room: .joined(code: "nearby"), searchStalled: true)
        guard case .lookingForPhones(let hint?) = BumpEngine.readiness(i) else { return XCTFail() }
        XCTAssertTrue(hint.contains("Local Network"))
        XCTAssertFalse(hint.contains("\u{2014}"), "no em dashes in user-facing copy")
    }

    func testHostLossReadsAsReconnectingAndBackgroundNeedsFreshRanging() {
        XCTAssertEqual(BumpEngine.readiness(R(room: .hostLost(code: "nearby"))), .reconnecting)
        var bg = R(phase: .ready, room: .joined(code: "nearby"), connectedPeers: 1,
                   motionRunning: false, backgrounded: true, freshUWB: false)
        XCTAssertEqual(BumpEngine.readiness(bg), .reconnecting,
                       "a Live Activity alone is not proof that sensing is alive")
        bg.freshUWB = true
        XCTAssertEqual(BumpEngine.readiness(bg), .listening)
    }

    func testMotionUnavailableDoesNotBlockWhenUWBIsMissingAndViceVersa() {
        // UWB missing is not an input at all in the motion path.
        let i = R(phase: .ready, room: .joined(code: "nearby"), connectedPeers: 1,
                  motionRunning: true, freshUWB: false)
        XCTAssertEqual(BumpEngine.readiness(i), .listening)
    }

    /// Field failure: a permission prompt made the app inactive, that stopped
    /// motion, and with a Live Activity running nothing restarted it.
    func testAPermissionPromptInactivityDoesNotStopSensing() {
        let e = engine()
        XCTAssertTrue(e.motion.isRunning)
        e.handleScenePhase(.inactive)
        XCTAssertFalse(e.isBackgrounded, "inactive is not backgrounded")
        XCTAssertTrue(e.motion.isRunning, "a system prompt must not stop the accelerometer")
        e.handleScenePhase(.active)
        XCTAssertTrue(e.motion.isRunning)
    }

    func testForegroundRestartsMotionThatStoppedWhilePhaseSaidReady() {
        let e = engine()
        XCTAssertEqual(e.phase, .ready)
        e.motion.stop()                       // the stranded state
        e.handleScenePhase(.active)
        XCTAssertTrue(e.motion.isRunning, "returning to the app must restart sensing")
    }

    func testBackgroundThenForegroundResumesSensingWithoutATap() {
        let e = engine()
        e.handleScenePhase(.background)
        XCTAssertFalse(e.motion.isRunning)
        e.handleScenePhase(.active)
        XCTAssertTrue(e.motion.isRunning)
        XCTAssertEqual(e.phase, .ready)
    }

    func testRetryIsNotADeadEnd() {
        let e = engine()
        e.retry()
        XCTAssertEqual(e.phase, .ready, "retry used to park the phase at .notReady forever")
        XCTAssertTrue(e.motion.isRunning)
    }

    func testRepeatedAutoStartDoesNotRestartMotionOrRoom() {
        let e = engine()
        let room = e.room
        for _ in 0..<5 { e.autoStart(); e.handleScenePhase(.active) }
        XCTAssertEqual(e.room, room)
        XCTAssertTrue(e.motion.isRunning)
    }

    /// Only one phone felt it, or nobody is connected: say so, do not wait and
    /// blame the network.
    func testABumpWithNoConnectedPhoneIsReportedAsSuch() {
        let e = engine()
        e.motion.onSpike?(30)
        XCTAssertEqual(e.counters.bumpsDetected, 1)
        XCTAssertEqual(e.counters.bumpsNotSent, 1)
        guard case .needsRetry(let why) = e.phase else { return XCTFail("\(e.phase)") }
        XCTAssertTrue(why.contains("no other phone is connected"))
    }

    func testARestingOutcomeReturnsToListeningOnItsOwn() async throws {
        let e = engine()
        e.motion.onSpike?(30)                 // -> needsRetry
        guard case .needsRetry = e.phase else { return XCTFail() }
        try await Task.sleep(nanoseconds: UInt64((BumpEngine.restingOutcomeDuration + 0.8) * 1e9))
        XCTAssertEqual(e.phase, .ready, "a repeat trial must not need a tap or a restart")
    }

    func testASpikeWhileNotReadyIsCountedAsSuppressedNotLost() {
        let e = engine()
        e.pause()
        e.motion.onSpike?(30)
        XCTAssertEqual(e.counters.bumpsSuppressed, 1)
        XCTAssertEqual(e.counters.bumpsDetected, 0)
    }

    func testSettingsChangeAppliesToARunningDetector() {
        let e = engine()
        e.motion.config.threshold = 12
        XCTAssertTrue(e.motion.isRunning, "a live threshold change restarts, not stops, sensing")
        XCTAssertEqual(e.motion.config.threshold, 12)
    }

    func testCooldownRearmsAfterAQuietPeriod() {
        var gate = SpikeGate(threshold: 20, rearmFactor: 0.5, cooldown: 1.5)
        XCTAssertEqual(gate.feed(magnitude: 25, now: 100), .spike(25))
        _ = gate.feed(magnitude: 1, now: 100.1)
        // Long after: nothing latched.
        XCTAssertEqual(gate.feed(magnitude: 25, now: 500), .spike(25))
    }

    func testLogKindNeverIncludesPayload() {
        let kind = Wire.kind(of: .discoveryToken(Data([1, 2, 3, 4])))
        XCTAssertEqual(kind, "discoveryToken")
        XCTAssertEqual(Wire.kind(of: .bumpTimedOut), "bumpTimedOut")
    }

    func testDiagnosticsRowsExcludeProfileContent() {
        let e = engine()
        let text = e.diagnosticsRows().map { "\($0.0) \($0.1)" }.joined(separator: "\n")
        XCTAssertFalse(text.contains("chess"))
        XCTAssertTrue(text.contains("Readiness"))
    }
}

// MARK: - Server relay, end to end (needs `npm start` in backend/)

@MainActor
final class RelayEndToEndTests: XCTestCase {

    private func phone(_ name: String, server: String) -> BumpEngine {
        let store = Store(inMemory: true)
        store.settings.apiBaseURL = server
        store.settings.transport = .server
        store.profile = Profile(displayName: name, bio: "",
                                interests: [InterestCatalog.byID["chess"]!])
        let e = BumpEngine(store: store)
        e.motion.availabilityOverride = true
        e.resetAndReconnect()
        return e
    }

    private func until(_ what: String, timeout: TimeInterval = 15, _ cond: () -> Bool) async throws {
        let end = Date().addingTimeInterval(timeout)
        while !cond() {
            guard Date() < end else { return XCTFail("timed out waiting for \(what)") }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
    }

    func testTwoPhonesBumpConfirmAndConnectThroughTheServer() async throws {
        let server = "http://127.0.0.1:8787"
        guard await BumpEngine.relayAvailable(BumpAPIClient(baseURL: URL(string: server)!), timeout: 2) else {
            throw XCTSkip("backend not running on \(server)")
        }
        let a = phone("Ada", server: server)
        let b = phone("Bea", server: server)
        defer { a.stopNearby(); b.stopNearby() }

        try await until("both connected and listening") { a.autoStatus == .listening && b.autoStatus == .listening }
        XCTAssertNotEqual(a.isCoordinator, b.isCoordinator, "exactly one coordinator")

        // Both feel the bump at (nearly) the same moment.
        a.motion.onSpike?(30); b.motion.onSpike?(28)
        try await until("a proposal on both") {
            if case .confirming = a.phase, case .confirming = b.phase { return true }
            return false
        }
        guard case .confirming(let pa) = a.phase, case .confirming(let pb) = b.phase else { return }
        XCTAssertEqual(pa.id, pb.id, "one authoritative proposal")
        XCTAssertEqual(pa.evidence, .motionOnly, "no UWB in the Simulator; must not claim it")

        a.confirmCurrent(); b.confirmCurrent()
        try await until("connected on both", timeout: 20) {
            if case .connected = a.phase, case .connected = b.phase { return true }
            return false
        }

        // A second encounter needs no restart.
        a.bumpAgain(); b.bumpAgain()
        try await until("listening again") { a.autoStatus == .listening && b.autoStatus == .listening }
        a.motion.onSpike?(30); b.motion.onSpike?(30)
        try await until("second proposal") {
            if case .confirming = a.phase, case .confirming = b.phase { return true }
            return false
        }
        a.declineCurrent()
        try await until("both back to listening after a rejection", timeout: 12) {
            a.phase == .ready && b.phase == .ready
        }
    }
}

// MARK: - Related interests via tags

final class RelatedInterestTests: XCTestCase {

    private func profile(_ interests: [Interest]) -> SharedProfile {
        SharedProfile(displayName: "x", bio: "", interests: interests)
    }

    func testDifferentShowsMeetAtTheirSharedTag() {
        let a = profile([Interest(id: "custom:one piece", label: "One Piece", specificity: 2, custom: true, tags: ["anime", "manga"])])
        let b = profile([Interest(id: "custom:naruto", label: "Naruto", specificity: 2, custom: true, tags: ["anime"])])
        let h = InterestMatcher.overlap(a, b)
        XCTAssertEqual(h.first?.statement, "You're both into anime.")
        XCTAssertEqual(h.first?.yourEntry, "One Piece")
        XCTAssertEqual(h.first?.theirEntry, "Naruto")
        XCTAssertFalse(h.contains { $0.interestID == "related:screen" }, "the broad parent is redundant")
    }

    func testExactMatchesStillRankFirst() {
        let a = profile([InterestCatalog.byID["chess"]!,
                         Interest(id: "custom:one piece", label: "One Piece", specificity: 2, custom: true, tags: ["anime"])])
        let b = profile([InterestCatalog.byID["chess"]!,
                         Interest(id: "custom:naruto", label: "Naruto", specificity: 2, custom: true, tags: ["anime"])])
        let h = InterestMatcher.overlap(a, b)
        XCTAssertEqual(h.first?.interestID, "chess")
        XCTAssertTrue(h.contains { $0.interestID == "related:anime" })
    }

    func testUntaggedUnrelatedInterestsStillDoNotMatch() {
        let a = profile([Interest(id: "custom:one piece", label: "One Piece", specificity: 2, custom: true)])
        let b = profile([Interest(id: "custom:sourdough x", label: "Sourdough x", specificity: 2, custom: true, tags: ["baking"])])
        XCTAssertTrue(InterestMatcher.overlap(a, b).isEmpty, "nothing is invented")
    }
}
