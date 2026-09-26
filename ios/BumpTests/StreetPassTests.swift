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

    /// Frame-size arithmetic, not image validity: a worst-case `.hello` — an
    /// avatar at the full `ProfilePhoto.thumbnailMaxBytes` budget, a
    /// maximum-length display name, and five long custom interests — must still
    /// fit inside `StreetPassWire.maxFrame` once JSON has base64'd the avatar
    /// (~4/3 expansion) and added the envelope. If it doesn't, `encode` throws
    /// `.tooLarge`, `StreetPassTransport.send` swallows it, and the peer's
    /// profile never arrives — which silently kills every encounter with that
    /// peer, since `handleMeasurement` needs the profile to build an encounter.
    func testHelloFrameWithAMaxBudgetThumbnailAndFullInterestListFitsTheWireCap() throws {
        let profile = StreetPassPeerProfile(
            id: "Maximilian Wordsworth#ABCD",
            displayName: String(repeating: "W", count: 24),
            avatarThumbnail: Data(repeating: 0x41, count: ProfilePhoto.thumbnailMaxBytes),
            interests: worstCaseInterests)
        XCTAssertEqual(profile.interests.count, StreetPassPeerProfile.maxInterests)

        let data = try StreetPassWire.encode(.hello(profile: profile))
        XCTAssertLessThanOrEqual(data.count, StreetPassWire.maxFrame,
                                 "a budgeted avatar must never overflow the StreetPass frame")
        // Headroom, not just a pass: half the cap still leaves room for longer
        // custom interest text than this before anything breaks.
        XCTAssertLessThanOrEqual(data.count, StreetPassWire.maxFrame / 2,
                                 "the thumbnail budget should leave real headroom under the cap")
        // And it must survive the round trip, avatar bytes intact.
        let envelope = try StreetPassWire.decode(data)
        guard case .hello(let decoded) = envelope.body else { return XCTFail("wrong body") }
        XCTAssertEqual(decoded.avatarThumbnail?.count, ProfilePhoto.thumbnailMaxBytes)
    }

    /// The other half of the arithmetic, and the bug this guards against: a
    /// full-size profile photo (`ProfilePhoto.maxBytes`, sized for the 64 KB
    /// `Wire` frame) cannot be forwarded into a StreetPass `.hello`. This is
    /// why `StreetPassEngine.myPeerProfile()` re-encodes a thumbnail instead of
    /// passing `store.profile.photo` straight through.
    func testHelloFrameWithAFullSizeProfilePhotoIsRejected() {
        let profile = StreetPassPeerProfile(
            id: "p#1",
            displayName: "Sam",
            avatarThumbnail: Data(repeating: 0x41, count: ProfilePhoto.maxBytes),
            interests: worstCaseInterests)
        XCTAssertThrowsError(try StreetPassWire.encode(.hello(profile: profile))) { error in
            guard case .tooLarge = (error as? StreetPassWire.WireError) else {
                return XCTFail("expected .tooLarge, got \(error)")
            }
        }
    }

    /// Five custom interests with realistic, non-trivial labels — the largest
    /// interest list `StreetPassPeerProfile` will carry.
    private var worstCaseInterests: [Interest] {
        ["Competitive duck herding at dawn",
         "Third-wave single-origin pour-over coffee",
         "Restoring vintage Italian espresso machines",
         "Long-exposure astrophotography in the desert",
         "Late-night improvisational jazz piano"]
            .map { Interest(id: "custom:\($0.lowercased())", label: $0,
                            parent: "music", specificity: 2, custom: true) }
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

// MARK: - Teaser split

/// The card shows one mutual interest in the clear and blurs the rest. These
/// cover the split itself: which statement is revealed, which are teased, and
/// that nothing is ever invented to fill the blurred rows.
final class StreetPassTeaserTests: XCTestCase {
    private func interests(_ labels: [String]) -> [Interest] {
        labels.compactMap { InterestCatalog.canonical(from: $0) }
    }

    func testFirstMatchIsRevealedAndTheRestAreTeased() {
        let teaser = StreetPassEncounter.teaser(mine: interests(["Jazz", "Photography", "Bouldering"]),
                                                theirs: interests(["Jazz", "Photography", "Bouldering"]))
        let all = InterestMatcher.overlap(interests(["Jazz", "Photography", "Bouldering"]),
                                          interests(["Jazz", "Photography", "Bouldering"]),
                                          limit: 3).map(\.statement)
        XCTAssertEqual(teaser.statement, all.first)
        XCTAssertEqual(teaser.teased, Array(all.dropFirst()))
    }

    func testASingleMatchTeasesNothing() {
        let teaser = StreetPassEncounter.teaser(mine: interests(["Jazz", "Bouldering"]),
                                                theirs: interests(["Jazz", "Vinyl"]))
        XCTAssertNotNil(teaser.statement)
        XCTAssertTrue(teaser.teased.isEmpty, "one match must never be padded out with invented rows")
    }

    func testNoOverlapRevealsAndTeasesNothing() {
        let teaser = StreetPassEncounter.teaser(mine: interests(["Jazz piano"]),
                                                theirs: interests(["Bouldering"]))
        XCTAssertNil(teaser.statement)
        XCTAssertTrue(teaser.teased.isEmpty)
    }

    func testAtMostTwoRowsAreTeased() {
        let many = interests(["Jazz", "Photography", "Bouldering", "Espresso", "Vinyl"])
        let teaser = StreetPassEncounter.teaser(mine: many, theirs: many)
        XCTAssertLessThanOrEqual(teaser.teased.count, 2)
    }
}
