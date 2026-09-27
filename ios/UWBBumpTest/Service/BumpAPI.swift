import Foundation

/// The app's only cloud dependency: our own small backend (`backend/`), which
/// in turn talks to xAI. The app never holds an xAI key.
///
/// Every call is bounded (timeouts, input limits) and every response is
/// validated here as well as on the server: we never trust a result just
/// because it parsed. A failure throws; callers fall back to local logic and
/// label that result honestly. Nothing in this file fabricates a "Grok" result.
struct BumpAPIClient: Sendable {
    let baseURL: URL
    var session: URLSession = BumpAPIClient.defaultSession

    static let defaultSession: URLSession = {
        let config = URLSessionConfiguration.ephemeral     // no disk cache of bodies
        config.timeoutIntervalForRequest = 25
        config.timeoutIntervalForResource = 40
        config.waitsForConnectivity = false                 // fail fast when offline
        config.urlCache = nil
        return URLSession(configuration: config)
    }()

    // MARK: Limits (mirrors backend/CONTRACT.md)

    enum Limit {
        static let transcript = 2000
        static let answer = 500
        static let label = 60
        static let evidence = 200
        static let bio = 200
        static let question = 160
        static let prompt = 180
        static let audioBytes = 3 * 1024 * 1024
        static let candidates = 8
    }

    // MARK: Resolving the base URL

    /// Settings override first (so a phone can be pointed at a Mac without a
    /// rebuild), then the build's `BumpAPIBaseURL` Info.plist value.
    static func resolve(override: String?) -> BumpAPIClient? {
        // The built-in server wins over a saved override, so a phone holding an
        // old address (a LAN IP, a dead tunnel) still reaches the live server.
        let raw = [Bundle.main.object(forInfoDictionaryKey: "BumpAPIBaseURL") as? String, override]
            .compactMap { $0?.trimmed() }
            .first { !$0.isEmpty && !$0.hasPrefix("$(") }
        guard let raw, let url = URL(string: raw), let scheme = url.scheme,
              ["http", "https"].contains(scheme.lowercased()), url.host != nil else { return nil }
        return BumpAPIClient(baseURL: url)
    }

    // MARK: Endpoints

    struct Health: Decodable, Sendable {
        let ok: Bool
        let grokConfigured: Bool
        let model: String?
        /// True when this server has the room relay (older servers omit it).
        let relay: Bool?
    }

    struct Generator: Decodable, Equatable, Sendable {
        let provider: String
        let model: String
    }

    struct Transcription: Decodable, Sendable {
        let transcript: String
        let durationSeconds: Double?
        let generator: Generator?
    }

    struct ProposedFact: Codable, Equatable, Hashable, Sendable {
        let kind: String
        let label: String
        let source: String
    }

    struct Draft: Decodable, Sendable {
        struct Bio: Decodable, Sendable { let text: String; let sources: [String] }
        let bio: Bio?
        let facts: [ProposedFact]
        let question: String?
        let generator: Generator
    }

    struct Followup: Decodable, Sendable {
        let facts: [ProposedFact]
        let question: String?
        let generator: Generator
    }

    struct Candidate: Codable, Equatable, Sendable {
        let id: String
        let kind: TalkingPoint.Kind
        let mine: String
        let theirs: String
    }

    struct TalkingPoints: Decodable, Sendable {
        struct Point: Decodable, Sendable { let candidateId: String; let prompt: String }
        let points: [Point]
        let opener: String
        let generator: Generator
    }

    func health() async throws -> Health {
        var request = URLRequest(url: baseURL.appendingPathComponent("healthz"))
        request.timeoutInterval = 3
        return try await send(request)
    }

    /// Upload a recorded clip. `onUploaded` fires once the body has been sent,
    /// so the UI can switch from "Uploading" to "Transcribing".
    func transcribe(fileURL: URL, onUploaded: @escaping @Sendable () -> Void) async throws -> Transcription {
        let size = (try? FileManager.default.attributesOfItem(atPath: fileURL.path)[.size] as? Int) ?? 0
        guard size > 0 else { throw BumpAPIError.emptyAudio }
        guard size <= Limit.audioBytes else { throw BumpAPIError.tooLarge }

        var request = URLRequest(url: baseURL.appendingPathComponent("v1/transcribe"))
        request.httpMethod = "POST"
        request.setValue("audio/mp4", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 30
        let delegate = UploadProgress(onUploaded: onUploaded)
        do {
            let (data, response) = try await session.upload(for: request, fromFile: fileURL, delegate: delegate)
            let result: Transcription = try Self.decode(data, response)
            guard !result.transcript.trimmed().isEmpty else { throw BumpAPIError.emptyAudio }
            return result
        } catch {
            throw BumpAPIError.map(error)
        }
    }

    func draft(transcript: String) async throws -> Draft {
        let text = transcript.trimmed().clipped(Limit.transcript)
        guard !text.isEmpty else { throw BumpAPIError.invalidResponse }
        return try await post("v1/profile/draft", timeout: 18, body: [
            "transcript": .string(text),
            "catalogLabels": .strings(InterestCatalog.all.map(\.label)),
        ])
    }

    func followup(known: [(kind: ProfileFact.Kind, label: String)], asked: [String], answer: String) async throws -> Followup {
        try await followup(known: known, asked: asked, answer: answer, topic: nil)
    }

    func followup(known: [(kind: ProfileFact.Kind, label: String)], asked: [String], answer: String,
                  topic: OnboardingTopic?) async throws -> Followup {
        var body: [String: Body] = [
            "known": .objects(known.prefix(30).map {
                ["kind": $0.kind.rawValue, "label": $0.label.clipped(Limit.label)]
            }),
            "asked": .strings(asked.map { $0.clipped(Limit.question) }),
            "answer": .string(answer.trimmed().clipped(Limit.answer)),
            "catalogLabels": .strings(InterestCatalog.all.map(\.label)),
        ]
        if let topic { body["topic"] = .objects([["id": topic.rawValue, "purpose": topic.purpose]]) }
        return try await post("v1/profile/followup", timeout: 15, body: body)
    }

    func talkingPoints(_ candidates: [Candidate], timeout: TimeInterval = 7) async throws -> TalkingPoints {
        try await post("v1/talking-points", timeout: timeout, body: [
            // The server rejects ids over 80; skip those rather than lose the call.
            "candidates": .objects(candidates.filter { $0.id.unicodeScalars.count <= 80 }
                                    .prefix(Limit.candidates).map {
                ["id": $0.id, "kind": $0.kind.rawValue,
                 "mine": $0.mine.clipped(Limit.label), "theirs": $0.theirs.clipped(Limit.label)]
            }),
        ])
    }

    // MARK: Plumbing

    /// A tiny JSON value so request bodies stay explicit and bounded.
    enum Body: Encodable {
        case string(String)
        case strings([String])
        case objects([[String: String]])

        func encode(to encoder: Encoder) throws {
            var c = encoder.singleValueContainer()
            switch self {
            case .string(let s): try c.encode(s)
            case .strings(let a): try c.encode(a)
            case .objects(let o): try c.encode(o)
            }
        }
    }

    /// Grok files custom interests under catalogue ids: label -> ids.
    func tagInterests(_ labels: [String]) async throws -> [String: [String]] {
        struct Vocab: Encodable { let id: String; let label: String }
        struct Body: Encodable { let interests: [String]; let vocabulary: [Vocab] }
        struct Reply: Decodable { let tags: [String: [String]] }
        var request = URLRequest(url: baseURL.appendingPathComponent("v1/interests/tag"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 15
        request.httpBody = try JSONEncoder().encode(Body(
            interests: Array(labels.prefix(30)).map { String($0.prefix(80)) },
            vocabulary: InterestCatalog.all.map { Vocab(id: $0.id, label: $0.label) }))
        let reply: Reply = try await send(request)
        return reply.tags
    }

    /// Grok's voice reading `text` aloud, as MP3 bytes.
    func speech(text: String, timeout: TimeInterval = 3) async throws -> Data {
        var request = URLRequest(url: baseURL.appendingPathComponent("v1/tts"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = timeout
        request.httpBody = try JSONEncoder().encode(["text": String(text.prefix(300))])
        do {
            let (data, response) = try await session.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200, !data.isEmpty else {
                throw BumpAPIError.invalidResponse
            }
            return data
        } catch {
            throw BumpAPIError.map(error)
        }
    }

    private func post<T: Decodable>(_ path: String, timeout: TimeInterval, body: [String: Body]) async throws -> T {
        var request = URLRequest(url: baseURL.appendingPathComponent(path))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = timeout
        request.httpBody = try JSONEncoder().encode(body)
        return try await send(request)
    }

    private func send<T: Decodable>(_ request: URLRequest) async throws -> T {
        do {
            let (data, response) = try await session.data(for: request)
            return try Self.decode(data, response)
        } catch {
            throw BumpAPIError.map(error)
        }
    }

    private struct ErrorBody: Decodable {
        struct Inner: Decodable { let code: String; let message: String? }
        let error: Inner
    }

    static func decode<T: Decodable>(_ data: Data, _ response: URLResponse) throws -> T {
        guard let http = response as? HTTPURLResponse else { throw BumpAPIError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            let code = (try? JSONDecoder().decode(ErrorBody.self, from: data))?.error.code ?? "http_\(http.statusCode)"
            throw BumpAPIError.server(status: http.statusCode, code: code)
        }
        do { return try JSONDecoder().decode(T.self, from: data) }
        catch { throw BumpAPIError.invalidResponse }
    }
}

/// Reports when the upload body has been fully sent.
private final class UploadProgress: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    private let onUploaded: @Sendable () -> Void
    private var fired = false
    init(onUploaded: @escaping @Sendable () -> Void) { self.onUploaded = onUploaded }

    func urlSession(_ session: URLSession, task: URLSessionTask, didSendBodyData bytesSent: Int64,
                    totalBytesSent: Int64, totalBytesExpectedToSend: Int64) {
        guard !fired, totalBytesExpectedToSend > 0, totalBytesSent >= totalBytesExpectedToSend else { return }
        fired = true
        onUploaded()
    }
}

enum BumpAPIError: Error, Equatable, LocalizedError {
    case notConfigured          // no backend URL, or the backend has no xAI key
    case offline                // can't reach the backend at all
    case timeout
    case rateLimited
    case emptyAudio
    case tooLarge
    case cancelled
    case invalidResponse        // unparseable, or failed our validation
    case server(status: Int, code: String)

    static func map(_ error: Error) -> BumpAPIError {
        if let api = error as? BumpAPIError {
            switch api {
            case .server(_, "not_configured"): return .notConfigured
            case .server(_, "rate_limited"): return .rateLimited
            case .server(_, "empty_audio"): return .emptyAudio
            case .server(_, "too_large"): return .tooLarge
            case .server(_, "upstream_timeout"): return .timeout
            default: return api
            }
        }
        if error is CancellationError { return .cancelled }
        if let url = error as? URLError {
            switch url.code {
            case .cancelled: return .cancelled
            case .timedOut: return .timeout
            case .notConnectedToInternet, .cannotConnectToHost, .cannotFindHost,
                 .networkConnectionLost, .dnsLookupFailed, .secureConnectionFailed,
                 .appTransportSecurityRequiresSecureConnection:
                return .offline
            default: return .offline
            }
        }
        return .invalidResponse
    }

    var errorDescription: String? {
        switch self {
        case .notConfigured: return "The BUMP server isn't set up for Grok yet."
        case .offline: return "Couldn't reach the BUMP server."
        case .timeout: return "The BUMP server took too long to answer."
        case .rateLimited: return "Too many requests. Give it a minute."
        case .emptyAudio: return "We couldn't hear anything in that recording."
        case .tooLarge: return "That recording is too large to send."
        case .cancelled: return "Cancelled."
        case .invalidResponse: return "Grok's answer didn't pass our checks."
        case .server(let status, _): return "The BUMP server had a problem (\(status))."
        }
    }
}

// MARK: - Validation (shared by the server and local paths)

/// Pure checks that keep every suggestion tied to what the person actually said.
enum Grounding {

    /// Case, accent, punctuation and whitespace folding — the same rule the
    /// server uses — so "I'm into jazz!" supports the excerpt "im into jazz".
    static func fold(_ s: String) -> String {
        let mapped = s.replacingOccurrences(of: "\u{2019}", with: "'")
            .replacingOccurrences(of: "\u{2018}", with: "'")
        return InterestCatalog.normalize(mapped)
    }

    /// True when `excerpt` is genuinely present in `text`, on word boundaries
    /// ("ja" is not supported by "jazz").
    static func supports(_ text: String, _ excerpt: String) -> Bool {
        let needle = fold(excerpt)
        guard needle.count >= 2 else { return false }
        return " \(fold(text)) ".contains(" \(needle) ")
    }

    /// Keep only well-formed facts whose source is in `text`, deduplicated.
    static func facts(_ proposed: [BumpAPIClient.ProposedFact], groundedIn text: String,
                      limit: Int) -> [ProfileFact] {
        var seen = Set<String>()
        var out: [ProfileFact] = []
        for fact in proposed {
            guard let kind = ProfileFact.Kind(rawValue: fact.kind) else { continue }
            let label = String(fact.label.withoutDashes().trimmed().prefix(BumpAPIClient.Limit.label))
            let source = String(fact.source.trimmed().prefix(BumpAPIClient.Limit.evidence))
            guard !label.isEmpty, supports(text, source) else { continue }
            // Valid JSON is not evidence. The quote must sit in a positive
            // statement about the person themselves, and an interest's label
            // must come from their own words: "I watch anime" can never
            // become "Golden Boy", and "I don't like Golden Boy" is not a like.
            guard isAffirmative(source, in: text) else { continue }
            if kind == .interest, !labelSupported(label, in: text) {
                // Only a broad catalogue category ("Music") may be worded
                // differently from what they said. Titles never may.
                guard let known = InterestCatalog.canonical(from: label), !known.custom,
                      known.specificity == 1 else { continue }
            }
            let key = "\(kind.rawValue)|\(fold(label))"
            guard seen.insert(key).inserted else { continue }
            out.append(ProfileFact(kind: kind, text: label, evidence: source))
            if out.count == limit { break }
        }
        return out
    }

    // MARK: Evidence

    private static let negations = [
        "don't", "dont", "do not", "does not", "doesn't", "doesnt", "not", "never", "no longer",
        "hate", "hated", "dislike", "can't stand", "cant stand", "not a fan", "not into", "used to",
        "isn't", "isnt", "aren't", "arent", "wasn't", "wasnt",
    ]
    private static let otherPeople = [
        "my friend", "my friends", "my brother", "my sister", "my mom", "my mum", "my dad",
        "my partner", "my girlfriend", "my boyfriend", "my wife", "my husband", "my roommate",
        "my kid", "my son", "my daughter", "my cousin", "my coworker", "my colleague",
        "he likes", "she likes", "he loves", "she loves", "they like", "they love", "he is into", "she is into",
    ]

    /// The person's text split into clauses on sentence punctuation, commas
    /// and "but", so "My friend likes Golden Boy, but I like Naruto" is two.
    static func clauses(_ text: String) -> [String] {
        text.replacingOccurrences(of: #"\s+but\s+"#, with: ".", options: [.regularExpression, .caseInsensitive])
            .components(separatedBy: CharacterSet(charactersIn: ".;!?,\n"))
            .map { $0.trimmed() }.filter { !$0.isEmpty }
    }

    /// Clauses that state something positive about the speaker.
    static func affirmativeClauses(_ text: String) -> [String] {
        clauses(text).filter { clause in
            let f = " " + fold(clause.replacingOccurrences(of: "\u{2019}", with: "'")) + " "
            let raw = " " + clause.lowercased().replacingOccurrences(of: "\u{2019}", with: "'") + " "
            let negated = negations.contains { raw.contains(" \($0) ") || f.contains(" \(fold($0)) ") }
            let someoneElse = otherPeople.contains { f.contains(" \(fold($0)) ") }
            return !negated && !someoneElse
        }
    }

    /// The quote appears in at least one positive clause about the speaker.
    static func isAffirmative(_ excerpt: String, in text: String) -> Bool {
        affirmativeClauses(text).contains { supports($0, excerpt) || supports(excerpt, $0) }
    }

    /// Every meaningful word of the label is in ONE positive clause of the
    /// person's text (a plural "s" is allowed either way).
    static func labelSupported(_ label: String, in text: String) -> Bool {
        let filler: Set<String> = ["a", "an", "the", "of", "and", "to", "in", "on", "at"]
        let words = fold(label).split(separator: " ").map(String.init).filter { !filler.contains($0) }
        guard !words.isEmpty else { return false }
        return affirmativeClauses(text).contains { clause in
            let have = Set(fold(clause).split(separator: " ").map(String.init))
            return words.allSatisfy { w in
                have.contains(w) || have.contains(w + "s") || (w.hasSuffix("s") && have.contains(String(w.dropLast())))
            }
        }
    }

    /// A usable question: short, actually a question, not a repeat.
    static func question(_ raw: String?, notIn asked: [String], limit: Int = BumpAPIClient.Limit.question) -> String? {
        guard let q = raw?.withoutDashes().trimmed(), q.count >= 8, q.count <= limit, q.hasSuffix("?") else { return nil }
        let folded = fold(q)
        guard !asked.contains(where: { fold($0) == folded }) else { return nil }
        guard !inventsScores(q) else { return nil }
        return q
    }

    /// No compatibility scores or percentages — we have no data to back them.
    static func inventsScores(_ s: String) -> Bool {
        let lower = s.lowercased()
        return lower.contains("%") || lower.contains("percent") || lower.contains("compatib")
    }
}

extension BumpAPIClient: ConversationService.CloudPhraser {}

extension String {
    /// House style: no em or en dashes in generated text. "piano—what" and
    /// "piano — what" both become "piano, what". Never applied to quotes of the
    /// user's own words.
    func withoutDashes() -> String {
        replacingOccurrences(of: #"\s*[\u{2014}\u{2013}]\s*"#, with: ", ", options: .regularExpression)
    }

    /// Clip to `n` Unicode scalars — the unit the server counts — so an emoji-
    /// heavy text never trips a server-side length check.
    func clipped(_ n: Int) -> String {
        guard unicodeScalars.count > n else { return self }
        var view = String.UnicodeScalarView()
        view.append(contentsOf: unicodeScalars.prefix(n))
        // The cut may split the last character (e.g. half a flag emoji): drop it.
        return String(String(view).dropLast())
    }
}
