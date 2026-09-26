import Foundation

/// The versioned message protocol spoken over the peer transport.
///
/// Every message carries a `v` and a unique `id` so receivers can drop
/// duplicates and late re-deliveries idempotently. Payloads are bounded before
/// decoding (`Wire.maxFrame`) so a malformed or hostile peer cannot make us
/// allocate without limit.
enum Wire {
    /// v2: partner-only profile messages carry `PartnerCaps`, and insights carry
    /// talking points. Older builds are refused with a clear message rather than
    /// half-decoding.
    static let version = 2
    /// Hard cap on an accepted frame. A profile with a long bio and many
    /// interests is a few KB; 64 KB is generous and still bounded.
    static let maxFrame = 64 * 1024

    struct Envelope: Codable {
        var v: Int = Wire.version
        var id: String = UUID().uuidString
        var body: Body
    }

    enum Body: Codable {
        // ---- discovery / membership
        /// Guest → coordinator, on connect.
        case hello(displayName: String, roomCode: String, supportsUWB: Bool, supportsAI: Bool)
        /// Coordinator → guest, accepting or refusing membership.
        case welcome(accepted: Bool, reason: String?, roomName: String, capacity: Int, occupancy: Int)
        /// Coordinator → everyone: the current roster, for ranging + manual pick.
        case roster(members: [Member])

        // ---- UWB token exchange
        /// Either direction. Archived NIDiscoveryToken bytes.
        case discoveryToken(Data)

        // ---- bump pipeline
        /// Participant → coordinator: "I felt a deliberate spike."
        case bumpEvent(localSequence: Int, magnitude: Double)
        /// Participant → coordinator: "I am ranging <peer> at <distance> m."
        case proximity(peer: String, distance: Double)
        /// Coordinator → the two participants.
        case proposal(id: String, partner: Member, uwbCorroborated: Bool, expiresIn: TimeInterval)
        /// Coordinator → participant: your bump found nobody / was ambiguous.
        case bumpTimedOut
        case bumpAmbiguous(candidates: Int)
        /// Participant → coordinator.
        case confirm(proposalID: String)
        case decline(proposalID: String, reason: String)
        /// Coordinator → participant: the other side confirmed / it's dead.
        case partnerConfirmed(proposalID: String)
        case proposalClosed(proposalID: String, reason: String)
        /// Coordinator → both: both confirmed, go exchange profiles directly.
        case proposalSealed(proposalID: String, generator: String)

        // ---- direct, partner-only exchange (never through the coordinator)
        case profile(proposalID: String, profile: SharedProfile, caps: PartnerCaps)
        case insight(proposalID: String, insight: ConnectionInsight)
    }

    /// The minimum a confirmed partner needs to agree on who generates the
    /// talking points. Sent ONLY on the direct partner link, never to the room or
    /// the coordinator. Two booleans, no reasons, no settings.
    struct PartnerCaps: Codable, Equatable, Hashable, Sendable {
        /// This person allowed cloud processing (Grok via the BUMP server).
        var cloudConsent: Bool
        /// This phone could reach a BUMP server with Grok configured.
        var grokReady: Bool

        static let none = PartnerCaps(cloudConsent: false, grokReady: false)
    }

    /// A participant as everyone else sees them. Minimal on purpose: enough to
    /// discover, range and confirm a person, and nothing more. Interests are
    /// NEVER in here — they go only to a confirmed partner.
    struct Member: Codable, Equatable, Hashable, Identifiable, Sendable {
        /// Transient per-session identity, not a stable user id.
        let id: String
        let displayName: String
        var supportsUWB: Bool = false
    }

    // MARK: Coding

    static func encode(_ body: Body) throws -> Data {
        let data = try JSONEncoder().encode(Envelope(body: body))
        guard data.count <= maxFrame else { throw WireError.tooLarge(data.count) }
        return data
    }

    static func decode(_ data: Data) throws -> Envelope {
        guard data.count <= maxFrame else { throw WireError.tooLarge(data.count) }
        let envelope = try JSONDecoder().decode(Envelope.self, from: data)
        guard envelope.v == version else { throw WireError.badVersion(envelope.v) }
        return envelope
    }

    enum WireError: Error, LocalizedError, Equatable {
        case tooLarge(Int)
        case badVersion(Int)

        var errorDescription: String? {
            switch self {
            case .tooLarge(let n): return "Message too large (\(n) bytes)."
            case .badVersion(let v): return "This phone speaks BUMP protocol v\(Wire.version); the other sent v\(v). Both phones need the same app version."
            }
        }
    }
}

/// Remembers message ids we have already handled, so a duplicate or delayed
/// re-delivery is a no-op. Bounded.
struct SeenMessages {
    private var order: [String] = []
    private var set: Set<String> = []
    private let limit: Int

    init(limit: Int = 400) { self.limit = limit }

    /// Returns true the first time an id is seen, false for every repeat.
    mutating func accept(_ id: String) -> Bool {
        guard !set.contains(id) else { return false }
        set.insert(id); order.append(id)
        if order.count > limit { set.remove(order.removeFirst()) }
        return true
    }
}
