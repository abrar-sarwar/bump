import Foundation
import SwiftUI

/// What onboarding needs from the cloud. `BumpAPIClient` in the app; stubs in
/// tests and previews.
protocol OnboardingCloud: Sendable {
    func transcribe(fileURL: URL, onUploaded: @escaping @Sendable () -> Void) async throws -> BumpAPIClient.Transcription
    func draft(transcript: String) async throws -> BumpAPIClient.Draft
    func followup(known: [(kind: ProfileFact.Kind, label: String)], asked: [String], answer: String) async throws -> BumpAPIClient.Followup
}

extension BumpAPIClient: OnboardingCloud {}

/// All state for the Pre phase: name → spoken (or typed) intro → up to three
/// follow-ups → an editable card the person approves.
///
/// Rules this type enforces:
///  - Nothing goes to the cloud until the person has chosen "allow".
///  - Every suggestion keeps the exact words it came from.
///  - A newer request always wins: older ones are cancelled and late answers
///    are ignored (generation counter), including after leaving the screen.
///  - Grok failing never blocks anyone — the on-phone drafter takes over and is
///    labelled as such. Nothing local is ever presented as Grok.
///  - Answers, edits and choices survive moving back and forth between steps.
@MainActor
final class OnboardingModel: ObservableObject {

    enum Step: Int, CaseIterable, Comparable {
        case name, intro, questions, card
        static func < (a: Step, b: Step) -> Bool { a.rawValue < b.rawValue }
    }

    /// Who produced a suggestion — shown to the person.
    enum Origin: String, Equatable, Sendable {
        case grok, onPhone, you

        var label: String {
            switch self {
            case .grok: return "Suggested by Grok"
            case .onPhone: return "Suggested on this phone"
            case .you: return "Added by you"
            }
        }
    }

    struct Item: Identifiable, Equatable {
        let id: String
        var kind: ProfileFact.Kind
        var text: String
        var evidence: String?
        var origin: Origin
        /// Whether it will be saved (and so shared with confirmed partners).
        var included: Bool = true
        /// Came from the intro (replaced if the intro is re-drafted) rather than
        /// from an answer or the person themselves.
        var fromIntro: Bool = false
    }

    struct Question: Equatable {
        let text: String
        let origin: Origin
    }

    struct Answered: Equatable, Identifiable {
        var id: String { question.text }
        let question: Question
        /// nil when skipped. Private: never saved or shared.
        let answer: String?
    }

    enum Busy: Equatable {
        case idle
        case uploading
        case transcribing
        case drafting
        case thinking           // fetching the next question
    }

    /// Hard ceilings on top of URLSession's own timeouts.
    struct Deadlines {
        var transcribe: TimeInterval = 30
        var draft: TimeInterval = 20
        var followup: TimeInterval = 15
    }

    static let maxQuestions = 3

    // MARK: Published state

    @Published var step: Step = .name
    @Published var name: String = ""
    @Published private(set) var cloud: PrivacyPreferences.Cloud

    @Published var typing = false               // "Type instead"
    @Published var transcript: String = ""
    @Published private(set) var transcriptFromVoice = false
    @Published private(set) var busy: Busy = .idle
    @Published private(set) var error: String?
    /// A calm note, e.g. that Grok was unavailable and the phone drafted instead.
    @Published private(set) var notice: String?

    @Published var bio: String = ""
    /// Card photo (already resized). Only shared with confirmed partners.
    @Published var photo: Data?
    @Published private(set) var bioOrigin: Origin?
    @Published var items: [Item] = []

    @Published private(set) var answered: [Answered] = []
    @Published private(set) var current: Question?
    @Published var answer: String = ""

    let recorder = IntroRecorder()

    // MARK: Collaborators

    private let store: Store
    private let cloudProvider: @MainActor () -> OnboardingCloud?
    var deadlines = Deadlines()

    private var work: Task<Void, Never>?
    private var generation = 0
    private var lastDrafted: String?

    init(store: Store, cloud: (@MainActor () -> OnboardingCloud?)? = nil) {
        self.store = store
        self.cloud = store.privacy.cloud
        self.cloudProvider = cloud ?? { BumpAPIClient.resolve(override: store.settings.apiBaseURL) }
        self.name = store.profile.displayName
        self.photo = store.profile.photo
    }

    // MARK: Derived

    var canContinueFromName: Bool { !name.trimmed().isEmpty }
    var canDraft: Bool { !transcript.trimmed().isEmpty && busy == .idle }
    var includedCount: Int { items.filter(\.included).count }
    var canFinish: Bool { !name.trimmed().isEmpty && items.contains { $0.included } }
    var cloudAllowed: Bool { cloud == .allowed }
    var questionNumber: Int { answered.count + 1 }

    func items(_ kind: ProfileFact.Kind) -> [Item] { items.filter { $0.kind == kind } }

    // MARK: Navigation

    func goBack() {
        cancelWork()
        switch step {
        case .name: break
        case .intro: step = .name
        case .questions: step = .intro
        // Only return to the questions if one is actually waiting.
        case .card: step = current != nil ? .questions : .intro
        }
    }

    func continueFromName() {
        guard canContinueFromName else { return }
        step = .intro
    }

    /// Go straight to the card and pick interests by hand.
    func skipIntro() {
        cancelWork()
        recorder.discard()
        step = .card
    }

    /// Called when the screen goes away: nothing in flight may land afterwards.
    func tearDown() {
        cancelWork()
        recorder.discard()
    }

    // MARK: Cloud choice

    func chooseCloud(_ allowed: Bool) {
        cloud = allowed ? .allowed : .localOnly
        store.privacy.cloud = cloud
        if !allowed {
            typing = true
            recorder.discard()
        }
    }

    // MARK: Voice

    func useRecording() {
        guard cloudAllowed else { return }
        guard let file = recorder.fileURL else {
            error = "There's no recording to send. Record again, or type instead."
            return
        }
        guard let client = cloudProvider() else {
            error = "Voice needs the BUMP server, which isn't set up on this phone. Type instead. It works the same."
            return
        }
        error = nil
        busy = .uploading
        let deadline = deadlines.transcribe
        let markUploaded: @Sendable (Int) -> Void = { [weak self] g in
            Task { @MainActor in self?.uploadFinished(generation: g) }
        }
        run { [weak self] g in
            do {
                let result = try await withDeadline(deadline) {
                    try await client.transcribe(fileURL: file) { markUploaded(g) }
                }
                guard let self, self.generation == g else { return }
                self.recorder.deleteFile()          // audio is not kept
                self.transcript = String(result.transcript.trimmed().prefix(BumpAPIClient.Limit.transcript))
                self.transcriptFromVoice = true
                self.busy = .idle
            } catch {
                guard let self, self.generation == g else { return }
                self.busy = .idle
                self.error = Self.voiceMessage(for: BumpAPIError.map(error))
            }
        }
    }

    private func uploadFinished(generation g: Int) {
        guard generation == g, busy == .uploading else { return }
        busy = .transcribing
    }

    func cancelUpload() {
        cancelWork()
    }

    func recordAgain() {
        cancelWork()
        error = nil
        transcript = ""
        transcriptFromVoice = false
        recorder.discard()
        recorder.start()
    }

    static func voiceMessage(for error: BumpAPIError) -> String {
        switch error {
        case .emptyAudio: return "We couldn't make out any words. Try again a little closer to the mic, or type instead."
        case .offline: return "Couldn't reach the BUMP server. Check the connection and try again, or type instead."
        case .timeout: return "Transcribing took too long. Try again, or type instead."
        case .notConfigured: return "Voice isn't available right now because the BUMP server has no Grok key. Type instead."
        case .rateLimited: return "Too many tries in a row. Wait a moment, or type instead."
        case .tooLarge: return "That recording is too large. Record a shorter one, or type instead."
        case .cancelled: return "Upload cancelled."
        default: return "Something went wrong transcribing that. Try again, or type instead."
        }
    }

    // MARK: Draft

    /// Turn the (corrected) intro into suggestions. Re-uses the previous draft
    /// if the text hasn't changed, so going back and forward costs nothing.
    func draftProfile() {
        let text = String(transcript.trimmed().prefix(BumpAPIClient.Limit.transcript))
        guard !text.isEmpty else { return }
        if text == lastDrafted {
            step = (current != nil) ? .questions : .card
            return
        }
        error = nil
        notice = nil
        recorder.deleteFile()

        guard cloudAllowed, let client = cloudProvider() else {
            applyLocalDraft(text, reason: nil)
            return
        }
        busy = .drafting
        let deadline = deadlines.draft
        run { [weak self] g in
            do {
                let draft = try await withDeadline(deadline) { try await client.draft(transcript: text) }
                guard let self, self.generation == g else { return }
                self.busy = .idle
                if !self.applyCloudDraft(draft, text: text) {
                    self.applyLocalDraft(text, reason: .invalidResponse)
                }
            } catch {
                guard let self, self.generation == g else { return }
                self.busy = .idle
                let mapped = BumpAPIError.map(error)
                guard mapped != .cancelled else { return }
                self.applyLocalDraft(text, reason: mapped)
            }
        }
    }

    /// Returns false if nothing usable survived validation.
    private func applyCloudDraft(_ draft: BumpAPIClient.Draft, text: String) -> Bool {
        guard draft.generator.provider == "xai" else { return false }
        let facts = Grounding.facts(draft.facts, groundedIn: text, limit: 12)
        var bioText: String?
        if let bio = draft.bio {
            let t = bio.text.withoutDashes().trimmed()
            let grounded = bio.sources.contains { Grounding.supports(text, $0) }
            if grounded, !t.isEmpty, t.count <= BumpAPIClient.Limit.bio + 40 { bioText = t }
        }
        guard !facts.isEmpty || bioText != nil else { return false }

        replaceIntroItems(with: facts.map { item(from: $0, origin: .grok, fromIntro: true) })
        if let bioText, bio.trimmed().isEmpty || bioOrigin != .you {
            bio = bioText
            bioOrigin = .grok
        }
        lastDrafted = text
        let q = Grounding.question(draft.question, notIn: answered.map(\.question.text))
        advance(to: q.map { Question(text: $0, origin: .grok) })
        return true
    }

    private func applyLocalDraft(_ text: String, reason: BumpAPIError?) {
        let suggestions = LocalDrafter.extract(from: text)
        replaceIntroItems(with: suggestions.map {
            item(from: ProfileFact(kind: $0.kind, text: $0.label, evidence: $0.source), origin: .onPhone, fromIntro: true)
        })
        // After a Grok failure, drafting the same text again retries Grok.
        lastDrafted = reason == nil ? text : nil
        if let reason {
            notice = "Grok wasn't available (\(Self.shortReason(reason))), so this was drafted on your phone. Nothing from Grok is shown."
        }
        advance(to: localQuestion())
    }

    private func replaceIntroItems(with fresh: [Item]) {
        // Keep anything the person added or edited, and answer-derived items.
        var kept = items.filter { !$0.fromIntro || $0.origin == .you }
        for item in fresh where !kept.contains(where: { $0.kind == item.kind && Grounding.fold($0.text) == Grounding.fold(item.text) }) {
            kept.append(item)
        }
        items = kept
    }

    private func advance(to question: Question?) {
        if answered.count < Self.maxQuestions, let question {
            current = question
            answer = ""
            step = .questions
        } else {
            current = nil
            step = .card
        }
    }

    static func shortReason(_ error: BumpAPIError) -> String {
        switch error {
        case .offline: return "couldn't reach the BUMP server"
        case .timeout: return "it took too long"
        case .notConfigured: return "the server has no Grok key"
        case .rateLimited: return "too many requests"
        case .invalidResponse: return "its answer didn't pass our checks"
        default: return "server error"
        }
    }

    // MARK: Questions

    func submitAnswer() {
        guard let question = current else { return }
        let text = String(answer.trimmed().prefix(BumpAPIClient.Limit.answer))
        record(question, answer: text.isEmpty ? nil : text)
    }

    func skipQuestion() {
        guard let question = current else { return }
        record(question, answer: nil)
    }

    private func record(_ question: Question, answer text: String?) {
        answered.append(Answered(question: question, answer: text))
        current = nil
        answer = ""
        notice = nil
        guard answered.count < Self.maxQuestions else { step = .card; return }

        let known = knownFacts
        let asked = answered.map(\.question.text)
        guard cloudAllowed, let client = cloudProvider() else {
            applyLocalAnswer(text)
            return
        }
        busy = .thinking
        let deadline = deadlines.followup
        run { [weak self] g in
            do {
                let result = try await withDeadline(deadline) {
                    try await client.followup(known: known, asked: asked, answer: text ?? "")
                }
                guard let self, self.generation == g else { return }
                self.busy = .idle
                guard result.generator.provider == "xai" else {
                    self.applyLocalAnswer(text, reason: .invalidResponse); return
                }
                let facts = text.map { Grounding.facts(result.facts, groundedIn: $0, limit: 6) } ?? []
                self.appendAnswerItems(facts.map { self.item(from: $0, origin: .grok, fromIntro: false) })
                let q = Grounding.question(result.question, notIn: asked)
                self.advance(to: q.map { Question(text: $0, origin: .grok) })
            } catch {
                guard let self, self.generation == g else { return }
                self.busy = .idle
                let mapped = BumpAPIError.map(error)
                guard mapped != .cancelled else { return }
                self.applyLocalAnswer(text, reason: mapped)
            }
        }
    }

    private func applyLocalAnswer(_ text: String?, reason: BumpAPIError? = nil) {
        if let text {
            appendAnswerItems(LocalDrafter.extract(from: text).map {
                item(from: ProfileFact(kind: $0.kind, text: $0.label, evidence: $0.source), origin: .onPhone, fromIntro: false)
            })
        }
        if let reason {
            notice = "Grok wasn't available (\(Self.shortReason(reason))), so the next question comes from your phone."
        }
        advance(to: localQuestion())
    }

    private func appendAnswerItems(_ fresh: [Item]) {
        for item in fresh where !items.contains(where: { $0.kind == item.kind && Grounding.fold($0.text) == Grounding.fold(item.text) }) {
            items.append(item)
        }
    }

    private func localQuestion() -> Question? {
        LocalDrafter.nextQuestion(known: knownFacts, asked: answered.map(\.question.text),
                                  maxQuestions: Self.maxQuestions)
            .map { Question(text: $0, origin: .onPhone) }
    }

    /// What the person has kept so far — the only profile context a follow-up
    /// request carries. Never the transcript.
    private var knownFacts: [(kind: ProfileFact.Kind, label: String)] {
        items.filter(\.included).map { ($0.kind, $0.text) }
    }

    /// Leave the questions and go to the card.
    func finishQuestions() {
        cancelWork()
        current = nil
        step = .card
    }

    // MARK: Card editing

    func toggle(_ id: String) {
        guard let i = items.firstIndex(where: { $0.id == id }) else { return }
        items[i].included.toggle()
    }

    func remove(_ id: String) {
        items.removeAll { $0.id == id }
    }

    func rename(_ id: String, to text: String) {
        let clean = String(text.trimmed().prefix(BumpAPIClient.Limit.label))
        guard !clean.isEmpty, let i = items.firstIndex(where: { $0.id == id }) else { return }
        items[i].text = items[i].kind == .interest ? displayLabel(forInterest: clean) : clean
        items[i].origin = .you
    }

    func add(_ kind: ProfileFact.Kind, _ text: String) {
        let clean = String(text.trimmed().prefix(BumpAPIClient.Limit.label))
        guard !clean.isEmpty else { return }
        let label = kind == .interest ? displayLabel(forInterest: clean) : clean
        if let i = items.firstIndex(where: { $0.kind == kind && Grounding.fold($0.text) == Grounding.fold(label) }) {
            items[i].included = true
            return
        }
        items.append(Item(id: newID(), kind: kind, text: label, evidence: nil, origin: .you))
    }

    func toggleCatalog(_ interest: Interest) {
        if let i = items.firstIndex(where: { $0.kind == .interest && InterestCatalog.canonical(from: $0.text)?.id == interest.id }) {
            items[i].included.toggle()
        } else {
            items.append(Item(id: newID(), kind: .interest, text: interest.label, evidence: nil, origin: .you))
        }
    }

    func isSelected(_ interest: Interest) -> Bool {
        items.contains { $0.included && $0.kind == .interest && InterestCatalog.canonical(from: $0.text)?.id == interest.id }
    }

    func bioEdited() { bioOrigin = .you }

    // MARK: Save

    /// Only included items are saved. Transcript, answers and drafts are not.
    func buildProfile() -> Profile {
        var interests: [Interest] = []
        var evidence: [String: String] = [:]
        for item in items where item.included && item.kind == .interest {
            guard let interest = InterestCatalog.canonical(from: item.text),
                  !interests.contains(where: { $0.id == interest.id }) else { continue }
            interests.append(interest)
            if let e = item.evidence { evidence[interest.id] = e }
        }
        let details = items.filter { $0.included && $0.kind != .interest }
            .map { ProfileFact(id: $0.id, kind: $0.kind, text: $0.text, evidence: $0.evidence) }
        return Profile(displayName: name.trimmed(), bio: String(bio.trimmed().prefix(280)),
                       interests: interests, details: details, interestEvidence: evidence, photo: photo)
    }

    /// Save the approved card. Returns false (and saves nothing) if incomplete.
    @discardableResult
    func finish() -> Bool {
        let profile = buildProfile()
        guard profile.isComplete else { return false }
        tearDown()
        store.profile = profile
        transcript = ""
        answered = []
        return true
    }

    #if DEBUG
    /// Previews and demo screenshots only: pose the flow with SAMPLE data.
    func seedSample(step: Step, transcript: String, bio: String, items: [Item],
                    answered: [Answered], current: Question?, fromVoice: Bool) {
        self.cloud = .allowed
        self.step = step
        self.transcript = transcript
        self.transcriptFromVoice = fromVoice
        self.bio = bio
        self.bioOrigin = bio.isEmpty ? nil : .grok
        self.items = items
        self.answered = answered
        self.current = current
    }
    #endif

    // MARK: Helpers

    private func item(from fact: ProfileFact, origin: Origin, fromIntro: Bool) -> Item {
        let text = fact.kind == .interest ? displayLabel(forInterest: fact.text) : fact.text
        return Item(id: newID(), kind: fact.kind, text: text, evidence: fact.evidence,
                    origin: origin, fromIntro: fromIntro)
    }

    /// Show a catalogue label when the words are an exact equivalent, so the
    /// person sees what will actually be saved; otherwise keep their words.
    private func displayLabel(forInterest raw: String) -> String {
        guard let c = InterestCatalog.canonical(from: raw) else { return raw }
        return c.custom ? raw : c.label
    }

    private func newID() -> String { "fact-\(UUID().uuidString.prefix(8).lowercased())" }

    private func cancelWork() {
        generation += 1
        work?.cancel()
        work = nil
        if busy != .idle { busy = .idle }
    }

    /// Start a new piece of cloud work, superseding any older one.
    private func run(_ body: @escaping @MainActor (Int) async -> Void) {
        work?.cancel()
        generation += 1
        let g = generation
        work = Task { @MainActor in await body(g) }
    }
}

// MARK: - Deadline

/// Run `work`, throwing `BumpAPIError.timeout` if it takes longer than `seconds`.
///
/// Unlike a task group, this returns AS SOON AS the deadline passes: the work is
/// cancelled and abandoned rather than awaited, so a call that ignores
/// cancellation (e.g. an on-device model mid-generation) can't hold the user up.
func withDeadline<T: Sendable>(_ seconds: TimeInterval,
                               _ work: @escaping @Sendable () async throws -> T) async throws -> T {
    let gate = DeadlineGate<T>()
    return try await withTaskCancellationHandler {
        try await withCheckedThrowingContinuation { continuation in
            gate.install(continuation)
            gate.track(Task {
                do { gate.finish(.success(try await work())) } catch { gate.finish(.failure(error)) }
            })
            gate.track(Task {
                try? await Task.sleep(nanoseconds: UInt64(max(0, seconds) * 1_000_000_000))
                gate.finish(.failure(BumpAPIError.timeout))
            })
        }
    } onCancel: {
        gate.finish(.failure(CancellationError()))
    }
}

/// First result wins; everything else is cancelled. Thread-safe.
private final class DeadlineGate<T: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<T, Error>?
    private var pending: Result<T, Error>?
    private var tasks: [Task<Void, Never>] = []
    private var done = false

    func install(_ c: CheckedContinuation<T, Error>) {
        lock.lock()
        if let result = pending {
            pending = nil
            lock.unlock()
            c.resume(with: result)
            return
        }
        continuation = c
        lock.unlock()
    }

    func track(_ task: Task<Void, Never>) {
        lock.lock()
        let finished = done
        if !finished { tasks.append(task) }
        lock.unlock()
        if finished { task.cancel() }
    }

    func finish(_ result: Result<T, Error>) {
        lock.lock()
        guard !done else { lock.unlock(); return }
        done = true
        let c = continuation
        continuation = nil
        if c == nil { pending = result }
        let running = tasks
        tasks = []
        lock.unlock()
        c?.resume(with: result)
        running.forEach { $0.cancel() }
    }
}
