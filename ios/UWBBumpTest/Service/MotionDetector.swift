import CoreMotion
import Foundation

/// Native bump detection from Core Motion.
///
/// UNITS: `CMDeviceMotion.userAcceleration` is in **g**, gravity already removed
/// by the device-motion filter. We convert explicitly to m/s² with `G` below so
/// the threshold is in the same units the UI shows. The old web experiment's
/// 12 m/s² threshold came from a hand-rolled high-pass over
/// `accelerationIncludingGravity` in a browser at a different sample rate — it is
/// NOT transferable, so the default here is set independently and must be tuned
/// on hardware.
@MainActor
final class MotionDetector: ObservableObject {

    /// Standard gravity, for the g → m/s² conversion.
    nonisolated static let G: Double = 9.80665

    struct Config: Equatable {
        /// Spike threshold in m/s², gravity excluded.
        var threshold: Double = 20.0
        /// Must fall below `threshold * rearmFactor` before another spike can fire.
        var rearmFactor: Double = 0.5
        /// Minimum gap between two reported spikes.
        var cooldown: TimeInterval = 1.5
        /// Sensor rate. 50 Hz is plenty for a hand bump and cheaper than 100 Hz.
        var updateInterval: TimeInterval = 1.0 / 50.0
    }

    @Published private(set) var isRunning = false
    @Published private(set) var currentMagnitude: Double = 0
    @Published private(set) var lastSpikeMagnitude: Double?
    @Published private(set) var lastSpikeAt: Date?
    @Published var config = Config()

    /// Fired on the main actor when a deliberate spike crosses the threshold.
    var onSpike: ((Double) -> Void)?

    private let manager = CMMotionManager()
    /// Sensor callbacks land here, off the UI thread; only the published
    /// summary is hopped back to the main actor.
    private let queue: OperationQueue = {
        let q = OperationQueue()
        q.name = "bump.motion"
        q.qualityOfService = .userInitiated
        q.maxConcurrentOperationCount = 1
        return q
    }()

    var isAvailable: Bool { manager.isDeviceMotionAvailable }

    func start() {
        guard !isRunning, manager.isDeviceMotionAvailable else { return }
        manager.deviceMotionUpdateInterval = config.updateInterval
        gate = SpikeGate(threshold: config.threshold,
                         rearmFactor: config.rearmFactor,
                         cooldown: config.cooldown)

        manager.startDeviceMotionUpdates(to: queue) { [weak self] motion, _ in
            guard let self, let motion else { return }
            // userAcceleration is in g with gravity already removed by the
            // device-motion filter; convert explicitly to m/s².
            let a = motion.userAcceleration
            let magnitude = sqrt(a.x * a.x + a.y * a.y + a.z * a.z) * Self.G

            // CMDeviceMotion.timestamp is seconds since boot: monotonic, and
            // immune to the user changing the wall clock.
            let verdict = self.gateStorage.feed(magnitude: magnitude, now: motion.timestamp)

            Task { @MainActor in
                self.currentMagnitude = magnitude
                if case .spike(let value) = verdict {
                    self.lastSpikeMagnitude = value
                    self.lastSpikeAt = Date()
                    self.onSpike?(value)
                }
            }
        }
        isRunning = true
    }

    func stop() {
        guard isRunning else { return }
        manager.stopDeviceMotionUpdates()
        isRunning = false
        currentMagnitude = 0
    }

    /// Gate state lives in a class box because it is mutated only on `queue`
    /// (serial, maxConcurrentOperationCount == 1) and never from the main actor.
    private final class GateBox: @unchecked Sendable {
        var gate: SpikeGate
        init(_ gate: SpikeGate) { self.gate = gate }
        func feed(magnitude: Double, now: TimeInterval) -> SpikeGate.Verdict {
            gate.feed(magnitude: magnitude, now: now)
        }
    }
    private let gateStorage = GateBox(SpikeGate(threshold: 20))
    private var gate: SpikeGate {
        get { gateStorage.gate } set { gateStorage.gate = newValue }
    }
}
