import Foundation

/// A single StreetPass encounter, ephemeral and in-memory only — never
/// persisted, never logged to disk. Cleared on dismiss or peer disconnect.
struct StreetPassEncounter: Identifiable, Equatable {
    /// The peer's transient StreetPass transport id.
    let id: String
    let displayName: String
    let avatarThumbnail: Data?
    /// The one grounded, shared interest to tease, already phrased by
    /// InterestMatcher (e.g. "You're both into jazz piano."). nil when there
    /// is no mutual interest — never invented, never substituted.
    let mutualInterestStatement: String?
}
