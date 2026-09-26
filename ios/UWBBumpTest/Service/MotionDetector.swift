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
        /// Sensor rate. 100 Hz, not 50: the impact of a phone-to-phone tap is a
        /// spike of roughly 10 to 30 ms, so at 50 Hz one or both samples can
        /// land either side of the peak and a real bump reads well under the
        /// threshold on one phone only. Hypothesis to confirm with the recorded
        /// peaks on hardware.
        var updateInterval: TimeInterval = 1.0 / 100.0
    }

    @Published private(set) var isRunning = false
    @Published private(set) var currentMagnitude: Double = 0
    @Published private(set) var lastSpikeMagnitude: Double?
    @Published private(set) var lastSpikeAt: Date?
    @Published var config = Config() {
        // A threshold change used to apply only after the next stop/start, so
        // the slider could show one value while the gate used another.
        didSet { if isRunning && config != oldValue { stop(); start() } }
    }

    // Diagnostics. Published at most a few times a second, not per sample.
    @Published private(set) var sampleCount = 0
    @Published private(set) var lastSampleAt: Date?
    /// Highest magnitude in the last `peakWindow` seconds, whether or not it
    /// crossed the threshold. This is the number to compare against the
    /// threshold after a trial that did not fire.
    @Published private(set) var recentPeak: Double = 0
    @Published private(set) var spikesDetected = 0
    @Published private(set) var spikesSuppressed = 0
    nonisolated static let peakWindow: TimeInterval = 3

    #if DEBUG
    /// Tests only: pretend the sensor exists (the Simulator has none).
    var availabilityOverride: Bool?
    #endif

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

    var isAvailable: Bool {
        #if DEBUG
        if let availabilityOverride { return availabilityOverride }
        #endif
        return manager.isDeviceMotionAvailable
    }

    func start() {
        guard !isRunning, isAvailable else { return }
        isRunning = true
        guard manager.isDeviceMotionAvailable else { return }   // test override only
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
            let summary = self.gateStorage.summarise(magnitude: magnitude, now: motion.timestamp,
                                                     verdict: verdict)

            // Hop to the main actor only for events and a ~10 Hz summary, not
            // for every one of the 100 samples a second.
            guard summary != nil || verdict != .belowThreshold && verdict != .stillHigh else { return }
            Task { @MainActor in
                if let summary {
                    self.currentMagnitude = magnitude
                    self.sampleCount = summary.count
                    self.lastSampleAt = Date()
                    self.recentPeak = summary.peak
                }
                switch verdict {
                case .spike(let value):
                    self.spikesDetected += 1
                    self.lastSpikeMagnitude = value
                    self.lastSpikeAt = Date()
                    self.onSpike?(value)
                case .suppressedByCooldown(let value):
                    self.spikesSuppressed += 1
                    self.onSuppressed?(value)
                default: break
                }
            }
        }
    }

    /// Fired on the main actor when a crossing was swallowed by the cooldown.
    var onSuppressed: ((Double) -> Void)?

    /// Seconds since the last sample, or nil if none has arrived. A running
    /// detector with a large age has silently stopped delivering.
    var sampleAge: TimeInterval? { lastSampleAt.map { Date().timeIntervalSince($0) } }

    func stop() {
        guard isRunning else { return }
        manager.stopDeviceMotionUpdates()
        isRunning = false
        currentMagnitude = 0
        lastSampleAt = nil
    }

    /// Gate state lives in a class box because it is mutated only on `queue`
    /// (serial, maxConcurrentOperationCount == 1) and never from the main actor.
    private final class GateBox: @unchecked Sendable {
        var gate: SpikeGate
        init(_ gate: SpikeGate) { self.gate = gate }
        var count = 0
        var peaks: [(at: TimeInterval, value: Double)] = []
        var lastSummaryAt: TimeInterval = 0
        func feed(magnitude: Double, now: TimeInterval) -> SpikeGate.Verdict {
            gate.feed(magnitude: magnitude, now: now)
        }
        /// Rolling peak plus a throttled snapshot for the UI.
        func summarise(magnitude: Double, now: TimeInterval,
                       verdict: SpikeGate.Verdict) -> (count: Int, peak: Double)? {
            count += 1
            peaks.append((now, magnitude))
            peaks.removeAll { now - $0.at > MotionDetector.peakWindow }
            let isEvent = verdict != .belowThreshold && verdict != .stillHigh
            guard isEvent || now - lastSummaryAt >= 0.1 else { return nil }
            lastSummaryAt = now
            return (count, peaks.map(\.value).max() ?? 0)
        }
    }
    private let gateStorage = GateBox(SpikeGate(threshold: 20))
    private var gate: SpikeGate {
        get { gateStorage.gate } set { gateStorage.gate = newValue }
    }
}
