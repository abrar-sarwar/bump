import Foundation

/// Turns a stream of UWB distances into at most one "they came together" event.
///
/// Used when there is no accelerometer to lean on, which is every backgrounded
/// session: Core Motion gets no background execution, so proximity is the only
/// evidence available. Pure and clock-injected so it is testable without radios.
///
/// This detects PROXIMITY, not impact. Crossing the threshold means two phones
/// came within a few centimetres of each other, which is weaker evidence than a
/// deliberate motion spike. Mutual confirmation still decides everything.
struct ProximityGate {

    /// Fire when a fresh distance is at or below this.
    var threshold: Double
    /// Must go back above this before another event can fire, so a reading
    /// hovering around the threshold cannot machine-gun proposals.
    var rearm: Double
    /// Minimum gap between two events.
    var cooldown: TimeInterval
    /// A measurement older than this says nothing about now.
    var freshness: TimeInterval
    /// The distance must actually have come down by this much beforehand, so
    /// two phones resting side by side on a table never trigger.
    var minimumApproach: Double

    init(threshold: Double = 0.15,
         rearm: Double = 0.45,
         cooldown: TimeInterval = 3,
         freshness: TimeInterval = 1.5,
         minimumApproach: Double = 0.25) {
        self.threshold = threshold
        self.rearm = rearm
        self.cooldown = cooldown
        self.freshness = freshness
        self.minimumApproach = minimumApproach
    }

    enum Verdict: Equatable {
        case bump(Double)
        case tooFar
        case notRearmed          // still close from the previous event
        case noApproach          // close, but it never came from further away
        case suppressedByCooldown
        case stale
    }

    /// Armed only after we have seen the peer far enough away to call the next
    /// close reading an approach.
    private var armed = false
    private var sawFarEnough = false
    private var lastFire: TimeInterval = -.greatestFiniteMagnitude

    mutating func feed(distance: Double, age: TimeInterval, now: TimeInterval) -> Verdict {
        guard age <= freshness else { return .stale }

        if distance >= rearm {
            armed = true
            if distance >= threshold + minimumApproach { sawFarEnough = true }
            return .tooFar
        }
        guard distance <= threshold else { return .tooFar }
        guard armed else { return .notRearmed }
        guard sawFarEnough else { return .noApproach }

        armed = false
        guard now - lastFire >= cooldown else { return .suppressedByCooldown }
        lastFire = now
        sawFarEnough = false
        return .bump(distance)
    }

    /// Forget the approach history, for example when the peer changes or the
    /// session restarts. Never call this from a measurement callback.
    mutating func reset() {
        armed = false
        sawFarEnough = false
    }
}
