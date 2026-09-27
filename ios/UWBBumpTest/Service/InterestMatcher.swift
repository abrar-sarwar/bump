import Foundation

/// Computes GROUNDED overlap between two profiles. Pure and synchronous, so it
/// is fully unit-testable.
///
/// Rules:
///  - An interest is shared only when it appears in BOTH profiles after
///    normalization. Nothing is inferred, extrapolated or invented.
///  - Specific beats broad: "you both play jazz piano" ranks above "you both
///    like music", and a broad category is suppressed entirely when a specific
///    child of it already matched.
///  - Every highlight carries the exact entry from each profile that supports it.
///
/// Deliberately NOT done: rarity percentages. We have no population data, so any
/// "only 1% of people share this" claim would be fabricated. We rank by
/// specificity and say so.
enum InterestMatcher {

    static func overlap(_ a: SharedProfile, _ b: SharedProfile, limit: Int = 3) -> [SharedHighlight] {
        overlap(a.interests, b.interests, limit: limit)
    }

    /// Same grounded-overlap logic, taking raw interest lists directly — lets a
    /// caller compute overlap without constructing a SharedProfile just to
    /// hold an interest list. StreetPass's ambient peer payload is not a
    /// SharedProfile (it carries no bio, no experiences/goals, no evidence).
    static func overlap(_ mine: [Interest], _ theirs: [Interest], limit: Int = 3) -> [SharedHighlight] {
        // Index by canonical id, keeping the user's own wording as evidence.
        let mineByID = index(mine)
        let theirsByID = index(theirs)

        let sharedIDs = Set(mineByID.keys).intersection(theirsByID.keys)
        guard !sharedIDs.isEmpty else {
            return Array(broader(mineByID, theirsByID, excluding: []).prefix(limit))
        }

        // Suppress a broad category when one of its specific children matched,
        // including custom interests that belong to it ("Jazz piano" → Music).
        let matchedParents: Set<String> = Set(sharedIDs.compactMap { id in
            guard let interest = mineByID[id], interest.specificity == 2 else { return nil }
            return interest.parent
        })

        let highlights: [SharedHighlight] = sharedIDs.compactMap { id -> SharedHighlight? in
            guard let mine = mineByID[id], let theirs = theirsByID[id] else { return nil }
            if matchedParents.contains(id) { return nil }
            return SharedHighlight(
                interestID: id,
                statement: statement(for: mine),
                yourEntry: mine.label,
                theirEntry: theirs.label,
                specificity: mine.specificity
            )
        }

        let exact = highlights
            .sorted {
                if $0.specificity != $1.specificity { return $0.specificity > $1.specificity }
                return $0.interestID < $1.interestID     // stable, so both phones agree
            }
        // Exact matches first; related interests fill any remaining room.
        let covered = sharedIDs.union(matchedParents)
            .union(sharedIDs.compactMap { mineByID[$0]?.parent })
        return Array((exact + broader(mineByID, theirsByID, excluding: covered)).prefix(limit))
    }

    /// Different interests that share a wider one: "One Piece" and "Naruto"
    /// are both anime. Uses each interest's Grok tags and catalogue parent.
    /// Still grounded: the evidence is each person's own entry, and the claim
    /// is only the category they both belong to.
    /// Broad catalogue topics a profile belongs to: its tags, catalogue picks
    /// and their parents. This is all "Show what we have in common" shares.
    static func topics(_ interests: [Interest]) -> Set<String> {
        var out = Set<String>()
        for interest in interests {
            let canonical = InterestCatalog.canonical(from: interest.label)
            var ids = interest.tags ?? []
            if let id = canonical?.id, InterestCatalog.byID[id] != nil { ids.append(id) }
            if let parent = canonical?.parent ?? interest.parent { ids.append(parent) }
            ids += ids.compactMap { InterestCatalog.byID[$0]?.parent }
            out.formUnion(ids.filter { InterestCatalog.byID[$0] != nil })
        }
        return out
    }

    /// Readable shared topics, most specific first, with a broad topic left
    /// out when one of its children is already listed.
    static func sharedTopicLabels(_ a: Set<String>, _ b: Set<String>) -> [String] {
        let shared = a.intersection(b)
        let redundant = Set(shared.compactMap { InterestCatalog.byID[$0]?.parent })
        return shared.subtracting(redundant)
            .compactMap { InterestCatalog.byID[$0] }
            .sorted { $0.specificity != $1.specificity ? $0.specificity > $1.specificity : $0.id < $1.id }
            .map { lowercasedFirst($0.label) }
    }

    static func broader(_ mine: [String: Interest], _ theirs: [String: Interest],
                        excluding covered: Set<String>) -> [SharedHighlight] {
        func index(_ interests: [String: Interest]) -> [String: String] {
            var out: [String: String] = [:]     // category id -> user's label
            for (id, interest) in interests.sorted(by: { $0.key < $1.key }) {
                var ids = interest.tags ?? []
                if InterestCatalog.byID[id] != nil { ids.append(id) }
                ids += ids.compactMap { InterestCatalog.byID[$0]?.parent }
                if let parent = interest.parent { ids.append(parent) }
                for c in ids where out[c] == nil { out[c] = interest.label }
            }
            return out
        }
        let a = index(mine), b = index(theirs)
        let shared = Set(a.keys).intersection(b.keys).subtracting(covered)
        // A specific shared category (anime) makes its broad parent (Movies &
        // TV) redundant.
        let redundant = Set(shared.compactMap { InterestCatalog.byID[$0]?.parent })
        return shared.subtracting(redundant).compactMap { id -> SharedHighlight? in
            guard let category = InterestCatalog.byID[id], let yours = a[id], let theirs = b[id],
                  yours.lowercased() != theirs.lowercased() else { return nil }
            return SharedHighlight(
                interestID: "related:\(id)",
                statement: "You're both into \(lowercasedFirst(category.label)).",
                yourEntry: yours,
                theirEntry: theirs,
                specificity: 1
            )
        }
        .sorted {
            let sa = InterestCatalog.byID[String($0.interestID.dropFirst(8))]?.specificity ?? 0
            let sb = InterestCatalog.byID[String($1.interestID.dropFirst(8))]?.specificity ?? 0
            if sa != sb { return sa > sb }                // anime before Movies & TV
            return $0.interestID < $1.interestID
        }
    }

    private static func index(_ interests: [Interest]) -> [String: Interest] {
        var out: [String: Interest] = [:]
        for interest in interests {
            // Re-normalize on the way in: a profile may hold raw custom text.
            guard let canonical = InterestCatalog.canonical(from: interest.label) else { continue }
            // Keep the user's own wording for evidence, but key on the canonical id.
            out[canonical.id] = Interest(
                id: canonical.id, label: interest.label,
                parent: canonical.parent ?? interest.parent, specificity: canonical.specificity,
                custom: canonical.custom, tags: interest.tags
            )
        }
        return out
    }

    /// Phrasing that stays true to what we actually know.
    private static func statement(for interest: Interest) -> String {
        let label = interest.label.trimmed()
        if interest.specificity >= 2 {
            return "You're both into \(lowercasedFirst(label))."
        }
        return "You both like \(lowercasedFirst(label))."
    }

    private static func lowercasedFirst(_ s: String) -> String {
        // Keep acronyms and proper nouns intact; only downcase an ordinary
        // leading capital so the sentence reads naturally.
        guard let first = s.first, first.isUppercase,
              s.dropFirst().prefix(1).allSatisfy({ $0.isLowercase || $0.isWhitespace })
        else { return s }
        return s.prefix(1).lowercased() + s.dropFirst()
    }
}
