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
        // Index by canonical id, keeping the user's own wording as evidence.
        let mineByID = index(a.interests)
        let theirsByID = index(b.interests)

        let sharedIDs = Set(mineByID.keys).intersection(theirsByID.keys)
        guard !sharedIDs.isEmpty else { return [] }

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

        return highlights
            .sorted {
                if $0.specificity != $1.specificity { return $0.specificity > $1.specificity }
                return $0.interestID < $1.interestID     // stable, so both phones agree
            }
            .prefix(limit)
            .map { $0 }
    }

    private static func index(_ interests: [Interest]) -> [String: Interest] {
        var out: [String: Interest] = [:]
        for interest in interests {
            // Re-normalize on the way in: a profile may hold raw custom text.
            guard let canonical = InterestCatalog.canonical(from: interest.label) else { continue }
            // Keep the user's own wording for evidence, but key on the canonical id.
            out[canonical.id] = Interest(
                id: canonical.id, label: interest.label,
                parent: canonical.parent, specificity: canonical.specificity,
                custom: canonical.custom
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
