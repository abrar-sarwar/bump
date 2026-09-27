import Foundation

/// What an onboarding question is FOR, owned by the app. Grok may phrase the
/// question, but the app decides which topic comes next and refuses anything
/// that re-asks a topic already covered, however it is worded.
///
/// Before this, the only duplicate check was exact text equality, so "What
/// specific shows and movies are you into?" and "What are more shows and
/// movies you're into?" both passed, and Grok alone chose the topic.
enum OnboardingTopic: String, Codable, CaseIterable, Sendable {
    case introDetail = "intro.detail"               // one follow-up on something from the intro
    case music = "music.artists"
    case coffee = "coffee.preferences"
    case food = "food.preferences"
    case sports = "sports.activities"
    case games = "games.titles"
    case entertainment = "entertainment.specific_titles"
    case collecting = "collecting.items"
    case outdoors = "outdoors.activities"
    case tech = "tech.projects"
    case art = "art.practice"
    case books = "books.titles"
    case travel = "travel.places"
    case goals = "goals.meet"
    case work = "experience.work"

    /// The catalogue category this topic clarifies, if any.
    var category: String? {
        switch self {
        case .music: return "music"
        case .coffee: return "coffee"
        case .food: return "food"
        case .sports: return "movement"
        case .games: return "games"
        case .entertainment: return "screen"
        case .collecting: return "collecting"
        case .outdoors: return "outdoors"
        case .tech: return "building"
        case .art: return "design"
        case .books: return "words"
        case .travel: return "travel"
        case .introDetail, .goals, .work: return nil
        }
    }

    static func forCategory(_ id: String) -> OnboardingTopic? {
        allCases.first { $0.category == id }
    }

    /// Plain description sent to Grok so it phrases a question for THIS topic.
    var purpose: String {
        switch self {
        case .introDetail: return "one detail about something they mentioned in their intro"
        case .music: return "which artists, genres or scenes they listen to"
        case .coffee: return "how they take their coffee or where they get it"
        case .food: return "which foods or drinks they love"
        case .sports: return "which sport or activity keeps them moving"
        case .games: return "which games they play"
        case .entertainment: return "which specific shows, films or anime they watch"
        case .collecting: return "what they collect"
        case .outdoors: return "what they like doing outdoors"
        case .tech: return "what they are building or tinkering with"
        case .art: return "what art or design they make or love"
        case .books: return "which books, writers or podcasts they love"
        case .travel: return "where they have travelled or want to go"
        case .goals: return "what they hope to get out of meeting people here"
        case .work: return "what they are working on or studying"
        }
    }

    /// Deterministic question used whenever a generated one is missing,
    /// repeats, or drifts to another topic.
    var fallback: String {
        switch self {
        case .introDetail: return "What's something from your intro you could talk about for hours?"
        case .music: return "You mentioned music. What artist, genre, or scene are you into?"
        case .coffee: return "How do you take your coffee, and where's your go-to spot?"
        case .food: return "What's one food or drink you could talk about for hours?"
        case .sports: return "What's your sport or way of staying active?"
        case .games: return "What are you playing at the moment?"
        case .entertainment: return "What's something you've been watching lately?"
        case .collecting: return "What do you collect, and what got you started?"
        case .outdoors: return "What do you like doing outside, and where?"
        case .tech: return "What are you building or tinkering with right now?"
        case .art: return "What kind of art or design do you make or love?"
        case .books: return "What's a book, writer, or podcast you keep recommending?"
        case .travel: return "Where's the best place you've been, or where are you going next?"
        case .goals: return "What are you hoping to get out of meeting people here?"
        case .work: return "What are you working on or studying these days?"
        }
    }

    /// Words that mark a question as being about this topic.
    private var keywords: [String] {
        switch self {
        case .introDetail: return []
        case .music: return ["music", "artist", "artists", "band", "bands", "song", "songs", "listen", "listening", "genre", "album", "concert"]
        case .coffee: return ["coffee", "espresso", "latte", "cafe", "brew"]
        case .food: return ["food", "foods", "eat", "eating", "cook", "cooking", "dish", "restaurant", "cuisine", "bake", "drink"]
        case .sports: return ["sport", "sports", "active", "gym", "run", "running", "train", "training", "workout", "team"]
        case .games: return ["game", "games", "gaming", "playing", "play"]
        case .entertainment: return ["show", "shows", "movie", "movies", "film", "films", "anime", "series", "watch", "watching", "tv"]
        case .collecting: return ["collect", "collecting", "collection"]
        case .outdoors: return ["outside", "outdoors", "hike", "hiking", "camping", "nature"]
        case .tech: return ["build", "building", "tinker", "tinkering", "code", "coding", "project", "tech"]
        case .art: return ["art", "design", "draw", "drawing", "paint", "painting", "make"]
        case .books: return ["book", "books", "read", "reading", "writer", "author", "podcast", "podcasts"]
        case .travel: return ["travel", "trip", "trips", "place", "visited", "country", "city"]
        case .goals: return ["hoping", "hope", "looking", "meet", "meeting", "goal", "get out of"]
        case .work: return ["work", "working", "job", "study", "studying", "career", "role"]
        }
    }

    /// Best guess at what a question is about, from its words. nil when no
    /// topic's words appear.
    static func classify(_ question: String) -> OnboardingTopic? {
        let words = " " + Grounding.fold(question) + " "
        var best: (OnboardingTopic, Int)?
        for topic in allCases {
            let hits = topic.keywords.filter { words.contains(" \($0) ") }.count
            if hits > 0, hits > (best?.1 ?? 0) { best = (topic, hits) }
        }
        return best?.0
    }
}

/// Pure rules for onboarding progression, so they are unit-tested.
enum OnboardingPlan {

    private static let stopwords: Set<String> = [
        "a", "an", "the", "and", "or", "of", "to", "in", "on", "for", "with", "at", "by", "about",
        "what", "whats", "which", "who", "how", "where", "when", "why", "do", "does", "did", "is",
        "are", "was", "you", "your", "youre", "you've", "youve", "i", "me", "my", "it", "that",
        "this", "these", "those", "into", "some", "any", "more", "most", "specific", "really",
        "lately", "these", "days", "right", "now", "one", "thing", "things", "like", "love",
        "enjoy", "been", "be", "can", "could", "would", "tell", "us", "share", "else", "other",
    ]

    static func contentWords(_ s: String) -> Set<String> {
        Set(Grounding.fold(s).split(separator: " ").map(String.init).filter { !stopwords.contains($0) && $0.count > 1 })
    }

    /// True when two questions ask essentially the same thing.
    static func isParaphrase(_ a: String, _ b: String) -> Bool {
        if Grounding.fold(a) == Grounding.fold(b) { return true }
        let x = contentWords(a), y = contentWords(b)
        guard !x.isEmpty, !y.isEmpty else { return false }
        let overlap = Double(x.intersection(y).count) / Double(x.union(y).count)
        return overlap >= 0.5
    }

    /// Topics the person has already given specific information about. A
    /// specific interest in a category (Anime under Movies & TV) covers it;
    /// a broad one ("Movies & TV") is worth one clarifying question.
    static func covered(by known: [(kind: ProfileFact.Kind, label: String)]) -> Set<OnboardingTopic> {
        var out = Set<OnboardingTopic>()
        for fact in known {
            switch fact.kind {
            case .goal: out.insert(.goals)
            case .experience: out.insert(.work)
            case .interest:
                guard let i = InterestCatalog.canonical(from: fact.label), i.specificity == 2,
                      let parent = i.parent, let t = OnboardingTopic.forCategory(parent) else { continue }
                out.insert(t)
            }
        }
        return out
    }

    /// The next topic to ask about, chosen by the app. Order: clarify a broad
    /// interest the person named, then goals, then work. nil means finish.
    static func next(known: [(kind: ProfileFact.Kind, label: String)],
                     asked: [OnboardingTopic], remaining: Int) -> OnboardingTopic? {
        guard remaining > 0 else { return nil }
        let done = Set(asked).union(covered(by: known))
        let broad = known.filter { $0.kind == .interest }
            .compactMap { InterestCatalog.canonical(from: $0.label) }
            .filter { $0.specificity == 1 && !$0.custom }
            .compactMap { OnboardingTopic.forCategory($0.id) }
        for t in broad where !done.contains(t) { return t }
        if !done.contains(.goals) { return .goals }
        if !done.contains(.work) { return .work }
        return nil
    }

    /// Accept a generated question for `topic`, or nil (the caller then uses
    /// the topic's fallback). Rejects exact and near repeats of anything
    /// already asked, and questions that drift to another topic that is
    /// already asked or covered.
    static func accept(_ generated: String?, for topic: OnboardingTopic,
                       askedQuestions: [String], askedTopics: [OnboardingTopic],
                       covered: Set<OnboardingTopic>) -> String? {
        guard let q = Grounding.question(generated, notIn: askedQuestions) else { return nil }
        if askedQuestions.contains(where: { isParaphrase($0, q) }) { return nil }
        if let about = OnboardingTopic.classify(q), about != topic,
           askedTopics.contains(about) || covered.contains(about) { return nil }
        return q
    }

    /// Grok's own in-depth follow-up, kept unless it repeats: an exact or near
    /// copy of an earlier question, or the same topic asked again (three
    /// "what shows do you like?" in a row).
    static func acceptFollowUp(_ generated: String?, askedQuestions: [String],
                               askedTopics: [OnboardingTopic]) -> String? {
        guard let q = Grounding.question(generated, notIn: askedQuestions) else { return nil }
        if askedQuestions.contains(where: { isParaphrase($0, q) }) { return nil }
        if let about = OnboardingTopic.classify(q), askedTopics.contains(about) { return nil }
        return q
    }

    /// The question to show for `topic`: the generated one if acceptable,
    /// otherwise the fixed fallback, and nil if even that would repeat.
    static func question(for topic: OnboardingTopic, generated: String?,
                         askedQuestions: [String], askedTopics: [OnboardingTopic],
                         covered: Set<OnboardingTopic>) -> String? {
        if let q = accept(generated, for: topic, askedQuestions: askedQuestions,
                          askedTopics: askedTopics, covered: covered) { return q }
        let fallback = topic.fallback
        return askedQuestions.contains(where: { isParaphrase($0, fallback) }) ? nil : fallback
    }
}
