import Foundation

/// Someone whose phone was nearby without a bump — a "streetpass".
///
/// Deliberately thin: a display name (the only thing the roster carries about an
/// unconfirmed peer, see `Wire.Member`) and when we saw them. No interests, no
/// bio, no photo, no location — none of that reaches us before a confirmed bump,
/// and this record is local only.
struct StreetpassEvent: Codable, Equatable, Identifiable, Sendable {
    var id: UUID = UUID()
    var peerName: String
    var seenAt: Date
    /// The room we were in when we saw them, for context in the feed.
    var roomName: String

    init(id: UUID = UUID(), peerName: String, seenAt: Date, roomName: String) {
        self.id = id
        self.peerName = peerName
        self.seenAt = seenAt
        self.roomName = roomName
    }
}
