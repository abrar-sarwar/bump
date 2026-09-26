import Foundation

/// The ambient StreetPass broadcast payload: what one phone tells any nearby
/// StreetPass peer about itself, before any mutual confirmation. Deliberately
/// smaller than `SharedProfile` — no bio, no experiences/goals, no evidence.
struct StreetPassPeerProfile: Codable, Equatable, Sendable {
    /// Transient, session-scoped identity. Never a stable user id.
    var id: String
    var displayName: String
    /// Small square JPEG, same bounding discipline as ProfilePhoto. Optional.
    var avatarThumbnail: Data?
    /// Full Interest structs (not bare canonical ids), capped small, so a
    /// custom catalog-less interest still round-trips correctly for
    /// mutual-interest matching.
    var interests: [Interest]

    static let maxInterests = 5

    init(id: String, displayName: String, avatarThumbnail: Data? = nil, interests: [Interest]) {
        self.id = id
        self.displayName = displayName
        self.avatarThumbnail = avatarThumbnail
        self.interests = Array(interests.prefix(Self.maxInterests))
    }

    /// Custom Decodable to enforce interest cap during JSON decoding.
    /// Without this, the synthesized Decodable would ignore the cap and decode
    /// any number of interests from the wire protocol.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        displayName = try c.decode(String.self, forKey: .displayName)
        avatarThumbnail = try c.decodeIfPresent(Data.self, forKey: .avatarThumbnail)
        let decodedInterests = try c.decode([Interest].self, forKey: .interests)
        interests = Array(decodedInterests.prefix(Self.maxInterests))
    }
}
