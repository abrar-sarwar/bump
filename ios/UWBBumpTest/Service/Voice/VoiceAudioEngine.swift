import AVFoundation
import Foundation

/// Microphone in, Grok's voice out. `VoiceAudioEngine` in the app; a fake in tests.
@MainActor
protocol VoiceAudioIO: AnyObject {
    /// 24 kHz mono PCM16 little-endian chunks from the microphone.
    var onMicChunk: ((Data) -> Void)? { get set }
    /// Fired when everything queued for playback has finished playing.
    var onPlaybackFinished: (() -> Void)? { get set }
    var level: Float { get }
    var isPlaying: Bool { get }
    func start() throws
    func stop()
    func play(_ pcm16: Data)
    /// Stop speaking immediately and drop anything still queued.
    func stopPlayback()
}

/// AVAudioEngine with Apple's voice processing (echo cancellation), so Grok's
/// own voice coming out of the speaker isn't sent back as the user's answer.
/// Nothing is recorded to disk: audio only ever exists as in-memory chunks.
@MainActor
final class VoiceAudioEngine: VoiceAudioIO {
    nonisolated static let sampleRate: Double = 24_000

    var onMicChunk: ((Data) -> Void)?
    var onPlaybackFinished: (() -> Void)?
    private(set) var level: Float = 0
    var isPlaying: Bool { pending > 0 }

    private var engine: AVAudioEngine?
    private var player: AVAudioPlayerNode?
    private var pending = 0
    /// Bumped on every stop, so completions from dropped buffers are ignored.
    private var playbackGeneration = 0

    private let playFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: sampleRate,
                                           channels: 1, interleaved: false)!

    func start() throws {
        stop()
        let session = AVAudioSession.sharedInstance()
        // .voiceChat is what turns on echo cancellation for the input node.
        try session.setCategory(.playAndRecord, mode: .voiceChat, options: [.defaultToSpeaker])
        try session.setActive(true)

        let engine = AVAudioEngine()
        let player = AVAudioPlayerNode()
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: playFormat)
        do {
            try engine.inputNode.setVoiceProcessingEnabled(true)
        } catch {
            // Keep going without it; the app also filters obvious echoes.
        }

        let input = engine.inputNode
        let inputFormat = input.outputFormat(forBus: 0)
        guard inputFormat.sampleRate > 0,
              let converter = MicConverter(from: inputFormat) else {
            throw VoiceAudioError.noMicrophone
        }
        input.installTap(onBus: 0, bufferSize: 2048, format: inputFormat) { [weak self] buffer, _ in
            let rms = MicConverter.rms(buffer)
            guard let pcm = converter.convert(buffer) else { return }
            Task { @MainActor in
                guard let self else { return }
                self.level = self.level * 0.7 + min(1, rms * 8) * 0.3
                self.onMicChunk?(pcm)
            }
        }
        engine.prepare()
        try engine.start()
        player.play()
        self.engine = engine
        self.player = player
    }

    func stop() {
        stopPlayback()
        engine?.inputNode.removeTap(onBus: 0)
        engine?.stop()
        engine = nil
        player = nil
        level = 0
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    func play(_ pcm16: Data) {
        guard let player, let engine, engine.isRunning else { return }
        let frames = pcm16.count / 2
        guard frames > 0, let buffer = AVAudioPCMBuffer(pcmFormat: playFormat, frameCapacity: AVAudioFrameCount(frames)),
              let out = buffer.floatChannelData?[0] else { return }
        buffer.frameLength = AVAudioFrameCount(frames)
        pcm16.withUnsafeBytes { raw in
            let src = raw.bindMemory(to: Int16.self)
            for i in 0..<frames { out[i] = Float(Int16(littleEndian: src[i])) / 32768 }
        }
        pending += 1
        let generation = playbackGeneration
        player.scheduleBuffer(buffer, completionCallbackType: .dataPlayedBack) { [weak self] _ in
            Task { @MainActor in
                guard let self, generation == self.playbackGeneration else { return }
                self.pending = max(0, self.pending - 1)
                if self.pending == 0 { self.onPlaybackFinished?() }
            }
        }
        if !player.isPlaying { player.play() }
    }

    func stopPlayback() {
        playbackGeneration += 1
        let wasPlaying = pending > 0
        pending = 0
        player?.stop()      // drops everything queued
        player?.play()      // ready for the next turn
        if wasPlaying { onPlaybackFinished?() }
    }
}

enum VoiceAudioError: LocalizedError {
    case noMicrophone
    var errorDescription: String? { "The microphone isn't available right now." }
}

/// Converts mic buffers (usually 48 kHz float) to 24 kHz mono PCM16 on the
/// audio thread. One converter for the session, fed exactly one buffer per call.
private final class MicConverter: @unchecked Sendable {
    private let converter: AVAudioConverter
    private let outFormat: AVAudioFormat
    private let ratio: Double

    init?(from input: AVAudioFormat) {
        guard let out = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: VoiceAudioEngine.sampleRate,
                                      channels: 1, interleaved: true),
              let converter = AVAudioConverter(from: input, to: out) else { return nil }
        self.converter = converter
        self.outFormat = out
        self.ratio = VoiceAudioEngine.sampleRate / input.sampleRate
    }

    func convert(_ buffer: AVAudioPCMBuffer) -> Data? {
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 64
        guard let out = AVAudioPCMBuffer(pcmFormat: outFormat, frameCapacity: capacity) else { return nil }
        var fed = false
        var error: NSError?
        converter.convert(to: out, error: &error) { _, status in
            if fed { status.pointee = .noDataNow; return nil }
            fed = true
            status.pointee = .haveData
            return buffer
        }
        guard error == nil, out.frameLength > 0, let samples = out.int16ChannelData?[0] else { return nil }
        return Data(bytes: samples, count: Int(out.frameLength) * 2)
    }

    static func rms(_ buffer: AVAudioPCMBuffer) -> Float {
        guard let data = buffer.floatChannelData?[0], buffer.frameLength > 0 else { return 0 }
        var sum: Float = 0
        for i in 0..<Int(buffer.frameLength) { sum += data[i] * data[i] }
        return (sum / Float(buffer.frameLength)).squareRoot()
    }
}
