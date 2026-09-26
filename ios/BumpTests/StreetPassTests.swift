import XCTest
@testable import UWBBumpTest

// MARK: - Encounter gate

final class StreetPassEncounterGateTests: XCTestCase {

    private func gate(threshold: Double = 0.5, readings: Int = 3, margin: Double = 0.5,
                       cooldown: TimeInterval = 30) -> StreetPassEncounterGate {
        StreetPassEncounterGate(proximityThreshold: threshold, consecutiveReadingsRequired: readings,
                                exitHysteresisMargin: margin, cooldown: cooldown)
    }

    func testRequiresConsecutiveSubThresholdReadingsBeforeQualifying() {
        var g = gate()
        XCTAssertEqual(g.feed(distance: 0.4, now: 0), .accumulating(1))
        XCTAssertEqual(g.feed(distance: 0.4, now: 0.1), .accumulating(2))
        XCTAssertEqual(g.feed(distance: 0.4, now: 0.2), .qualified)
    }

    func testASingleFarReadingResetsTheConsecutiveCount() {
        var g = gate()
        XCTAssertEqual(g.feed(distance: 0.4, now: 0), .accumulating(1))
        XCTAssertEqual(g.feed(distance: 0.4, now: 0.1), .accumulating(2))
        XCTAssertEqual(g.feed(distance: 0.6, now: 0.2), .idle, "one far reading breaks the run")
        XCTAssertEqual(g.feed(distance: 0.4, now: 0.3), .accumulating(1), "must restart, not resume")
    }

    func testQualifiesOnceThenRequiresClearExitBeforeRefiring() {
        var g = gate(readings: 2, cooldown: 0)
        XCTAssertEqual(g.feed(distance: 0.3, now: 0), .accumulating(1))
        XCTAssertEqual(g.feed(distance: 0.3, now: 0.1), .qualified)
        // Sustained proximity must not refire.
        XCTAssertEqual(g.feed(distance: 0.3, now: 0.2), .awaitingExit)
        XCTAssertEqual(g.feed(distance: 0.3, now: 0.3), .awaitingExit)
        // Within the hysteresis band (above threshold, not past the margin): still no rearm.
        XCTAssertEqual(g.feed(distance: 0.7, now: 0.4), .awaitingExit)
        // Clearly past threshold + margin (0.5 + 0.5 = 1.0): rearms.
        XCTAssertEqual(g.feed(distance: 1.1, now: 0.5), .idle)
        XCTAssertEqual(g.feed(distance: 0.3, now: 0.6), .accumulating(1))
        XCTAssertEqual(g.feed(distance: 0.3, now: 0.7), .qualified)
    }

    func testCooldownSuppressesARequalificationEvenAfterRearming() {
        var g = gate(readings: 1, cooldown: 10)
        XCTAssertEqual(g.feed(distance: 0.3, now: 0), .qualified)
        // Threshold 0.5 + margin 0.5 = 1.0: 1.1 clearly clears it, 0.9 would not.
        XCTAssertEqual(g.feed(distance: 1.1, now: 1), .idle, "rearm")
        XCTAssertEqual(g.feed(distance: 0.3, now: 2), .suppressedByCooldown)
        XCTAssertEqual(g.feed(distance: 1.1, now: 3), .idle, "rearm again")
        XCTAssertEqual(g.feed(distance: 0.3, now: 11), .qualified, "past cooldown, a clean rearm can qualify again")
    }

    func testFreshGateAfterSimulatedDisconnectHasNoMemoryOfThePreviousEncounter() {
        var g = gate(readings: 1, cooldown: 30)
        XCTAssertEqual(g.feed(distance: 0.3, now: 0), .qualified)
        // Peer disconnects; StreetPassEngine discards this gate entirely
        // rather than carrying cooldown state across a reconnect.
        g = gate(readings: 1, cooldown: 30)
        XCTAssertEqual(g.feed(distance: 0.3, now: 0.1), .qualified,
                       "a fresh gate for a reconnected peer must not be suppressed by the old cooldown")
    }
}

// MARK: - Peer profile

final class StreetPassPeerProfileTests: XCTestCase {
    func testInterestListIsCappedAtFive() {
        let seven = (1...7).map { Interest(id: "i\($0)", label: "I\($0)") }
        let profile = StreetPassPeerProfile(id: "p#1", displayName: "Sam", interests: seven)
        XCTAssertEqual(profile.interests.count, 5)
        XCTAssertEqual(profile.interests.map(\.id), ["i1", "i2", "i3", "i4", "i5"])
    }
}

// MARK: - StreetPass wire protocol

final class StreetPassWireTests: XCTestCase {
    func testRoundTrip() throws {
        guard let jazzInterest = InterestCatalog.byID["jazz"] else {
            return XCTFail("jazz interest not found in catalog")
        }
        let profile = StreetPassPeerProfile(id: "p#1", displayName: "Sam",
                                            interests: [jazzInterest])
        let data = try StreetPassWire.encode(.hello(profile: profile))
        let envelope = try StreetPassWire.decode(data)
        guard case .hello(let decoded) = envelope.body else { return XCTFail("wrong body") }
        XCTAssertEqual(decoded, profile)
        XCTAssertEqual(envelope.v, StreetPassWire.version)
    }

    func testDiscoveryTokenRoundTrip() throws {
        let bytes = Data([0x01, 0x02, 0x03])
        let data = try StreetPassWire.encode(.discoveryToken(bytes))
        let envelope = try StreetPassWire.decode(data)
        guard case .discoveryToken(let decoded) = envelope.body else { return XCTFail("wrong body") }
        XCTAssertEqual(decoded, bytes)
    }

    func testOversizeFrameIsRejectedBeforeDecoding() {
        let junk = Data(repeating: 0x41, count: StreetPassWire.maxFrame + 1)
        XCTAssertThrowsError(try StreetPassWire.decode(junk)) { error in
            XCTAssertEqual(error as? StreetPassWire.WireError, .tooLarge(junk.count))
        }
    }

    func testMalformedJSONDoesNotCrash() {
        XCTAssertThrowsError(try StreetPassWire.decode(Data([0x7B, 0x00, 0xFF])))
    }

    func testBadVersionIsRejected() {
        // Manually construct an envelope with a different version
        var envelope = StreetPassWire.Envelope(body: .discoveryToken(Data()))
        envelope.v = 999
        let data = try! JSONEncoder().encode(envelope)
        XCTAssertThrowsError(try StreetPassWire.decode(data)) { error in
            XCTAssertEqual(error as? StreetPassWire.WireError, .badVersion(999))
        }
    }

    func testInterestCapIsEnforcedWhenDecodingFromJSON() throws {
        // Create JSON with a profile that has 7 interests, simulating a peer sending uncapped data
        // This uses the actual Interest structure as encoded
        let json = """
        {"id":"p#1","displayName":"Sam","avatarThumbnail":null,"interests":[{"id":"i1","label":"I1","parent":null,"specificity":1,"custom":false},{"id":"i2","label":"I2","parent":null,"specificity":1,"custom":false},{"id":"i3","label":"I3","parent":null,"specificity":1,"custom":false},{"id":"i4","label":"I4","parent":null,"specificity":1,"custom":false},{"id":"i5","label":"I5","parent":null,"specificity":1,"custom":false},{"id":"i6","label":"I6","parent":null,"specificity":1,"custom":false},{"id":"i7","label":"I7","parent":null,"specificity":1,"custom":false}]}
        """.data(using: .utf8)!

        // Decode the profile from JSON that has 7 interests
        let decodedProfile = try JSONDecoder().decode(StreetPassPeerProfile.self, from: json)

        // The critical assertion: even though the JSON had 7 interests,
        // the decoded profile must have exactly 5 due to the cap.
        // This test will FAIL until we implement custom init(from:) that applies the cap during decoding.
        XCTAssertEqual(decodedProfile.interests.count, 5,
                       "Interest cap must be enforced during JSON decoding, not just in memberwise init")
        XCTAssertEqual(decodedProfile.interests.map(\.id), ["i1", "i2", "i3", "i4", "i5"])
    }
}

// MARK: - Notifier copy

final class StreetPassNotifierTests: XCTestCase {
    private func encounter(mutual: String? = nil) -> StreetPassEncounter {
        StreetPassEncounter(id: "p#1", displayName: "Sam", avatarThumbnail: nil,
                            mutualInterestStatement: mutual)
    }

    func testBaseCopyIsAlwaysPresentAndSecondLineEmptyWithNoMutualInterest() {
        let copy = StreetPassNotifier.copy(for: encounter())
        XCTAssertEqual(copy.title, "hey, this person just walked by you. bump them?")
        XCTAssertEqual(copy.body, "")
    }

    func testSecondLineIsTheExactMutualInterestStatementWhenPresent() {
        let copy = StreetPassNotifier.copy(for: encounter(mutual: "You're both into jazz piano."))
        XCTAssertEqual(copy.body, "You're both into jazz piano.")
    }

    func testNeverInventsAnInterestLine() {
        XCTAssertFalse(StreetPassNotifier.copy(for: encounter()).body.contains("both"))
    }
}
