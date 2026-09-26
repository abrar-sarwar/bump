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
    /// Further mutual interests, shown blurred on the card as a tease — the
    /// person has to bump to read them. Real statements from InterestMatcher,
    /// never padding: empty when there is only one match, or none.
    var teasedMutualStatements: [String] = []
}

extension StreetPassEncounter {
    /// How many mutual interests the card can hint at behind the blur.
    static let maxTeased = 2

    /// Splits the grounded overlap into the one statement shown in the clear
    /// and the ones shown blurred. Pure, so the split itself is testable
    /// without standing up a transport.
    static func teaser(mine: [Interest], theirs: [Interest]) -> (statement: String?, teased: [String]) {
        let statements = InterestMatcher.overlap(mine, theirs, limit: maxTeased + 1).map(\.statement)
        return (statements.first, Array(statements.dropFirst()))
    }
}
