import Foundation

/// The room coordinator's pairing algorithm. Pure logic with an injected clock,
/// so every scenario is unit-testable without radios or timers.
///
/// WHAT THIS DOES AND DOES NOT KNOW
/// --------------------------------
/// A bump event says "this phone moved sharply". It does NOT say who it bumped.
/// The coordinator stamps each event with ITS OWN monotonic clock on arrival and
/// pairs by arrival proximity. Timestamps from different phones are never
/// subtracted from each other — their clocks are not synchronized, and network
/// latency (tens of ms on a busy room's Wi-Fi/AWDL) further blurs arrival order.
///
/// UWB evidence, when present, is much stronger: a fresh sub-threshold distance
/// measurement between exactly those two peers is direct physical evidence. It
/// is used to promote a pair and to break what would otherwise be ambiguous.
///
/// ALGORITHM
///  1. Age out events older than `timeout` → the phone gets an explicit timeout.
///  2. An event may only be committed after `buffer` ms, so a closer arrival can
///     still win instead of greedily taking the first two.
///  3. Candidates = pairs of DIFFERENT participants whose arrival times differ by
///     at most `window`, where at least one has matured past the buffer.
///  4. Score each candidate: UWB-corroborated pairs sort ahead of all others,
///     then by smallest arrival gap.
///  5. Ambiguity: if a rival candidate shares exactly one member with the best
///     pair and is within `ambiguityMargin` of its gap at the same evidence
///     level, reject everything involved rather than guess.
///  6. Otherwise commit and loop, so two clearly separated pairs both match.
struct PairingMatcher {

    struct Config: Equatable {
        var window: TimeInterval = 0.500
        var ambiguityMargin: TimeInterval = 0.050
        var buffer: TimeInterval = 0.250
        var timeout: TimeInterval = 2.500
        /// A UWB measurement older than this is not evidence about "now".
        var uwbFreshness: TimeInterval = 1.500
        /// Distance below this counts as physical-contact evidence.
        var uwbProximity: Double = 0.15
        /// Per-participant cooldown enforced by the coordinator.
        var participantCooldown: TimeInterval = 1.0
    }

    struct Event: Equatable {
        let id: String
        let participant: String
        /// Coordinator's monotonic arrival time. NOT the sender's clock.
        let arrival: TimeInterval
    }

    /// A UWB observation reported by a participant about a peer it is ranging.
    struct Proximity: Equatable {
        let observer: String
        let peer: String
        let distance: Double
        let at: TimeInterval        // coordinator arrival time
    }

    enum Outcome: Equatable {
        case matched(a: String, b: String, gap: TimeInterval, uwbCorroborated: Bool)
        case ambiguous(participants: [String], candidates: Int)
        case timedOut(participant: String)
    }

    var config = Config()

    private(set) var pending: [Event] = []
    private var proximities: [Proximity] = []
    private var lastEventAt: [String: TimeInterval] = [:]
    /// Participants currently inside a live proposal, locked out of new matching.
    private(set) var locked: Set<String> = []

    // MARK: Input

    enum Rejection: Equatable { case cooldown, duplicatePending, locked }

    mutating func submit(_ event: Event) -> Rejection? {
        if locked.contains(event.participant) { return .locked }
        // Idempotency first: a re-delivered message with the same id is a
        // duplicate, not a rate-limit violation, and must report itself as such.
        if pending.contains(where: { $0.id == event.id }) { return .duplicatePending }
        if pending.contains(where: { $0.participant == event.participant }) { return .duplicatePending }
        if let last = lastEventAt[event.participant],
           event.arrival - last < config.participantCooldown { return .cooldown }

        lastEventAt[event.participant] = event.arrival
        pending.append(event)
        return nil
    }

    mutating func record(_ proximity: Proximity) {
        proximities.append(proximity)
        // Bounded: only recent observations matter.
        let cutoff = proximity.at - config.uwbFreshness * 2
        proximities.removeAll { $0.at < cutoff }
    }

    mutating func lock(_ participants: [String]) { participants.forEach { locked.insert($0) } }
    mutating func unlock(_ participants: [String]) { participants.forEach { locked.remove($0) } }

    mutating func remove(participant: String) {
        pending.removeAll { $0.participant == participant }
        proximities.removeAll { $0.observer == participant || $0.peer == participant }
        lastEventAt[participant] = nil
        locked.remove(participant)
    }

    mutating func reset() {
        pending.removeAll(); proximities.removeAll()
        lastEventAt.removeAll(); locked.removeAll()
    }

    // MARK: Resolve

    mutating func resolve(now: TimeInterval) -> [Outcome] {
        var outcomes: [Outcome] = []

        // 1. age out
        let stale = pending.filter { now - $0.arrival >= config.timeout }
        if !stale.isEmpty {
            pending.removeAll { now - $0.arrival >= config.timeout }
            outcomes += stale.map { .timedOut(participant: $0.participant) }
        }

        while true {
            let candidates = rankedCandidates(now: now)
            guard let best = candidates.first else { break }

            // 5. ambiguity — only among candidates with the SAME evidence level.
            let rivals = candidates.dropFirst().filter { rival in
                guard rival.uwb == best.uwb else { return false }
                let shared = [rival.a.participant, rival.b.participant]
                    .filter { $0 == best.a.participant || $0 == best.b.participant }
                return shared.count == 1 && rival.gap <= best.gap + config.ambiguityMargin
            }

            if !rivals.isEmpty {
                var involved = Set([best.a.participant, best.b.participant])
                for rival in rivals {
                    involved.insert(rival.a.participant); involved.insert(rival.b.participant)
                }
                pending.removeAll { involved.contains($0.participant) }
                outcomes.append(.ambiguous(participants: involved.sorted(),
                                           candidates: rivals.count + 1))
                continue
            }

            // 6. commit
            pending.removeAll { $0.id == best.a.id || $0.id == best.b.id }
            outcomes.append(.matched(a: best.a.participant, b: best.b.participant,
                                     gap: best.gap, uwbCorroborated: best.uwb))
        }
        return outcomes
    }

    private struct Candidate {
        let a: Event, b: Event, gap: TimeInterval, uwb: Bool
    }

    private func rankedCandidates(now: TimeInterval) -> [Candidate] {
        var out: [Candidate] = []
        for i in pending.indices {
            for j in pending.indices where j > i {
                let a = pending[i], b = pending[j]
                guard a.participant != b.participant else { continue }   // never self-pair
                let gap = abs(a.arrival - b.arrival)
                guard gap <= config.window else { continue }
                // At least one must have matured past the buffer.
                guard (now - a.arrival >= config.buffer) || (now - b.arrival >= config.buffer) else { continue }
                out.append(Candidate(a: a, b: b, gap: gap,
                                     uwb: hasFreshProximity(a.participant, b.participant, now: now)))
            }
        }
        // UWB-corroborated first, then closest arrival, then a stable tiebreak.
        return out.sorted {
            if $0.uwb != $1.uwb { return $0.uwb }
            if $0.gap != $1.gap { return $0.gap < $1.gap }
            return min($0.a.arrival, $0.b.arrival) < min($1.a.arrival, $1.b.arrival)
        }
    }

    /// Fresh, correctly attributed physical evidence that these two specific
    /// participants were in contact. Direction is NOT required — a valid
    /// distance is sufficient evidence on its own.
    func hasFreshProximity(_ x: String, _ y: String, now: TimeInterval) -> Bool {
        proximities.contains { p in
            let pairMatches = (p.observer == x && p.peer == y) || (p.observer == y && p.peer == x)
            return pairMatches
                && p.distance <= config.uwbProximity
                && now - p.at <= config.uwbFreshness
        }
    }
}
