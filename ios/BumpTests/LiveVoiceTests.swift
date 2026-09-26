import XCTest
@testable import UWBBumpTest

/// LIVE test of the real `RealtimeVoiceClient` against xAI, through a running
/// BUMP server (which mints the short-lived token). Costs a fraction of a cent.
/// SKIPPED unless configured:
///
///     TEST_RUNNER_BUMP_LIVE_VOICE_URL=http://localhost:8787 \
///     TEST_RUNNER_BUMP_LIVE_VOICE_PCM=/path/to/answer-24k-pcm16.wav \
///     xcodebuild test ... -only-testing:BumpTests/LiveVoiceTests
///
/// Make the clip with:  say -o a.aiff "I study cybersecurity" &&
///                      afconvert -f WAVE -d LEI16@24000 -c 1 a.aiff a.wav
@MainActor
final class LiveVoiceTests: XCTestCase {

    func testRealtimeClientSpeaksListensAndTranscribes() async throws {
        let env = ProcessInfo.processInfo.environment
        guard let raw = env["BUMP_LIVE_VOICE_URL"], let api = BumpAPIClient.resolve(override: raw) else {
            throw XCTSkip("BUMP_LIVE_VOICE_URL not set: live voice test skipped.")
        }
        let session = try await api.voiceSession()
        XCTAssertTrue(session.token.hasPrefix("xai-realtime"), "a short-lived token, not the API key")

        let client = RealtimeVoiceClient()
        var events: [RealtimeEvent] = []
        var closedWith: String?
        client.onEvent = { events.append($0) }
        client.onClose = { closedWith = $0 }
        client.connect(url: URL(string: session.url)!, token: session.token, model: session.model)

        func waitFor(_ seconds: TimeInterval, _ done: () -> Bool) async {
            let end = Date().addingTimeInterval(seconds)
            while !done() && Date() < end { try? await Task.sleep(nanoseconds: 50_000_000) }
        }

        await waitFor(10) { events.contains(.sessionCreated) }
        XCTAssertTrue(events.contains(.sessionCreated), "connected with the token (\(closedWith ?? "no error"))")
        client.send(["type": "session.update", "session": [
            "voice": session.voice, "instructions": VoiceOnboardingModel.instructions,
            "turn_detection": ["type": "server_vad"],
            "audio": ["input": ["format": ["type": "audio/pcm", "rate": 24_000],
                                "transcription": ["model": "grok-transcribe", "language_hint": "en"]],
                      "output": ["format": ["type": "audio/pcm", "rate": 24_000]]],
        ] as [String: Any]])
        await waitFor(5) { events.contains(.sessionUpdated) }

        // Scripted line, spoken verbatim.
        client.send(["type": "conversation.item.create",
                     "item": ["type": "force_message", "role": "assistant", "interruptible": true,
                              "content": [["type": "output_text", "text": VoiceOnboardingModel.openingQuestion]]]])
        await waitFor(10) { events.contains { if case .responseDone = $0 { return true }; return false } }
        let spoken = events.compactMap { if case .assistantText(_, _, let d) = $0 { return d }; return nil }.joined()
        XCTAssertEqual(Grounding.fold(spoken), Grounding.fold(VoiceOnboardingModel.openingQuestion))
        XCTAssertTrue(events.contains { if case .assistantAudio = $0 { return true }; return false }, "Grok's voice arrived")

        // A real spoken answer, if a clip was provided.
        if let path = env["BUMP_LIVE_VOICE_PCM"], let wav = FileManager.default.contents(atPath: path),
           let dataRange = wav.range(of: Data("data".utf8)) {
            let pcm = wav.subdata(in: (dataRange.upperBound + 4)..<wav.count)
            var offset = 0
            while offset < pcm.count {
                let chunk = pcm.subdata(in: offset..<min(offset + 4800, pcm.count))
                client.send(["type": "input_audio_buffer.append", "audio": chunk.base64EncodedString()])
                offset += 4800
                try? await Task.sleep(nanoseconds: 20_000_000)
            }
            for _ in 0..<15 {
                client.send(["type": "input_audio_buffer.append", "audio": Data(count: 4800).base64EncodedString()])
                try? await Task.sleep(nanoseconds: 20_000_000)
            }
            await waitFor(10) { events.contains { if case .userFinal = $0 { return true }; return false } }
            let heard = events.compactMap { if case .userFinal(_, let t) = $0 { return t }; return nil }.last ?? ""
            XCTAssertTrue(heard.lowercased().contains("cybersecurity"), "heard: \(heard)")
        }
        client.close()
    }
}
