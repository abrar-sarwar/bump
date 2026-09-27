import AVFoundation

/// Reads onboarding questions aloud: Grok's voice through the BUMP server when
/// cloud processing is allowed, otherwise (or if that is slow or fails) the
/// built-in iOS voice on the phone.
@MainActor
final class QuestionVoice {
    private let synth = AVSpeechSynthesizer()
    private var player: AVAudioPlayer?
    private var fetch: Task<Void, Never>?

    func speak(_ text: String, using grok: OnboardingSpeech? = nil) {
        stop()
        activatePlayback()
        guard let grok else { return speakOnPhone(text) }
        fetch = Task { [weak self] in
            do {
                let audio = try await grok.speech(text: text, timeout: 3)
                guard let self, !Task.isCancelled else { return }
                let player = try AVAudioPlayer(data: audio)
                self.player = player
                player.play()
            } catch {
                guard let self, !Task.isCancelled else { return }
                self.speakOnPhone(text)
            }
        }
    }

    func stop() {
        fetch?.cancel(); fetch = nil
        player?.stop(); player = nil
        if synth.isSpeaking { synth.stopSpeaking(at: .immediate) }
    }

    private func activatePlayback() {
        let session = AVAudioSession.sharedInstance()
        // Playback, not the recorder's playAndRecord: that routes to the quiet
        // earpiece. Ducks rather than stops whatever else is playing.
        try? session.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
        try? session.setActive(true)
    }

    private func speakOnPhone(_ text: String) {
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = Self.bestVoice()
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 1.02
        synth.speak(utterance)
    }

    /// The highest-quality installed voice for the current language.
    private static func bestVoice() -> AVSpeechSynthesisVoice? {
        let lang = AVSpeechSynthesisVoice.currentLanguageCode()
        let voices = AVSpeechSynthesisVoice.speechVoices().filter { $0.language == lang }
        return voices.max { $0.quality.rawValue < $1.quality.rawValue }
            ?? AVSpeechSynthesisVoice(language: lang)
    }
}
