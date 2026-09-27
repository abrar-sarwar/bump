import Foundation

/// On-phone profile drafting: used when the person chose "keep it on this
/// phone", and whenever Grok is unavailable, slow or returns something invalid.
///
/// Deliberately simple and conservative. It only suggests what the text
/// literally contains — catalogue interests it can find word for word, and
/// clauses that plainly state a goal or an experience — and every suggestion
/// carries the exact words it came from. The person approves everything.
enum LocalDrafter {

    struct Suggestion: Equatable, Sendable {
        let kind: ProfileFact.Kind
        let label: String
        let source: String
    }

    // MARK: Extraction

    static func extract(from text: String) -> [Suggestion] {
        let sentences = splitSentences(text)
        var out: [Suggestion] = []
        var seen = Set<String>()
        func add(_ s: Suggestion) {
            let key = "\(s.kind.rawValue)|\(Grounding.fold(s.label))"
            if seen.insert(key).inserted { out.append(s) }
        }

        for sentence in sentences {
            // Only positive statements about the speaker: "I don't drink
            // coffee" and "my friend loves anime" are not interests.
            for clause in Grounding.affirmativeClauses(sentence) {
                for interest in interests(in: clause) {
                    add(Suggestion(kind: .interest, label: interest.label, source: sentence))
                }
            }
            if let clause = clause(in: sentence, after: goalTriggers) {
                add(Suggestion(kind: .goal, label: clip(clause), source: clause))
            }
            if let clause = clause(in: sentence, from: experienceTriggers) {
                add(Suggestion(kind: .experience, label: clip(clause), source: clause))
            }
        }
        return out
    }

    /// Catalogue interests named in `sentence`, longest match first, so "jazz
    /// piano" wins over "jazz" and "espresso" never appears because of "coffee".
    static func interests(in sentence: String) -> [Interest] {
        let words = Grounding.fold(sentence).split(separator: " ").map(String.init)
        guard !words.isEmpty else { return [] }

        var keys: [(key: [String], id: String)] = InterestCatalog.all.map {
            (Grounding.fold($0.label).split(separator: " ").map(String.init), $0.id)
        }
        keys += InterestCatalog.synonyms.map { ($0.key.split(separator: " ").map(String.init), $0.value) }
        keys.sort { $0.key.count > $1.key.count }

        var taken = Array(repeating: false, count: words.count)
        var found: [Interest] = []
        for (key, id) in keys where !key.isEmpty && key.count <= words.count {
            for start in 0...(words.count - key.count) {
                let range = start..<(start + key.count)
                guard Array(words[range]) == key, !range.contains(where: { taken[$0] }) else { continue }
                range.forEach { taken[$0] = true }
                if let interest = InterestCatalog.byID[id], !found.contains(interest) {
                    found.append(interest)
                }
            }
        }
        return found
    }

    private static let goalTriggers = [
        "i want to", "i'd like to", "i would like to", "i'm hoping to", "i am hoping to",
        "hoping to", "i'm looking to", "looking to", "i hope to", "my goal is to", "i'm trying to",
    ]
    private static let experienceTriggers = [
        "i work", "i'm a ", "i am a ", "i'm an ", "i am an ", "i study", "i studied", "i've been",
        "i have been", "i built", "i used to", "i run ", "i teach",
    ]

    /// The clause that FOLLOWS a goal trigger, e.g. "meet people building robots".
    private static func clause(in sentence: String, after triggers: [String]) -> String? {
        let lower = sentence.lowercased().replacingOccurrences(of: "\u{2019}", with: "'")
        for trigger in triggers {
            guard let r = lower.range(of: trigger) else { continue }
            let offset = lower.distance(from: lower.startIndex, to: r.upperBound)
            let rest = String(sentence.dropFirst(offset)).trimmed()
            let cut = rest.split(whereSeparator: { ",;".contains($0) }).first.map(String.init) ?? rest
            let clause = cut.trimmed()
            if clause.count >= 3 { return clause }
        }
        return nil
    }

    /// The clause STARTING at an experience trigger, e.g. "I work at a robotics lab".
    private static func clause(in sentence: String, from triggers: [String]) -> String? {
        let lower = sentence.lowercased().replacingOccurrences(of: "\u{2019}", with: "'")
        for trigger in triggers {
            guard let r = lower.range(of: trigger) else { continue }
            let offset = lower.distance(from: lower.startIndex, to: r.lowerBound)
            let rest = String(sentence.dropFirst(offset))
            let cut = rest.split(whereSeparator: { ",;".contains($0) }).first.map(String.init) ?? rest
            let clause = cut.trimmed()
            if clause.count >= 6 { return clause }
        }
        return nil
    }

    private static func clip(_ s: String) -> String {
        let limit = BumpAPIClient.Limit.label
        guard s.count > limit else { return s.prefix(1).uppercased() + s.dropFirst() }
        let head = String(s.prefix(limit))
        let trimmed = head.range(of: " ", options: .backwards).map { String(head[..<$0.lowerBound]) } ?? head
        return trimmed.prefix(1).uppercased() + trimmed.dropFirst()
    }

    static func splitSentences(_ text: String) -> [String] {
        text.components(separatedBy: CharacterSet(charactersIn: ".!?\n"))
            .map { $0.trimmed() }
            .filter { !$0.isEmpty }
    }

    // MARK: Follow-up questions

    /// Category questions, asked only when the person named the broad category
    /// but nothing specific inside it — so we never ask for what they already said.
    static let categoryQuestions: [String: String] = [
        "music": "You mentioned music. What artist, genre, or scene are you into?",
        "coffee": "How do you take your coffee, and where's your go-to spot?",
        "food": "What's one food or drink you could talk about for hours?",
        "movement": "What's your sport or way of staying active?",
        "games": "What are you playing at the moment?",
        "screen": "What's something you've been watching lately?",
        "collecting": "What do you collect, and what got you started?",
        "outdoors": "What do you like doing outside, and where?",
        "building": "What are you building or tinkering with right now?",
        "design": "What kind of art or design do you make or love?",
        "words": "What's a book, writer, or podcast you keep recommending?",
        "travel": "Where's the best place you've been, or where are you going next?",
    ]
    static let goalQuestion = "What are you hoping to get out of meeting people here?"
    static let experienceQuestion = "What are you working on or studying these days?"

    /// The next useful question, or nil when there's nothing worth asking.
    static func nextQuestion(known: [(kind: ProfileFact.Kind, label: String)], asked: [String],
                             maxQuestions: Int = 3) -> String? {
        guard asked.count < maxQuestions else { return nil }
        let askedFolded = Set(asked.map(Grounding.fold))
        func fresh(_ q: String) -> String? { askedFolded.contains(Grounding.fold(q)) ? nil : q }

        let interests = known.filter { $0.kind == .interest }.compactMap { InterestCatalog.canonical(from: $0.label) }
        let specificParents = Set(interests.filter { $0.specificity == 2 }.compactMap(\.parent))
        for broad in interests where broad.specificity == 1 && !broad.custom
            && !specificParents.contains(broad.id) {
            if let q = categoryQuestions[broad.id].flatMap(fresh) { return q }
        }
        if !known.contains(where: { $0.kind == .goal }), let q = fresh(goalQuestion) { return q }
        if !known.contains(where: { $0.kind == .experience }), let q = fresh(experienceQuestion) { return q }
        return nil
    }
}
