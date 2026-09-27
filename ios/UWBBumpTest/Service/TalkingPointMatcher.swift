import Foundation

/// Finds what two approved profiles can actually talk about. Pure, synchronous
/// and deterministic — both phones would compute the same list — so it is the
/// reliable fallback and the only source of facts a model is allowed to phrase.
///
/// Two kinds, kept separate on purpose:
///  - **shared**: the same thing appears in both profiles (via `InterestMatcher`).
///  - **complementary**: related but different things — "jazz" and "jazz piano",
///    or one person's goal and the other's matching experience. These are offered
///    as something to ask about, never as a claim that the two people share it.
///
/// Broad interests are never forced into narrower ones: "music" and "jazz piano"
/// are complementary at most, never shared.
enum TalkingPointMatcher {

    typealias Candidate = BumpAPIClient.Candidate

    static func candidates(_ mine: SharedProfile, _ theirs: SharedProfile,
                           limit: Int = BumpAPIClient.Limit.candidates) -> [Candidate] {
        var out: [Candidate] = []

        // 1. Genuine overlap, already ranked specific-first.
        // Related matches (two different titles under one topic) are NOT
        // shared: they reach Grok below as complementary pairs, so it is never
        // told one person's title is something both listed.
        for h in InterestMatcher.overlap(mine, theirs, limit: 4) where !h.isRelated {
            out.append(Candidate(id: "shared:\(h.interestID)", kind: .shared,
                                 mine: h.yourEntry, theirs: h.theirEntry))
        }

        // Identical approved experiences or goals also count as shared.
        let theirDetails = Dictionary(theirs.details.map { (Grounding.fold($0.text), $0) },
                                      uniquingKeysWith: { a, _ in a })
        for fact in mine.details.sorted(by: { $0.id < $1.id }) {
            if let match = theirDetails[Grounding.fold(fact.text)], match.kind == fact.kind {
                out.append(Candidate(id: "shared:\(fact.kind.rawValue):\(Grounding.fold(fact.text))",
                                     kind: .shared, mine: fact.text, theirs: match.text))
            }
        }

        // 2. One person's goal lines up with the other's interest or experience.
        out += goalPairs(from: mine, to: theirs, mineIsGoal: true)
        out += goalPairs(from: theirs, to: mine, mineIsGoal: false)

        // 3. Different interests under the same broad category.
        out += relatedInterests(mine, theirs)

        // Dedupe by id, keep order, cap.
        var seen = Set<String>()
        return Array(out.filter { seen.insert($0.id).inserted }.prefix(limit))
    }

    // MARK: Goals

    private static func goalPairs(from goalOwner: SharedProfile, to other: SharedProfile,
                                  mineIsGoal: Bool) -> [Candidate] {
        var out: [Candidate] = []
        let offers: [(id: String, text: String)] =
            other.interests.map { ($0.id, $0.label) } +
            other.details.filter { $0.kind == .experience }.map { ($0.id, $0.text) }

        for goal in goalOwner.details.filter({ $0.kind == .goal }).sorted(by: { $0.id < $1.id }) {
            let goalWords = contentWords(goal.text)
            guard let offer = offers.sorted(by: { $0.id < $1.id })
                    .first(where: { !goalWords.isDisjoint(with: contentWords($0.text), matching: stemMatch) })
            else { continue }
            // Id is written from a neutral viewpoint so both phones agree on it.
            let id = "goal:\(goal.id)|\(offer.id)"
            out.append(mineIsGoal
                ? Candidate(id: id, kind: .complementary, mine: goal.text, theirs: offer.text)
                : Candidate(id: id, kind: .complementary, mine: offer.text, theirs: goal.text))
        }
        return out
    }

    // MARK: Related interests

    private static func relatedInterests(_ mine: SharedProfile, _ theirs: SharedProfile) -> [Candidate] {
        let mineCanon = mine.interests.compactMap { canonical($0) }
        let theirsCanon = theirs.interests.compactMap { canonical($0) }
        let sharedIDs = Set(mineCanon.map(\.id)).intersection(theirsCanon.map(\.id))

        var out: [Candidate] = []
        var usedFamilies = Set<String>()
        // Specific-with-specific first, then broad-with-specific.
        let pairs = mineCanon.flatMap { a in theirsCanon.map { (a, $0) } }
            .filter { a, b in
                a.id != b.id && !sharedIDs.contains(a.id) && !sharedIDs.contains(b.id)
                    && family(a) != nil && family(a) == family(b)
            }
            .sorted { lhs, rhs in
                let l = lhs.0.specificity + lhs.1.specificity, r = rhs.0.specificity + rhs.1.specificity
                if l != r { return l > r }
                return (lhs.0.id, lhs.1.id) < (rhs.0.id, rhs.1.id)
            }
        for (a, b) in pairs {
            guard let fam = family(a), usedFamilies.insert(fam).inserted else { continue }
            // Order-independent id so both phones agree.
            let ids = [a.id, b.id].sorted()
            out.append(Candidate(id: "related:\(ids[0])|\(ids[1])", kind: .complementary,
                                 mine: a.label, theirs: b.label))
        }
        return out
    }

    /// Re-canonicalise from the label (like `InterestMatcher`) but keep the
    /// user's own wording.
    private static func canonical(_ interest: Interest) -> Interest? {
        guard let c = InterestCatalog.canonical(from: interest.label) else { return nil }
        return Interest(id: c.id, label: interest.label, parent: c.parent,
                        specificity: c.specificity, custom: c.custom)
    }

    /// The broad category an interest belongs to (itself, if it is broad).
    private static func family(_ interest: Interest) -> String? {
        if interest.specificity == 1, !interest.custom { return interest.id }
        return interest.parent
    }

    // MARK: Words

    private static let stopwords: Set<String> = [
        "about", "after", "again", "being", "better", "build", "doing", "every", "from", "getting",
        "have", "into", "just", "learn", "learning", "like", "love", "maybe", "meet", "more",
        "people", "really", "some", "start", "that", "their", "them", "there", "these", "thing",
        "things", "this", "want", "with", "would", "your", "someone", "hoping", "looking", "trying",
    ]

    static func contentWords(_ text: String) -> Set<String> {
        Set(Grounding.fold(text).split(separator: " ").map(String.init)
            .filter { $0.count >= 4 && !stopwords.contains($0) })
    }

    /// "climb" ~ "climbing", "robot" ~ "robotics": equal, or a shared prefix of
    /// at least five letters. Deliberately conservative.
    static func stemMatch(_ a: String, _ b: String) -> Bool {
        if a == b { return true }
        let n = min(a.count, b.count)
        guard n >= 5 else { return false }
        return a.hasPrefix(String(b.prefix(n))) || b.hasPrefix(String(a.prefix(n)))
    }

    // MARK: Deterministic phrasing

    /// Neutral wording — the same text is shown on both phones, so it never
    /// addresses only one of the two people.
    static func templatePrompt(for c: Candidate) -> String {
        let a = c.mine.trimmed(), b = c.theirs.trimmed()
        switch c.kind {
        case .shared:
            if Grounding.fold(a) == Grounding.fold(b) {
                return "How did each of you get into \(a.lowercasedFirstWord())?"
            }
            return "You both listed this (“\(a)” and “\(b)”). What's the story behind it for each of you?"
        case .complementary:
            if c.id.hasPrefix("goal:") {
                return "One of you listed “\(a)” and the other “\(b)”. Anything to swap notes on?"
            }
            return "One of you is into \(a.lowercasedFirstWord()) and the other \(b.lowercasedFirstWord()). Where do those overlap?"
        }
    }

    static func templatePoints(_ candidates: [Candidate], limit: Int = 4) -> [TalkingPoint] {
        candidates.prefix(limit).map {
            TalkingPoint(id: $0.id, kind: $0.kind, prompt: templatePrompt(for: $0),
                         yourEntry: $0.mine, theirEntry: $0.theirs, source: .fallbackTemplate)
        }
    }
}

private extension Set where Element == String {
    func isDisjoint(with other: Set<String>, matching: (String, String) -> Bool) -> Bool {
        !contains { a in other.contains { b in matching(a, b) } }
    }
}
