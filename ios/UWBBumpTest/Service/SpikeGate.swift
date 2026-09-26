import Foundation

/// The threshold-crossing / rearm / cooldown state machine, pulled out of
/// `MotionDetector` so it can be unit-tested without a real accelerometer.
///
/// Semantics:
///  - A spike fires on the CROSSING into the above-threshold region, once.
///  - It cannot fire again until the signal has fallen below
///    `threshold * rearmFactor` (hysteresis), so sustained shaking fires once.
///  - Even after rearming, a spike is suppressed until `cooldown` has elapsed.
///  - `now` is a monotonic seconds value supplied by the caller
///    (`CMDeviceMotion.timestamp`, i.e. seconds since boot).
struct SpikeGate {
    var threshold: Double
    var rearmFactor: Double = 0.5
    var cooldown: TimeInterval = 1.5

    private var armed = true
    private var lastFire: TimeInterval = -.greatestFiniteMagnitude

    enum Verdict: Equatable {
        case spike(Double)
        case suppressedByCooldown(Double)
        case belowThreshold
        case stillHigh          // above threshold, already fired for this crossing
    }

    init(threshold: Double, rearmFactor: Double = 0.5, cooldown: TimeInterval = 1.5) {
        self.threshold = threshold
        self.rearmFactor = rearmFactor
        self.cooldown = cooldown
    }

    mutating func feed(magnitude: Double, now: TimeInterval) -> Verdict {
        if magnitude >= threshold {
            guard armed else { return .stillHigh }
            armed = false
            guard now - lastFire >= cooldown else { return .suppressedByCooldown(magnitude) }
            lastFire = now
            return .spike(magnitude)
        }
        if magnitude < threshold * rearmFactor { armed = true }
        return .belowThreshold
    }
}
