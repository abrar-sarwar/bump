import AVFoundation
import Foundation

/// Records the short spoken introduction.
///
/// - 45 second hard cap (`record(forDuration:)`), shown as a countdown.
/// - Microphone permission is asked for only when the person taps record.
/// - Calls, Siri and other interruptions stop the take and say so.
/// - Near-silent or sub-second takes are rejected before anything is uploaded.
/// - The file lives in the temporary directory and is deleted as soon as it has
///   been transcribed, discarded, re-recorded, or this object goes away. Audio is
///   never kept by the app.
@MainActor
final class IntroRecorder: NSObject, ObservableObject {

    static let maxDuration: TimeInterval = 45
    /// Anything quieter than this peak (dBFS) is treated as "we heard nothing".
    static let silenceFloor: Float = -45
    static let minimumDuration: TimeInterval = 1.0

    enum State: Equatable {
        case idle
        case requestingPermission
        case denied
        case recording
        case finished(duration: TimeInterval, interrupted: Bool)
        case failed(String)
    }

    @Published private(set) var state: State = .idle
    @Published private(set) var elapsed: TimeInterval = 0
    /// 0...1, smoothed, for the level meter.
    @Published private(set) var level: Float = 0

    private(set) var fileURL: URL?
    private var recorder: AVAudioRecorder?
    private var meterTimer: Timer?
    private var peak: Float = -160
    private var interrupted = false

    override init() {
        super.init()
        NotificationCenter.default.addObserver(self, selector: #selector(handleInterruption(_:)),
                                               name: AVAudioSession.interruptionNotification, object: nil)
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
        if let url = fileURL { try? FileManager.default.removeItem(at: url) }
    }

    var remaining: TimeInterval { max(0, Self.maxDuration - elapsed) }

    // MARK: Control

    func start() {
        switch AVAudioApplication.shared.recordPermission {
        case .granted:
            begin()
        case .denied:
            state = .denied
        case .undetermined:
            state = .requestingPermission
            AVAudioApplication.requestRecordPermission { granted in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    if granted { self.begin() } else { self.state = .denied }
                }
            }
        @unknown default:
            state = .denied
        }
    }

    func stop() {
        guard state == .recording else { return }
        recorder?.stop()        // delegate finishes the take
    }

    /// Throw the take away and delete the file.
    func discard() {
        recorder?.stop()
        recorder = nil
        stopMetering()
        deleteFile()
        elapsed = 0
        level = 0
        state = .idle
        deactivateSession()
    }

    /// Called once the audio has been transcribed (or the person moved on).
    func deleteFile() {
        if let url = fileURL { try? FileManager.default.removeItem(at: url) }
        fileURL = nil
    }

    // MARK: Internals

    private func begin() {
        deleteFile()
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playAndRecord, mode: .spokenAudio, options: [.defaultToSpeaker])
            try session.setActive(true)
        } catch {
            state = .failed("The microphone isn't available right now. Try again, or type instead.")
            return
        }

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("bump-intro-\(UUID().uuidString).m4a")
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 22_050,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.medium.rawValue,
        ]
        do {
            let recorder = try AVAudioRecorder(url: url, settings: settings)
            recorder.delegate = self
            recorder.isMeteringEnabled = true
            guard recorder.record(forDuration: Self.maxDuration) else {
                deactivateSession()
                state = .failed("Couldn't start recording. Try again, or type instead.")
                return
            }
            self.recorder = recorder
            fileURL = url
            peak = -160
            interrupted = false
            elapsed = 0
            state = .recording
            startMetering()
        } catch {
            deactivateSession()
            state = .failed("Couldn't start recording. Try again, or type instead.")
        }
    }

    private func startMetering() {
        meterTimer?.invalidate()
        meterTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
    }

    private func stopMetering() {
        meterTimer?.invalidate()
        meterTimer = nil
    }

    private func tick() {
        guard let recorder, recorder.isRecording else { return }
        recorder.updateMeters()
        let power = recorder.peakPower(forChannel: 0)
        peak = max(peak, power)
        elapsed = recorder.currentTime
        // Map -50...0 dB to 0...1 and smooth a little.
        let target = max(0, min(1, (power + 50) / 50))
        level = level * 0.6 + target * 0.4
    }

    fileprivate func finish(duration: TimeInterval) {
        stopMetering()
        recorder = nil
        level = 0
        deactivateSession()

        if duration < Self.minimumDuration {
            deleteFile()
            state = .failed(interrupted
                ? "Recording was interrupted before we caught anything. Try again, or type instead."
                : "That was a little short. Try again, or type instead.")
            return
        }
        if peak < Self.silenceFloor {
            deleteFile()
            state = .failed("We couldn't hear anything. Check the mic isn't covered, or type instead.")
            return
        }
        elapsed = duration
        state = .finished(duration: duration, interrupted: interrupted)
    }

    private func deactivateSession() {
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    @objc nonisolated private func handleInterruption(_ note: Notification) {
        guard let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
              AVAudioSession.InterruptionType(rawValue: raw) == .began else { return }
        Task { @MainActor [weak self] in
            guard let self, self.state == .recording else { return }
            self.interrupted = true
            self.recorder?.stop()
        }
    }
}

extension IntroRecorder: AVAudioRecorderDelegate {
    nonisolated func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        let url = recorder.url
        Task { @MainActor [weak self] in
            guard let self, self.fileURL == url else { return }
            // Read the real length from the file; `currentTime` is 0 after stop.
            let duration = (try? AVAudioPlayer(contentsOf: url).duration) ?? self.elapsed
            if flag {
                self.finish(duration: duration)
            } else {
                self.stopMetering()
                self.recorder = nil
                self.deleteFile()
                self.state = .failed("Recording didn't save. Try again, or type instead.")
            }
        }
    }

    nonisolated func audioRecorderEncodeErrorDidOccur(_ recorder: AVAudioRecorder, error: Error?) {
        Task { @MainActor [weak self] in
            self?.stopMetering()
            self?.recorder = nil
            self?.deleteFile()
            self?.state = .failed("Recording failed. Try again, or type instead.")
        }
    }
}
