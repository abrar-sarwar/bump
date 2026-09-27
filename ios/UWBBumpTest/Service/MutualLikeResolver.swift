import Foundation

/// The partner's answer to "want to connect again?", as far as this phone knows.
enum PartnerLike: Equatable, Sendable {
    /// We have no answer from them. Not the same as a no: a match requires an
    /// explicit yes on both sides, so `.unknown` can never produce one.
    case unknown
    case wantsToConnect
    case passed
}

/// Where the partner's answer comes from.
///
/// This is a seam, not an abstraction for its own sake. Everything downstream —
/// `MatchEvaluator`, the card, the success sheet, the unlock — is written against
/// this one method, so the day a real two-sided check exists it is the only thing
/// that changes.
protocol MutualLikeResolver: Sendable {
    func partnerLike(for connection: SavedConnection) -> PartnerLike
}

/// STAND-IN. This does not ask the other person anything.
///
/// BUMP has no user database and no durable channel: `backend/src/server.js` is
/// an xAI proxy plus a relay whose mailboxes live only for the duration of a
/// bump. By the time someone rates an interaction the peer is long gone, so
/// there is nowhere to read a real answer from.
///
/// So this derives a stable pseudo-answer from the connection's `id`: the same
/// connection always gives the same result, which makes the whole match flow
/// exercisable and demoable, but it is NOT reciprocity and must not be described
/// as such in the UI's copy or anywhere else.
///
/// Replacing it means a durable per-person like mailbox (an identity the app does
/// not yet have, plus storage the backend does not yet have), after which this
/// type is deleted and the real client conforms to `MutualLikeResolver` instead.
struct LocalMutualLikeResolver: MutualLikeResolver {
    /// Fraction of connections the stand-in answers yes for. Deliberately not
    /// 1.0: a flow where everyone matches hides every un-matched state.
    static let yesShare = 0.5

    func partnerLike(for connection: SavedConnection) -> PartnerLike {
        // `hashValue` is not stable across launches in Swift, so derive from the
        // UUID's own bytes instead — the answer must survive a relaunch or a
        // profile would appear to lock itself again.
        let byte = withUnsafeBytes(of: connection.id.uuid) { $0.reduce(into: UInt8(0)) { $0 ^= $1 } }
        return Double(byte) / 255.0 < Self.yesShare ? .wantsToConnect : .passed
    }
}

/// Answers yes for an explicit set of connections and no for the rest. Used by
/// tests and by the DEBUG demo entry points, where the flow has to be reachable
/// on demand rather than by whatever the stand-in happens to derive.
struct FixedMutualLikeResolver: MutualLikeResolver {
    var yes: Set<UUID>
    /// What to answer for a connection outside `yes`.
    var otherwise: PartnerLike = .passed

    init(yes: Set<UUID>, otherwise: PartnerLike = .passed) {
        self.yes = yes
        self.otherwise = otherwise
    }

    func partnerLike(for connection: SavedConnection) -> PartnerLike {
        yes.contains(connection.id) ? .wantsToConnect : otherwise
    }
}
