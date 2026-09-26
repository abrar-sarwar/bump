import AVFoundation
import Foundation

/// What spoken onboarding needs from the BUMP server. `BumpAPIClient` in the
/// app; a stub in tests.
protocol VoiceBackend: Sendable {
    func voiceSession() async throws -> BumpAPIClient.VoiceSession
    func draft(transcript: String) async throws -> BumpAPIClient.Draft
    func revise(items: [(id: String, kind: ProfileFact.Kind, label: String)], utterance: String) async throws -> BumpAPIClient.Revision
}

extension BumpAPIClient: VoiceBackend {}

/// A short spoken interview with Grok that becomes a draft Bump card.
///
/// Grok speaks, listens, and asks up to `maxQuestions` questions (the opening
/// one included). The app, not the prompt, enforces that: once the budget is
/// used, or time is up, any reply Grok starts is cancelled before it plays.
/// Then Grok reads a summary, the card appears, and the person confirms or
/// corrects it by voice or by hand. Nothing is saved until they confirm.
///
/// Voice turns are detected by the server (server VAD). Exact lines (the
/// opening question, the closing line, the summary) are spoken with xAI's
/// `force_message`, so they are never improvised.
@MainActor
final class VoiceOnboardingModel: ObservableObject {

    // MARK: Tunables

    static let maxQuestions = 3
    static let wrapUpAfter: TimeInterval = 90
    static let hardStopAfter: TimeInterval = 120
    static let openingQuestion = "Tell me a little about yourself. What do you enjoy doing?"
    static let closingLine = "Thanks! Let me put your card together."

    // MARK: State

    enum Phase: Equatable {
        case idle               // start screen
        case connecting
        case conversation
        case building           // turning answers into a card
        case review             // editable card + spoken confirmation
        case saved
        case micDenied
        case failed(String)     // with Retry / Type instead
    }

    /// What the voice indicator shows.
    enum Activity: Equatable { case idle, listening, thinking, speaking }

    struct Line: Identifiable, Equatable {
        enum Speaker: Equatable { case you, bump }
        let id: String          // the realtime item id, so updates replace instead of duplicating
        let speaker: Speaker
        var text: String
        var isFinal: Bool
    }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var activity: Activity = .idle
    @Published private(set) var lines: [Line] = []
    @Published private(set) var questionsAsked = 0
    @Published private(set) var elapsed: TimeInterval = 0
    @Published private(set) var notice: String?
    @Published var muted = false
    /// Tap-to-talk for noisy rooms: the mic only sends while `holdingToTalk`.
    @Published var tapToTalk = false
    @Published var holdingToTalk = false

    var level: Float { audio.level }
    var wrappingUp: Bool { elapsed >= Self.wrapUpAfter }

    let onboarding: OnboardingModel

    // MARK: Collaborators

    private let backend: () -> VoiceBackend?
    private let makeConnection: () -> VoiceConnection
    private let audio: VoiceAudioIO
    private let requestMic: () async -> Bool
    private let now: () -> Date
    /// How long a user turn must be quiet before it's treated as final. The
    /// server can send several "completed" transcripts for one turn.
    var settleDelay: TimeInterval = 0.8

    private var connection: VoiceConnection?
    private var session: BumpAPIClient.VoiceSession?
    private var startedAt: Date?
    private var ticker: Timer?
    private var generation = 0          // bumps on every stop; late callbacks are dropped
    private var work: Task<Void, Never>?

    // Response bookkeeping
    /// Exact lines we asked Grok to say (force_message), oldest first.
    private var expectedLines: [String] = []
    /// Replies held silently until their first words show whether they are our
    /// scripted line or Grok improvising. Buffered audio plays only if verified.
    private var holding: [String: (text: String, audio: [Data])] = [:]
    private var allowedResponses: Set<String> = []
    private var blockedResponses: Set<String> = []
    private var interruptedResponses: Set<String> = []
    private var currentResponse: String?
    private var responseLine: [String: String] = [:]   // response id → line id

    // Turn bookkeeping
    private var lastAnswerStarted = false        // the answer in progress is the final one
    private var settleTimers: [String: Timer] = [:]
    private var settled: Set<String> = []
    private var lastBumpText = ""
    private var bumpFinishedAt: Date?
    private var reviewBusy = false

    init(onboarding: OnboardingModel,
         backend: (() -> VoiceBackend?)? = nil,
         makeConnection: (() -> VoiceConnection)? = nil,
         audio: VoiceAudioIO? = nil,
         requestMic: (() async -> Bool)? = nil,
         now: @escaping () -> Date = Date.init) {
        self.onboarding = onboarding
        self.backend = backend ?? { BumpAPIClient.resolve(override: onboarding.apiOverride) }
        self.makeConnection = makeConnection ?? { RealtimeVoiceClient() }
        self.audio = audio ?? VoiceAudioEngine()
        self.requestMic = requestMic ?? VoiceOnboardingModel.systemMicPermission
        self.now = now
        self.audio.onMicChunk = { [weak self] pcm in self?.micChunk(pcm) }
        self.audio.onPlaybackFinished = { [weak self] in self?.playbackFinished() }
    }

    // MARK: Start / stop

    /// "Start talking": consent is implied by the notice on the start screen.
    func start() {
        guard phase == .idle || isFailed || phase == .micDenied else { return }
        onboarding.chooseCloud(true)
        notice = nil
        let g = bumpGeneration()
        work = Task { [weak self] in
            guard let self else { return }
            guard await self.requestMic() else {
                guard g == self.generation else { return }
                self.phase = .micDenied
                return
            }
            guard g == self.generation else { return }
            await self.connect(generation: g)
        }
    }

    private func connect(generation g: Int) async {
        phase = .connecting
        expectedLines.removeAll()
        holding.removeAll()
        activity = .idle
        guard let api = backend() else {
            phase = .failed("Voice needs the BUMP server, and this phone isn't set up to reach it. Type instead, or set the server in Testing tools.")
            return
        }
        do {
            let session = try await withDeadline(10) { try await api.voiceSession() }
            guard g == generation else { return }
            guard let url = URL(string: session.url) else { throw BumpAPIError.invalidResponse }
            self.session = session
            let connection = makeConnection()
            connection.onEvent = { [weak self] event in
                guard let self, g == self.generation else { return }
                self.handle(event)
            }
            connection.onClose = { [weak self] message in
                guard let self, g == self.generation else { return }
                self.connectionLost(message)
            }
            self.connection = connection
            connection.connect(url: url, token: session.token, model: session.model)
        } catch {
            guard g == generation else { return }
            phase = .failed(Self.message(for: BumpAPIError.map(error)))
        }
    }

    /// Stop everything: mic, playback, socket, timers. Safe to call twice.
    func stop() {
        bumpGeneration()
        work?.cancel(); work = nil
        ticker?.invalidate(); ticker = nil
        settleTimers.values.forEach { $0.invalidate() }
        settleTimers.removeAll()
        connection?.close(); connection = nil
        audio.stop()
        activity = .idle
        holdingToTalk = false
    }

    /// Leaving the screen or the app mid-interview.
    func suspend(reason: String = "Voice paused because you left the app.") {
        guard phase == .connecting || phase == .conversation || phase == .review else { return }
        let wasReview = phase == .review
        stop()
        phase = wasReview ? .review : .failed(reason)
        if wasReview { notice = "Voice paused. You can still edit and save your card." }
    }

    /// Reconnect after a failure. Everything said so far is kept and replayed
    /// to Grok as history, so it picks up where it left off.
    func retry() {
        guard isFailed else { return }
        start()
    }

    /// Leave voice for the typed flow, keeping what was said.
    func typeInstead() {
        stop()
        let said = userText
        if !said.isEmpty { onboarding.rememberVoiceAnswers(said) }
        onboarding.transcript = said
        onboarding.typing = true
        onboarding.step = .intro
        phase = .idle
    }

    /// "I'm done": skip straight to the card.
    func done() {
        guard phase == .conversation else { return }
        finishDiscovery(speakClosing: false)
    }

    /// Cut Grok off mid-sentence (the "Stop" control, or barge-in).
    func interrupt() {
        guard let id = currentResponse, activity == .speaking || activity == .thinking else { return }
        interruptedResponses.insert(id)
        connection?.send(["type": "response.cancel"])
        audio.stopPlayback()
        activity = .listening
    }

    // MARK: Mic

    private func micChunk(_ pcm: Data) {
        guard canSendAudio else { return }
        connection?.send(["type": "input_audio_buffer.append", "audio": pcm.base64EncodedString()])
    }

    private var canSendAudio: Bool {
        guard connection != nil, !muted, phase == .conversation || phase == .review else { return false }
        if tapToTalk && !holdingToTalk { return false }
        return true
    }

    /// Tap-to-talk release: send a moment of silence so the server ends the turn.
    func releaseTalk() {
        guard holdingToTalk else { return }
        holdingToTalk = false
        let silence = Data(count: Int(VoiceAudioEngine.sampleRate) * 2 / 10)   // 100 ms
        for _ in 0..<8 { connection?.send(["type": "input_audio_buffer.append", "audio": silence.base64EncodedString()]) }
    }

    // MARK: Events

    func handle(_ event: RealtimeEvent) {
        switch event {
        case .sessionCreated:
            guard phase == .connecting else { return }
            connection?.send(sessionConfig())

        case .sessionUpdated:
            guard phase == .connecting else { return }
            beginConversation()

        case .speechStarted:
            // Barge-in: the person started talking, so Grok stops.
            if activity == .speaking || activity == .thinking, let id = currentResponse {
                interruptedResponses.insert(id)
                audio.stopPlayback()
            }
            activity = .listening
            if phase == .conversation && (questionsAsked >= Self.maxQuestions || wrappingUp) {
                lastAnswerStarted = true
            }

        case .speechStopped:
            if phase == .conversation || phase == .review { activity = .thinking }

        case .committed:
            break

        case .userPartial(let item, let text):
            guard !settled.contains(item) else { return }
            upsert(Line(id: item, speaker: .you, text: text, isFinal: false))

        case .userFinal(let item, let text):
            guard !settled.contains(item) else { return }
            let clean = text.trimmed()
            if clean.isEmpty || isEcho(clean) {
                lines.removeAll { $0.id == item }
                return
            }
            upsert(Line(id: item, speaker: .you, text: clean, isFinal: true))
            scheduleSettle(item)

        case .responseCreated(let id):
            if replyAllowed {
                allowedResponses.insert(id)
            } else if !expectedLines.isEmpty {
                holding[id] = ("", [])           // decide once its first words arrive
            } else {
                // Budget used, time up, or reviewing: Grok doesn't get a turn.
                blockedResponses.insert(id)
                connection?.send(["type": "response.cancel"])
                return
            }
            currentResponse = id
            activity = .thinking

        case .assistantText(let response, let item, let delta):
            if holding[response] != nil {
                holding[response]!.text += delta
                verifyHeld(response, itemID: item)
                return
            }
            guard isLive(response) else { return }
            responseLine[response] = item
            if let i = lines.firstIndex(where: { $0.id == item }) {
                lines[i].text += delta
            } else {
                lines.append(Line(id: item, speaker: .bump, text: delta, isFinal: false))
            }
            // A scripted line spoken while replies were allowed: cross it off.
            if let expected = expectedLines.first, let text = lines.first(where: { $0.id == item })?.text,
               Grounding.fold(text).count >= min(12, Grounding.fold(expected).count),
               Grounding.fold(expected).hasPrefix(Grounding.fold(text)) {
                expectedLines.removeFirst()
            }

        case .assistantAudio(let response, let pcm):
            if holding[response] != nil { holding[response]!.audio.append(pcm); return }
            guard isLive(response) else { return }
            audio.play(pcm)
            activity = .speaking

        case .responseDone(let response, let status):
            if holding[response] != nil {
                // Finished before we could tell: only a scripted line may play.
                blockedResponses.insert(response)
                holding[response] = nil
            }
            let lineID = responseLine[response]
            if let lineID, let i = lines.firstIndex(where: { $0.id == lineID }) {
                if interruptedResponses.contains(response) || blockedResponses.contains(response) {
                    // Keep what was actually heard, but mark it as cut off.
                    if lines[i].text.trimmed().isEmpty { lines.remove(at: i) } else { lines[i].isFinal = true }
                } else {
                    lines[i].isFinal = true
                    lastBumpText = lines[i].text
                    if phase == .conversation, status == "completed", lines[i].text.contains("?"),
                       allowedResponses.contains(response), !isScripted(lines[i].text) {
                        questionsAsked += 1
                    }
                }
            }
            if currentResponse == response { currentResponse = nil }
            if !audio.isPlaying && activity != .listening { activity = .listening }

        case .ping:
            break

        case .error(let message):
            // Most realtime errors are recoverable; show them without stopping.
            notice = message
        }
    }

    /// A held reply is ours if its words so far are the start of the next
    /// scripted line. Otherwise Grok is improvising when it shouldn't: cancel.
    private func verifyHeld(_ response: String, itemID: String) {
        guard let held = holding[response], let expected = expectedLines.first else { return }
        let said = Grounding.fold(held.text)
        guard !said.isEmpty else { return }
        let target = Grounding.fold(expected)
        if target.hasPrefix(said) || said.hasPrefix(target) {
            guard said.count >= min(12, target.count) else { return }   // enough words to be sure
            holding[response] = nil
            expectedLines.removeFirst()
            allowedResponses.insert(response)
            currentResponse = response
            responseLine[response] = itemID
            lines.append(Line(id: itemID, speaker: .bump, text: held.text, isFinal: false))
            held.audio.forEach { audio.play($0) }
            if !held.audio.isEmpty { activity = .speaking }
        } else {
            holding[response] = nil
            blockedResponses.insert(response)
            connection?.send(["type": "response.cancel"])
        }
    }

    private var replyAllowed: Bool {
        phase == .conversation && !lastAnswerStarted && questionsAsked < Self.maxQuestions && !wrappingUp
    }

    private func isLive(_ response: String) -> Bool {
        allowedResponses.contains(response) && !blockedResponses.contains(response)
            && !interruptedResponses.contains(response)
    }

    private func isScripted(_ text: String) -> Bool {
        let t = Grounding.fold(text)
        return t == Grounding.fold(Self.openingQuestion) || t == Grounding.fold(Self.closingLine)
            || t.hasPrefix(Grounding.fold("I've got")) || t.hasPrefix(Grounding.fold("I didn't catch"))
            || t.hasPrefix("updated")
    }

    /// Grok's own voice picked up by the mic. Voice processing should stop
    /// this; this is the backstop.
    private func isEcho(_ text: String) -> Bool {
        let heard = Grounding.fold(text)
        guard heard.count >= 8 else { return false }
        let recentlySpeaking = activity == .speaking || audio.isPlaying
            || (bumpFinishedAt.map { now().timeIntervalSince($0) < 1.5 } ?? false)
        guard recentlySpeaking else { return false }
        let current = currentResponse.flatMap { responseLine[$0] }.flatMap { id in lines.first { $0.id == id }?.text } ?? ""
        return [lastBumpText, current].contains { Grounding.fold($0).contains(heard) }
    }

    private func upsert(_ line: Line) {
        if let i = lines.firstIndex(where: { $0.id == line.id }) {
            lines[i].text = line.text
            lines[i].isFinal = line.isFinal
        } else {
            lines.append(line)
        }
    }

    private func playbackFinished() {
        bumpFinishedAt = now()
        if activity == .speaking { activity = .listening }
    }

    // MARK: Conversation

    private func beginConversation() {
        do {
            try audio.start()
        } catch {
            phase = .failed("The microphone isn't available right now. Try again, or type instead.")
            connection?.close()
            return
        }
        let resuming = !lines.isEmpty
        phase = .conversation
        if startedAt == nil { startedAt = now() }
        startTicker()
        if resuming {
            seedHistory()
            if questionsAsked >= Self.maxQuestions || wrappingUp {
                finishDiscovery(speakClosing: false)
            } else {
                connection?.send(["type": "response.create"])
            }
        } else {
            speak(Self.openingQuestion)
            questionsAsked = 1
        }
    }

    /// Instructions, voice and audio format. Turn detection stays on the
    /// server (xAI ignores turning it off mid-session); the app decides which
    /// replies may play.
    private func sessionConfig() -> [String: Any] {
        ["type": "session.update",
         "session": [
            "voice": session?.voice ?? "eve",
            "instructions": Self.instructions,
            "turn_detection": ["type": "server_vad", "silence_duration_ms": 700],
            "audio": [
                "input": ["format": ["type": "audio/pcm", "rate": 24_000],
                          "transcription": ["model": "grok-transcribe", "language_hint": "en"]],
                "output": ["format": ["type": "audio/pcm", "rate": 24_000]],
            ],
         ] as [String: Any]]
    }

    static let instructions = """
    # Role
    You are Bump, a warm and brief guide. You help someone set up their profile for an app that \
    helps people who just met in person find things in common.

    # Task
    Learn a few things the person enjoys, has done, or wants to find, so the app can build their \
    profile. The opening question has already been asked.

    # Every turn
    - Say one short acknowledgment of a few words, then ask exactly one question.
    - Never ask two questions. Never repeat back their whole answer.
    - Ask about specifics they mentioned (which games, artists, what they build or study), or what \
    they'd enjoy finding someone to do together.
    - Keep it under 20 words. No lists, no advice, no opinions, no small talk.

    # Never
    - Never ask about or comment on health, religion, ethnicity, sexuality, gender identity, politics, \
    immigration status, age, or money.
    - Never guess things about the person or describe their personality.
    - Never say you are saving anything, and never summarise their profile yourself.
    - Never use em dashes.
    """

    private func seedHistory() {
        for line in lines where line.isFinal {
            let (role, type) = line.speaker == .you ? ("user", "input_text") : ("assistant", "output_text")
            connection?.send(["type": "conversation.item.create",
                              "item": ["type": "message", "role": role,
                                       "content": [["type": type, "text": line.text]]]])
        }
    }

    /// Have Grok say an exact line (xAI `force_message`).
    private func speak(_ text: String) {
        expectedLines.append(text)
        connection?.send(["type": "conversation.item.create",
                          "item": ["type": "force_message", "role": "assistant", "interruptible": true,
                                   "content": [["type": "output_text", "text": text]]]])
    }

    private func startTicker() {
        ticker?.invalidate()
        ticker = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
    }

    /// Advances the clock. Public so tests can drive time.
    func tick() {
        guard let startedAt else { return }
        elapsed = now().timeIntervalSince(startedAt)
        if phase == .conversation && elapsed >= Self.hardStopAfter {
            notice = "Time's up, so here's what I heard. You can keep editing as long as you like."
            finishDiscovery(speakClosing: false)
        }
    }

    private func scheduleSettle(_ item: String) {
        settleTimers[item]?.invalidate()
        let g = generation
        settleTimers[item] = Timer.scheduledTimer(withTimeInterval: settleDelay, repeats: false) { [weak self] _ in
            Task { @MainActor in
                guard let self, g == self.generation else { return }
                self.settle(item)
            }
        }
    }

    /// A user turn is final: act on it once.
    private func settle(_ item: String) {
        settleTimers[item] = nil
        guard !settled.contains(item), let line = lines.first(where: { $0.id == item }) else { return }
        settled.insert(item)
        switch phase {
        case .conversation:
            if lastAnswerStarted || questionsAsked >= Self.maxQuestions || wrappingUp {
                finishDiscovery(speakClosing: true)
            }
        case .review:
            handleReview(utterance: line.text)
        default:
            break
        }
    }

    private func finishDiscovery(speakClosing: Bool) {
        guard phase == .conversation else { return }
        phase = .building
        lastAnswerStarted = false
        // Stop anything Grok is saying or about to say.
        if let id = currentResponse { interruptedResponses.insert(id); connection?.send(["type": "response.cancel"]) }
        audio.stopPlayback()
        settleTimers.values.forEach { $0.invalidate() }
        settleTimers.removeAll()
        lines.indices.forEach { lines[$0].isFinal = true }
        activity = .thinking
        if speakClosing { speak(Self.closingLine) }
        buildCard()
    }

    // MARK: Card

    /// Only what the person said, in order. Grok's lines are never extracted from.
    var userText: String {
        lines.filter { $0.speaker == .you && !$0.text.trimmed().isEmpty }
            .map { line in
                let t = line.text.trimmed()
                return ".!?".contains(t.last ?? " ") ? t : t + "."
            }
            .joined(separator: " ")
    }

    private func buildCard() {
        let said = userText
        let g = generation
        work = Task { [weak self] in
            guard let self else { return }
            if said.isEmpty {
                self.onboarding.applyLocalVoiceDraft(userText: "", reason: nil)
            } else if let api = self.backend() {
                do {
                    let draft = try await withDeadline(20) { try await api.draft(transcript: said) }
                    guard g == self.generation, self.phase == .building else { return }
                    if !self.onboarding.applyVoiceDraft(draft, userText: said) {
                        self.onboarding.applyLocalVoiceDraft(userText: said, reason: .invalidResponse)
                    }
                } catch {
                    guard g == self.generation, self.phase == .building else { return }
                    self.onboarding.applyLocalVoiceDraft(userText: said, reason: BumpAPIError.map(error))
                }
            } else {
                self.onboarding.applyLocalVoiceDraft(userText: said, reason: .offline)
            }
            guard g == self.generation, self.phase == .building else { return }
            self.enterReview()
        }
    }

    private func enterReview() {
        phase = .review
        activity = .listening
        speak(onboarding.spokenSummary + " Does that sound right?")
    }

    // MARK: Review

    /// Tapped "Looks right". Saves only what's on the card.
    @discardableResult
    func confirm() -> Bool {
        guard phase == .review, onboarding.canFinish else { return false }
        stop()
        guard onboarding.finish() else { return false }
        phase = .saved
        return true
    }

    private static let yes = ["yes", "yeah", "yep", "yup", "sure", "correct", "right", "that's right",
                              "thats right", "sounds right", "sounds good", "looks good", "looks right",
                              "perfect", "exactly", "ok", "okay", "all good", "that's it", "thats it"]

    /// "Yes, that's right" with nothing else to change.
    static func isPlainYes(_ text: String) -> Bool {
        let t = Grounding.fold(text)
        guard !t.isEmpty, t.split(separator: " ").count <= 5 else { return false }
        let changeWords = ["but", "change", "not", "actually", "remove", "add", "instead", "also", "no"]
        if t.split(separator: " ").contains(where: { changeWords.contains(String($0)) }) { return false }
        return yes.contains { t == Grounding.fold($0) || t.hasPrefix(Grounding.fold($0) + " ") }
    }

    private func handleReview(utterance: String) {
        guard !reviewBusy else { return }
        if Self.isPlainYes(utterance) {
            if !confirm() { speak("Add at least one thing to your card first, then say yes.") }
            return
        }
        guard let api = backend() else {
            speak("I can't change that by voice right now. You can edit the card directly.")
            return
        }
        reviewBusy = true
        activity = .thinking
        let version = onboarding.cardVersion
        let items = onboarding.items.map { (id: $0.id, kind: $0.kind, label: $0.text) }
        let g = generation
        work = Task { [weak self] in
            guard let self else { return }
            defer { if g == self.generation { self.reviewBusy = false } }
            do {
                let revision = try await withDeadline(12) { try await api.revise(items: items, utterance: utterance) }
                // Ignore a late answer if the card changed by hand, or we moved on.
                guard g == self.generation, self.phase == .review, self.onboarding.cardVersion == version else { return }
                switch revision.intent {
                case "confirm":
                    if !self.confirm() { self.speak("Add at least one thing to your card first, then say yes.") }
                case "correct":
                    if self.onboarding.applyRevision(revision, utterance: utterance) {
                        self.speak("Updated. " + self.onboarding.spokenSummary + " Does that sound right?")
                    } else {
                        self.speak("I didn't catch a change there. You can say it again or edit the card.")
                    }
                default:
                    self.speak("Sorry, I didn't catch that. Say yes if it's right, or tell me what to change.")
                }
            } catch {
                guard g == self.generation, self.phase == .review else { return }
                self.notice = "Couldn't apply that by voice (\(OnboardingModel.shortReason(BumpAPIError.map(error)))). Edit the card directly."
                self.activity = .listening
            }
        }
    }

    // MARK: Failure

    private var isFailed: Bool { if case .failed = phase { return true }; return false }

    private func connectionLost(_ message: String) {
        let inReview = phase == .review
        stop()
        if inReview {
            phase = .review
            notice = "Voice disconnected. You can still edit and save your card."
        } else if phase != .saved && phase != .building {
            phase = .failed("\(message) Your answers so far are kept.")
        }
    }

    static func message(for error: BumpAPIError) -> String {
        switch error {
        case .notConfigured: return "The BUMP server has no xAI key yet, so voice isn't available. Type instead."
        case .offline: return "Couldn't reach the BUMP server. Check the connection and try again, or type instead."
        case .timeout: return "The voice service took too long to answer. Try again, or type instead."
        case .rateLimited: return "Too many voice sessions in a row. Wait a minute, or type instead."
        default: return "Voice couldn't start. Try again, or type instead."
        }
    }

    @discardableResult
    private func bumpGeneration() -> Int {
        generation += 1
        return generation
    }

    static func systemMicPermission() async -> Bool {
        switch AVAudioApplication.shared.recordPermission {
        case .granted: return true
        case .denied: return false
        default:
            return await withCheckedContinuation { c in
                AVAudioApplication.requestRecordPermission { c.resume(returning: $0) }
            }
        }
    }

    #if DEBUG
    /// Previews only: pose the screen with SAMPLE lines.
    func seedSample(phase: Phase, activity: Activity, lines: [Line], questions: Int, elapsed: TimeInterval) {
        self.phase = phase
        self.activity = activity
        self.lines = lines
        self.questionsAsked = questions
        self.elapsed = elapsed
    }
    #endif
}
