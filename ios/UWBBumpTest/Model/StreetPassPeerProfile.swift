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
}
