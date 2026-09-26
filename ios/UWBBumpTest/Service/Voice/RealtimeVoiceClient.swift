import Foundation

/// The xAI realtime voice events onboarding cares about, decoded from JSON.
/// Everything else the server sends is ignored.
enum RealtimeEvent: Equatable {
    /// The socket is open and the server is ready for `session.update`.
    case sessionCreated
    case sessionUpdated
    case speechStarted(itemID: String)
    case speechStopped(itemID: String)
    case committed(itemID: String)
    /// Cumulative live caption for the user's current turn (may be revised).
    case userPartial(itemID: String, text: String)
    /// Finished transcript for the user's turn. Can arrive more than once for
    /// the same item, each time more complete: always REPLACE, never append.
    case userFinal(itemID: String, text: String)
    case responseCreated(responseID: String)
    case assistantText(responseID: String, itemID: String, delta: String)
    case assistantAudio(responseID: String, pcm: Data)
    case responseDone(responseID: String, status: String)
    case ping(timestamp: Any?)
    case error(String)

    static func == (a: RealtimeEvent, b: RealtimeEvent) -> Bool {
        switch (a, b) {
        case (.sessionCreated, .sessionCreated), (.sessionUpdated, .sessionUpdated): return true
        case let (.speechStarted(x), .speechStarted(y)), let (.speechStopped(x), .speechStopped(y)),
             let (.committed(x), .committed(y)), let (.responseCreated(x), .responseCreated(y)):
            return x == y
        case let (.userPartial(a1, a2), .userPartial(b1, b2)), let (.userFinal(a1, a2), .userFinal(b1, b2)):
            return a1 == b1 && a2 == b2
        case let (.assistantText(a1, a2, a3), .assistantText(b1, b2, b3)):
            return a1 == b1 && a2 == b2 && a3 == b3
        case let (.assistantAudio(a1, a2), .assistantAudio(b1, b2)): return a1 == b1 && a2 == b2
        case let (.responseDone(a1, a2), .responseDone(b1, b2)): return a1 == b1 && a2 == b2
        case (.ping, .ping): return true
        case let (.error(x), .error(y)): return x == y
        default: return false
        }
    }

    /// Pure parser, verified against payloads captured from the live API.
    static func parse(_ json: [String: Any]) -> RealtimeEvent? {
        let item = json["item_id"] as? String ?? ""
        let response = json["response_id"] as? String ?? ""
        switch json["type"] as? String {
        case "session.created": return .sessionCreated
        case "session.updated": return .sessionUpdated
        case "input_audio_buffer.speech_started": return .speechStarted(itemID: item)
        case "input_audio_buffer.speech_stopped": return .speechStopped(itemID: item)
        case "input_audio_buffer.committed": return .committed(itemID: item)
        case "conversation.item.input_audio_transcription.updated":
            return .userPartial(itemID: item, text: json["transcript"] as? String ?? "")
        case "conversation.item.input_audio_transcription.completed":
            return .userFinal(itemID: item, text: json["transcript"] as? String ?? "")
        case "response.created":
            let id = (json["response"] as? [String: Any])?["id"] as? String ?? ""
            return .responseCreated(responseID: id)
        case "response.output_audio_transcript.delta", "response.audio_transcript.delta":
            return .assistantText(responseID: response, itemID: item, delta: json["delta"] as? String ?? "")
        case "response.output_audio.delta", "response.audio.delta":
            guard let b64 = json["delta"] as? String, let pcm = Data(base64Encoded: b64) else { return nil }
            return .assistantAudio(responseID: response, pcm: pcm)
        case "response.done":
            let r = json["response"] as? [String: Any]
            return .responseDone(responseID: r?["id"] as? String ?? "", status: r?["status"] as? String ?? "")
        case "ping": return .ping(timestamp: json["ping_timestamp"])
        case "error":
            let e = json["error"] as? [String: Any]
            return .error(e?["message"] as? String ?? "The voice service reported an error.")
        default: return nil
        }
    }
}

/// A realtime voice connection. `RealtimeVoiceClient` in the app; a fake in tests.
@MainActor
protocol VoiceConnection: AnyObject {
    var onEvent: ((RealtimeEvent) -> Void)? { get set }
    /// Called once if the socket fails or closes; the string is shown to the user.
    var onClose: ((String) -> Void)? { get set }
    func connect(url: URL, token: String, model: String)
    func send(_ json: [String: Any])
    func close()
}

/// WebSocket to `wss://api.x.ai/v1/realtime`, authenticated with a short-lived
/// token from the BUMP server (never the API key). Answers pings itself.
@MainActor
final class RealtimeVoiceClient: VoiceConnection {
    var onEvent: ((RealtimeEvent) -> Void)?
    var onClose: ((String) -> Void)?

    private var task: URLSessionWebSocketTask?
    private var session: URLSession?
    private var connectTimeout: Task<Void, Never>?
    private var opened = false
    private var closed = false

    static let connectTimeoutSeconds: UInt64 = 10

    func connect(url: URL, token: String, model: String) {
        close()
        closed = false
        opened = false
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        components?.queryItems = [URLQueryItem(name: "model", value: model)]
        guard let wsURL = components?.url else { fail("The voice address is invalid."); return }

        let session = URLSession(configuration: .ephemeral)
        // The documented way to pass an ephemeral token on a WebSocket.
        let task = session.webSocketTask(with: wsURL, protocols: ["xai-client-secret.\(token)"])
        self.session = session
        self.task = task
        task.resume()
        receive()

        connectTimeout = Task { [weak self] in
            try? await Task.sleep(nanoseconds: Self.connectTimeoutSeconds * 1_000_000_000)
            guard let self, !Task.isCancelled, !self.opened else { return }
            self.fail("Couldn't connect to the voice service in time.")
        }
    }

    func send(_ json: [String: Any]) {
        guard let task, let data = try? JSONSerialization.data(withJSONObject: json),
              let text = String(data: data, encoding: .utf8) else { return }
        task.send(.string(text)) { _ in }
    }

    func close() {
        connectTimeout?.cancel()
        connectTimeout = nil
        closed = true
        task?.cancel(with: .normalClosure, reason: nil)
        task = nil
        session?.invalidateAndCancel()
        session = nil
    }

    private func receive() {
        task?.receive { [weak self] result in
            Task { @MainActor in
                guard let self, !self.closed else { return }
                switch result {
                case .failure(let error):
                    self.fail(self.opened ? "The voice connection dropped." : "Couldn't connect to the voice service (\(error.localizedDescription)).")
                case .success(let message):
                    if !self.opened { self.opened = true; self.connectTimeout?.cancel() }
                    var data: Data?
                    switch message {
                    case .string(let s): data = Data(s.utf8)
                    case .data(let d): data = d
                    @unknown default: break
                    }
                    if let data, let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
                       let event = RealtimeEvent.parse(json) {
                        if case .ping(let ts) = event {
                            var pong: [String: Any] = ["type": "pong"]
                            if let ts { pong["ping_timestamp"] = ts }
                            self.send(pong)
                        } else {
                            self.onEvent?(event)
                        }
                    }
                    self.receive()
                }
            }
        }
    }

    private func fail(_ message: String) {
        guard !closed else { return }
        close()
        onClose?(message)
    }
}
