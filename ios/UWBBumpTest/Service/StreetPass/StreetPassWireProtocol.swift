import Foundation

/// Versioned message envelope for the StreetPass ambient-discovery transport.
/// Deliberately separate from `Wire` — StreetPass has no room/coordinator
/// concept and only ever carries the small teaser payload, never a full
/// SharedProfile. Same idempotency/bounding discipline as `Wire`.
enum StreetPassWire {
    static let version = 1
    /// Small on purpose: this payload is a teaser, capped avatar and
    /// interests, never a full profile.
    static let maxFrame = 16 * 1024

    struct Envelope: Codable {
        var v: Int = StreetPassWire.version
        var id: String = UUID().uuidString
        var body: Body
    }

    enum Body: Codable {
        /// Either direction, sent once a direct link is established.
        case hello(profile: StreetPassPeerProfile)
        /// Either direction. Archived NIDiscoveryToken bytes.
        case discoveryToken(Data)
    }

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
            case .tooLarge(let n): return "StreetPass message too large (\(n) bytes)."
            case .badVersion(let v):
                return "This phone speaks StreetPass protocol v\(StreetPassWire.version); the other sent v\(v)."
            }
        }
    }
}
