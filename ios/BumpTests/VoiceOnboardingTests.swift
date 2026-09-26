import XCTest
@testable import UWBBumpTest

// MOCKED: a fake realtime connection replays the event shapes captured from
// the live xAI API, a fake audio engine records what would play, and a stub
// backend answers the BUMP server calls. No network, no microphone.

@MainActor
final class FakeConnection: VoiceConnection {
    var onEvent: ((RealtimeEvent) -> Void)?
    var onClose: ((String) -> Void)?
    private(set) var sent: [[String: Any]] = []
    private(set) var connected = false
    private(set) var closed = false

    func connect(url: URL, token: String, model: String) { connected = true }
    func send(_ json: [String: Any]) { sent.append(json) }
    func close() { closed = true }

    func emit(_ e: RealtimeEvent) { onEvent?(e) }
    func types() -> [String] { sent.compactMap { $0["type"] as? String } }
    /// Texts spoken with force_message, in order.
    func forced() -> [String] {
        sent.compactMap { msg -> String? in
            guard let item = msg["item"] as? [String: Any], item["type"] as? String == "force_message",
                  let content = item["content"] as? [[String: Any]] else { return nil }
            return content.first?["text"] as? String
        }
    }
    func cancels() -> Int { types().filter { $0 == "response.cancel" }.count }
}

@MainActor
final class FakeAudio: VoiceAudioIO {
    var onMicChunk: ((Data) -> Void)?
    var onPlaybackFinished: (() -> Void)?
    var level: Float = 0
    private(set) var played = 0
    private(set) var stops = 0
    private(set) var running = false
    var isPlaying: Bool { queued > 0 }
    private var queued = 0

    func start() throws { running = true }
    func stop() { running = false; queued = 0 }
    func play(_ pcm16: Data) { played += 1; queued += 1 }
    func stopPlayback() { stops += 1; queued = 0 }
    func finishPlaying() { queued = 0; onPlaybackFinished?() }
}

final class StubVoiceBackend: VoiceBackend, @unchecked Sendable {
    var sessionResult: Result<BumpAPIClient.VoiceSession, BumpAPIError> =
        .success(.init(token: "temp-token", expiresAt: 0, url: "wss://example.invalid/v1/realtime", model: "grok-voice-latest", voice: "eve"))
    var draftResult: Result<BumpAPIClient.Draft, BumpAPIError> = .failure(.offline)
    var reviseResult: Result<BumpAPIClient.Revision, BumpAPIError> = .failure(.offline)
    var reviseDelay: TimeInterval = 0
    private(set) var draftedText: String?
    private(set) var revised: [String] = []

    func voiceSession() async throws -> BumpAPIClient.VoiceSession { try sessionResult.get() }
    func draft(transcript: String) async throws -> BumpAPIClient.Draft {
        draftedText = transcript
        return try draftResult.get()
    }
    func revise(items: [(id: String, kind: ProfileFact.Kind, label: String)], utterance: String) async throws -> BumpAPIClient.Revision {
        revised.append(utterance)
        if reviseDelay > 0 { try await Task.sleep(nanoseconds: UInt64(reviseDelay * 1e9)) }
        return try reviseResult.get()
    }
}

private let grok = BumpAPIClient.Generator(provider: "xai", model: "grok-test")
private func fact(_ label: String, _ source: String) -> BumpAPIClient.ProposedFact {
    .init(kind: "interest", label: label, source: source)
}

@MainActor
final class VoiceOnboardingTests: XCTestCase {

    private var clock = Date(timeIntervalSince1970: 1_000)
    private var conn: FakeConnection!
    private var audio: FakeAudio!
    private var backend: StubVoiceBackend!
    private var store: Store!
    private var model: VoiceOnboardingModel!
    private var responseSeq = 0
    private var itemSeq = 0

    override func setUp() async throws {
        conn = FakeConnection()
        audio = FakeAudio()
        backend = StubVoiceBackend()
        store = Store(inMemory: true)
        let onboarding = OnboardingModel(store: store)
        onboarding.name = "Sam"
        let backend = self.backend!
        model = VoiceOnboardingModel(onboarding: onboarding, backend: { backend },
                                     makeConnection: { [unowned self] in self.conn },
                                     audio: audio, requestMic: { true },
                                     now: { [unowned self] in self.clock })
        model.settleDelay = 0.02
    }

    // MARK: Helpers

    private func wait(_ seconds: TimeInterval = 0.08) async {
        try? await Task.sleep(nanoseconds: UInt64(seconds * 1e9))
    }

    /// Start, connect, and let the opening question play.
    private func startConversation() async {
        model.start()
        await wait()
        conn.emit(.sessionCreated)
        conn.emit(.sessionUpdated)
        bumpSays("Tell me a little about yourself. What do you enjoy doing?")
    }

    @discardableResult
    private func bumpSays(_ text: String) -> String {
        responseSeq += 1
        let r = "resp_\(responseSeq)", item = "bump_\(responseSeq)"
        conn.emit(.responseCreated(responseID: r))
        conn.emit(.assistantText(responseID: r, itemID: item, delta: text))
        conn.emit(.assistantAudio(responseID: r, pcm: Data(count: 480)))
        conn.emit(.responseDone(responseID: r, status: "completed"))
        audio.finishPlaying()
        return r
    }

    /// The user answers: speech starts, captions stream, finals arrive (twice,
    /// like the live API), then the server may start a reply.
    @discardableResult
    private func userSays(_ text: String, partial: String? = nil) async -> String {
        itemSeq += 1
        let item = "user_\(itemSeq)"
        conn.emit(.speechStarted(itemID: item))
        if let partial { conn.emit(.userPartial(itemID: item, text: partial)) }
        conn.emit(.userFinal(itemID: item, text: String(text.prefix(text.count / 2))))
        conn.emit(.speechStopped(itemID: item))
        conn.emit(.userFinal(itemID: item, text: text))
        conn.emit(.committed(itemID: item))
        conn.emit(.userFinal(itemID: item, text: text))
        await wait()
        return item
    }

    // MARK: Tests

    func testOpeningIsSpokenVerbatimAndCountsAsQuestionOne() async {
        await startConversation()
        XCTAssertEqual(model.phase, .conversation)
        XCTAssertEqual(conn.forced().first, VoiceOnboardingModel.openingQuestion)
        XCTAssertEqual(model.questionsAsked, 1)
        XCTAssertEqual(model.lines.first?.speaker, .bump)
        XCTAssertTrue(audio.running, "mic starts only once the session is configured")
        // The session config keeps server turn detection and live captions on.
        let update = conn.sent.first { $0["type"] as? String == "session.update" }?["session"] as? [String: Any]
        XCTAssertEqual((update?["turn_detection"] as? [String: Any])?["type"] as? String, "server_vad")
        XCTAssertNotNil(update?["instructions"])
    }

    func testTranscriptUpdatesWithoutDuplicateTurns() async {
        await startConversation()
        await userSays("I study cybersecurity, play games, and go to concerts.", partial: "I study cyber")
        let mine = model.lines.filter { $0.speaker == .you }
        XCTAssertEqual(mine.count, 1, "partials and repeated finals replace one line")
        XCTAssertEqual(mine.first?.text, "I study cybersecurity, play games, and go to concerts.")
        XCTAssertTrue(mine.first?.isFinal ?? false)
    }

    func testThreeQuestionsThenReviewWithGrokSilencedByTheApp() async {
        backend.draftResult = .success(.init(bio: nil, facts: [
            fact("Cybersecurity", "I study cybersecurity"), fact("Valorant", "Valorant"), fact("House music", "house music"),
        ], question: nil, generator: grok))
        await startConversation()
        await userSays("I study cybersecurity, play games, and go to concerts.")
        bumpSays("Nice. What games or artists have you been into lately?")
        XCTAssertEqual(model.questionsAsked, 2)
        await userSays("Mostly Valorant and house music.")
        bumpSays("What would you enjoy finding someone to do together?")
        XCTAssertEqual(model.questionsAsked, 3)

        let playedBefore = audio.played
        await userSays("Going to shows together.")
        // The server tries to reply to the third answer: the app cancels it.
        conn.emit(.responseCreated(responseID: "extra"))
        conn.emit(.assistantAudio(responseID: "extra", pcm: Data(count: 480)))
        conn.emit(.assistantText(responseID: "extra", itemID: "extra_item", delta: "And what else?"))
        XCTAssertGreaterThanOrEqual(conn.cancels(), 1)
        XCTAssertEqual(audio.played, playedBefore, "a blocked reply never plays")
        XCTAssertFalse(model.lines.contains { $0.text.contains("And what else") })
        await wait(0.15)

        XCTAssertEqual(model.phase, .review)
        XCTAssertEqual(model.questionsAsked, 3, "never more than three")
        // Extraction used only the person's words.
        XCTAssertEqual(backend.draftedText, "I study cybersecurity, play games, and go to concerts. Mostly Valorant and house music. Going to shows together.")
        XCTAssertFalse(backend.draftedText?.contains("What games") ?? true)
        XCTAssertTrue(conn.forced().contains { $0.hasPrefix("I've got cybersecurity, Valorant, and house music.") && $0.hasSuffix("Does that sound right?") })
        XCTAssertTrue(store.profile.displayName.isEmpty, "nothing saved before confirmation")
    }

    func testSpokenCorrectionAppliesThenNeedsConfirmation() async {
        backend.draftResult = .success(.init(bio: nil, facts: [fact("Valorant", "Valorant")], question: nil, generator: grok))
        await startConversation()
        await userSays("I play Valorant.")
        model.done()
        await wait(0.1)
        XCTAssertEqual(model.phase, .review)
        let id = model.onboarding.items.first { $0.text == "Valorant" }!.id
        backend.reviseResult = .success(.init(intent: "correct", remove: [],
                                              rename: [.init(id: id, label: "Overwatch")], add: [], generator: grok))
        await userSays("Actually, change Valorant to Overwatch.")
        await wait(0.1)
        XCTAssertTrue(model.onboarding.items.contains { $0.text == "Overwatch" })
        XCTAssertTrue(conn.forced().last?.hasPrefix("Updated.") ?? false)
        XCTAssertTrue(store.profile.displayName.isEmpty, "a correction is not a confirmation")

        await userSays("Yes, that's right.")
        await wait(0.1)
        XCTAssertEqual(model.phase, .saved)
        XCTAssertEqual(store.profile.interests.first?.label, "Overwatch")
        XCTAssertTrue(conn.closed && !audio.running, "mic and socket stop once saved")
    }

    func testLateCorrectionIsIgnoredAfterAManualEdit() async {
        await startConversation()
        model.done()
        await wait(0.1)
        model.onboarding.add(.interest, "Chess")
        let id = model.onboarding.items.first!.id
        backend.reviseDelay = 0.2
        backend.reviseResult = .success(.init(intent: "correct", remove: [id], rename: [], add: [], generator: grok))
        await userSays("Remove chess.")
        model.onboarding.add(.interest, "Coffee")       // the person edits by hand meanwhile
        await wait(0.35)
        XCTAssertTrue(model.onboarding.items.contains { $0.text == "Chess" }, "the late correction didn't land")
    }

    func testBargeInStopsPlaybackAndDropsTheRest() async {
        await startConversation()
        conn.emit(.responseCreated(responseID: "long"))
        conn.emit(.assistantText(responseID: "long", itemID: "long_item", delta: "So tell me"))
        conn.emit(.assistantAudio(responseID: "long", pcm: Data(count: 480)))
        XCTAssertEqual(model.activity, .speaking)
        let stops = audio.stops
        conn.emit(.speechStarted(itemID: "interrupt"))
        XCTAssertEqual(audio.stops, stops + 1)
        XCTAssertEqual(model.activity, .listening)
        let played = audio.played
        conn.emit(.assistantAudio(responseID: "long", pcm: Data(count: 480)))
        conn.emit(.assistantText(responseID: "long", itemID: "long_item", delta: " more about that"))
        XCTAssertEqual(audio.played, played, "queued audio from the interrupted turn is dropped")
        XCTAssertFalse(model.lines.contains { $0.text.contains("more about that") })
    }

    func testStopButtonInterruptsGrok() async {
        await startConversation()
        conn.emit(.responseCreated(responseID: "r"))
        conn.emit(.assistantAudio(responseID: "r", pcm: Data(count: 480)))
        model.interrupt()
        XCTAssertEqual(conn.types().last, "response.cancel")
        XCTAssertEqual(model.activity, .listening)
    }

    func testImDoneJumpsToReview() async {
        await startConversation()
        await userSays("I like climbing.")
        model.done()
        await wait(0.1)
        XCTAssertEqual(model.phase, .review)
        XCTAssertEqual(backend.draftedText, "I like climbing.")
    }

    func testWrapUpAt90SecondsMakesTheNextAnswerTheLast() async {
        await startConversation()
        clock.addTimeInterval(91)
        model.tick()
        XCTAssertEqual(model.phase, .conversation, "90 s only starts wrapping up")
        await userSays("I also like hiking.")
        conn.emit(.responseCreated(responseID: "late"))
        conn.emit(.assistantText(responseID: "late", itemID: "late_item", delta: "Cool! What else do you do?"))
        XCTAssertGreaterThanOrEqual(conn.cancels(), 1)
        await wait(0.1)
        XCTAssertEqual(model.phase, .review)
    }

    func testHardStopAt120Seconds() async {
        await startConversation()
        clock.addTimeInterval(121)
        model.tick()
        await wait(0.1)
        XCTAssertEqual(model.phase, .review)
        XCTAssertNotNil(model.notice)
    }

    func testMicDeniedOffersTyping() async {
        let backend = self.backend!
        let denied = VoiceOnboardingModel(onboarding: OnboardingModel(store: store), backend: { backend },
                                          makeConnection: { [unowned self] in self.conn }, audio: audio,
                                          requestMic: { false })
        denied.start()
        await wait()
        XCTAssertEqual(denied.phase, .micDenied)
        XCTAssertFalse(conn.connected, "no connection without the mic")
        denied.typeInstead()
        XCTAssertTrue(denied.onboarding.typing)
    }

    func testMissingKeyAndConnectionDropKeepAnswersAndRetryReplaysThem() async {
        backend.sessionResult = .failure(.notConfigured)
        model.start()
        await wait()
        guard case .failed(let msg) = model.phase else { return XCTFail("expected failure") }
        XCTAssertTrue(msg.contains("no xAI key"))

        backend.sessionResult = StubVoiceBackend().sessionResult
        model.retry()
        await wait()
        conn.emit(.sessionCreated); conn.emit(.sessionUpdated)
        bumpSays(VoiceOnboardingModel.openingQuestion)
        await userSays("I study cybersecurity.")
        conn.onClose?("The voice connection dropped.")
        guard case .failed = model.phase else { return XCTFail("expected failure after drop") }
        XCTAssertTrue(model.lines.contains { $0.text == "I study cybersecurity." }, "answers are kept")

        let sentBefore = conn.sent.count
        model.retry()
        await wait()
        conn.emit(.sessionCreated); conn.emit(.sessionUpdated)
        let replay = conn.sent.dropFirst(sentBefore).compactMap { ($0["item"] as? [String: Any])?["role"] as? String }
        XCTAssertTrue(replay.contains("user"), "history is replayed to Grok")
        XCTAssertEqual(conn.types().last, "response.create", "Grok continues with its next question")
    }

    func testTypeInsteadKeepsWhatWasSaid() async {
        await startConversation()
        await userSays("I go to concerts.")
        model.typeInstead()
        XCTAssertTrue(model.onboarding.typing)
        XCTAssertEqual(model.onboarding.transcript, "I go to concerts.")
        XCTAssertTrue(conn.closed && !audio.running)
    }

    func testExtractionFailureFallsBackToEditableCard() async {
        backend.draftResult = .failure(.timeout)
        await startConversation()
        await userSays("I love hip hop and coffee.")
        model.done()
        await wait(0.1)
        XCTAssertEqual(model.phase, .review)
        XCTAssertTrue(model.onboarding.items.allSatisfy { $0.origin == .onPhone })
        XCTAssertTrue(model.onboarding.items.contains { $0.text == "Coffee" })
        XCTAssertNotNil(model.onboarding.notice)
    }

    func testEchoOfBumpIsNotTakenAsAnAnswer() async {
        await startConversation()
        conn.emit(.responseCreated(responseID: "q"))
        conn.emit(.assistantText(responseID: "q", itemID: "q_item", delta: "What games have you been into lately?"))
        conn.emit(.assistantAudio(responseID: "q", pcm: Data(count: 480)))
        conn.emit(.userFinal(itemID: "echo", text: "games have you been into lately"))
        XCTAssertFalse(model.lines.contains { $0.id == "echo" })
    }

    func testMutedAndTapToTalkGateTheMic() async {
        await startConversation()
        let before = conn.types().filter { $0 == "input_audio_buffer.append" }.count
        model.muted = true
        audio.onMicChunk?(Data(count: 100))
        model.muted = false
        model.tapToTalk = true
        audio.onMicChunk?(Data(count: 100))
        XCTAssertEqual(conn.types().filter { $0 == "input_audio_buffer.append" }.count, before, "no audio while muted or not holding")
        model.holdingToTalk = true
        audio.onMicChunk?(Data(count: 100))
        XCTAssertEqual(conn.types().filter { $0 == "input_audio_buffer.append" }.count, before + 1)
    }

    func testLeavingTheAppStopsMicAndPlayback() async {
        await startConversation()
        model.suspend()
        XCTAssertFalse(audio.running)
        XCTAssertTrue(conn.closed)
        guard case .failed = model.phase else { return XCTFail("expected paused state") }
    }

    func testPlainYesDetection() {
        XCTAssertTrue(VoiceOnboardingModel.isPlainYes("Yes."))
        XCTAssertTrue(VoiceOnboardingModel.isPlainYes("Yeah, that's right"))
        XCTAssertFalse(VoiceOnboardingModel.isPlainYes("Yes but change Valorant"))
        XCTAssertFalse(VoiceOnboardingModel.isPlainYes("No"))
        XCTAssertFalse(VoiceOnboardingModel.isPlainYes("I also like techno"))
    }

    func testParserMatchesLivePayloads() {
        // Shapes captured from the live xAI realtime API during development.
        XCTAssertEqual(RealtimeEvent.parse(["type": "conversation.item.input_audio_transcription.updated",
                                            "item_id": "i1", "transcript": "Hello, how are"]),
                       .userPartial(itemID: "i1", text: "Hello, how are"))
        XCTAssertEqual(RealtimeEvent.parse(["type": "conversation.item.input_audio_transcription.completed",
                                            "item_id": "i1", "transcript": "Hello, how are you?"]),
                       .userFinal(itemID: "i1", text: "Hello, how are you?"))
        XCTAssertEqual(RealtimeEvent.parse(["type": "response.output_audio_transcript.delta",
                                            "response_id": "r1", "item_id": "m1", "delta": "Hi"]),
                       .assistantText(responseID: "r1", itemID: "m1", delta: "Hi"))
        XCTAssertEqual(RealtimeEvent.parse(["type": "response.created", "response": ["id": "r1"]]), .responseCreated(responseID: "r1"))
        XCTAssertEqual(RealtimeEvent.parse(["type": "response.done", "response": ["id": "r1", "status": "cancelled"]]),
                       .responseDone(responseID: "r1", status: "cancelled"))
        XCTAssertEqual(RealtimeEvent.parse(["type": "response.output_audio.delta", "response_id": "r1",
                                            "delta": Data([1, 0, 2, 0]).base64EncodedString()]),
                       .assistantAudio(responseID: "r1", pcm: Data([1, 0, 2, 0])))
        XCTAssertNil(RealtimeEvent.parse(["type": "response.content_part.added"]))
    }

    func testExistingSavedProfilesStillLoad() throws {
        let old = #"{"displayName":"Ada","bio":"hi","interests":[{"id":"chess","label":"Chess","parent":"games","specificity":2,"custom":false}]}"#
        let profile = try JSONDecoder().decode(Profile.self, from: Data(old.utf8))
        XCTAssertTrue(profile.isComplete)
    }
}
