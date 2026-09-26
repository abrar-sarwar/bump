import Foundation

/// Per-peer StreetPass encounter decision, pulled out so it is fully
/// unit-testable without NearbyInteraction. Same shape as SpikeGate:
/// consecutive-reading debounce, hysteresis rearm, and a cooldown, but
/// distance-based (qualifies BELOW a threshold) rather than acceleration-based.
struct StreetPassEncounterGate: Equatable {
    var proximityThreshold: Double
    var consecutiveReadingsRequired: Int
    var exitHysteresisMargin: Double
    var cooldown: TimeInterval

    private var consecutiveCount = 0
    private var armed = true
    private var lastQualifiedAt: TimeInterval = -.greatestFiniteMagnitude

    enum Verdict: Equatable {
        /// Fires once per encounter, when the debounce requirement is met.
        case qualified
        /// Still accumulating consecutive sub-threshold readings.
        case accumulating(Int)
        /// Debounce requirement met, but suppressed by cooldown.
        case suppressedByCooldown
        /// Below rearm, waiting to clearly exit past the hysteresis margin.
        case awaitingExit
        /// Above threshold and already rearmed; nothing pending.
        case idle
    }

    init(proximityThreshold: Double, consecutiveReadingsRequired: Int = 3,
         exitHysteresisMargin: Double = 0.5, cooldown: TimeInterval = 30) {
        self.proximityThreshold = proximityThreshold
        self.consecutiveReadingsRequired = consecutiveReadingsRequired
        self.exitHysteresisMargin = exitHysteresisMargin
        self.cooldown = cooldown
    }

    mutating func feed(distance: Double, now: TimeInterval) -> Verdict {
        if distance <= proximityThreshold {
            guard armed else { return .awaitingExit }
            consecutiveCount += 1
            guard consecutiveCount >= consecutiveReadingsRequired else {
                return .accumulating(consecutiveCount)
            }
            armed = false
            consecutiveCount = 0
            guard now - lastQualifiedAt >= cooldown else { return .suppressedByCooldown }
            lastQualifiedAt = now
            return .qualified
        }
        // Above threshold: a single far reading breaks a run of near ones,
        // and rearming requires clearly exceeding the hysteresis margin.
        consecutiveCount = 0
        if distance > proximityThreshold + exitHysteresisMargin {
            armed = true
        }
        return armed ? .idle : .awaitingExit
    }
}
