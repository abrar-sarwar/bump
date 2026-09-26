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
