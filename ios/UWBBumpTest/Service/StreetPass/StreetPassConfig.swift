import Foundation

/// Centralized, adjustable tunables for the StreetPass ambient-encounter
/// pipeline — one place to tune, not magic numbers scattered through
/// delegate callbacks. Mirrors RangingService.Config / PairingMatcher.Config.
struct StreetPassConfig: Equatable {
    /// Distance below this counts toward a qualifying encounter. Experimental,
    /// not proof of a deliberate pass.
    var proximityThreshold: Double = 0.5
    /// Consecutive sub-threshold readings required before an encounter
    /// qualifies. Debounces a single noisy reading.
    var consecutiveReadingsRequired: Int = 3
    /// The peer's distance must exceed proximityThreshold + this margin
    /// before the gate can rearm for another encounter with them.
    var exitHysteresisMargin: Double = 0.5
    /// Minimum time between two qualifying encounters with the same peer,
    /// even after rearming.
    var cooldown: TimeInterval = 30
    /// Practical cap on simultaneous StreetPass ranging sessions, independent
    /// of RangingService.maxConcurrentPeers so the two subsystems never
    /// contend for whatever ceiling the hardware actually has.
    var maxConcurrentPeers: Int = 3
    /// A measurement older than this is stale and must not be used.
    var measurementFreshness: TimeInterval = 1.5
}
