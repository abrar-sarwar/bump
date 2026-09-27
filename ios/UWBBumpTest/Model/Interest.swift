import Foundation

/// An interest the user can hold. `id` is the canonical key used for matching;
/// `label` is what a human reads. `parent` lets us tell "both like music" from
/// "both play jazz piano" and prefer the latter.
struct Interest: Codable, Hashable, Identifiable, Sendable {
    let id: String
    let label: String
    /// Canonical id of the broader category, if this is a specific interest.
    let parent: String?
    /// 1 = broad category, 2 = specific. Higher is more conversation-worthy.
    let specificity: Int
    /// True when the user typed this themselves rather than picking a chip.
    var custom: Bool = false
    /// Invisible catalogue ids a custom interest belongs to ("One Piece" ->
    /// ["anime", "manga"]), set once by Grok after onboarding. nil means not
    /// tagged yet; [] means tagged and nothing fitted. Optional so older
    /// profiles and older phones still decode.
    var tags: [String]?

    init(id: String, label: String, parent: String? = nil, specificity: Int = 1,
         custom: Bool = false, tags: [String]? = nil) {
        self.id = id
        self.label = label
        self.parent = parent
        self.specificity = specificity
        self.custom = custom
        self.tags = tags
    }
}

/// The browsable catalogue: broad topics people actually talk about, each
/// opening into common variations ("Coffee" → espresso, pour-over, cold brew…).
/// A broad topic and its variations never match each other as "shared"; they
/// become complementary talking points instead.
enum InterestCatalog {

    static let groups: [(category: Interest, children: [Interest])] = [
        group("music", "Music", [
            ("jazz", "Jazz"), ("hip-hop", "Hip-hop"), ("indie", "Indie"), ("electronic", "Electronic music"),
            ("kpop", "K-pop"), ("rnb", "R&B"), ("concerts", "Live music"), ("festivals", "Festivals"),
            ("instrument", "Playing an instrument"), ("producing", "Making music"), ("singing", "Singing"),
        ]),
        group("coffee", "Coffee", [
            ("espresso", "Espresso"), ("pour-over", "Pour-over"), ("cold-brew", "Cold brew"),
            ("lattes", "Lattes"), ("cafes", "Café hopping"), ("home-coffee", "Brewing coffee at home"),
        ]),
        group("food", "Food & drink", [
            ("cooking", "Cooking"), ("baking", "Baking"), ("restaurants", "Trying new restaurants"),
            ("spicy-food", "Spicy food"), ("street-food", "Street food"), ("brunch", "Brunch"),
            ("tea", "Tea"), ("matcha", "Matcha"), ("boba", "Boba"),
        ]),
        group("movement", "Sports & fitness", [
            ("gym", "Gym"), ("running", "Running"), ("climbing", "Climbing"), ("basketball", "Basketball"),
            ("soccer", "Soccer"), ("tennis", "Tennis"), ("yoga", "Yoga"), ("martial-arts", "Martial arts"),
            ("cycling", "Cycling"), ("dance", "Dancing"),
        ]),
        group("games", "Gaming", [
            ("rpgs", "RPGs"), ("shooters", "Shooters"), ("cozy-games", "Cozy games"), ("esports", "Esports"),
            ("retro-games", "Retro games"), ("board-games", "Board games"), ("chess", "Chess"),
            ("tabletop-rpgs", "Tabletop RPGs"),
        ]),
        group("screen", "Movies & TV", [
            ("movies", "Movies"), ("anime", "Anime"), ("horror", "Horror"), ("reality-tv", "Reality TV"),
            ("documentaries", "Documentaries"), ("youtube", "YouTube"),
        ]),
        group("collecting", "Collecting", [
            ("vinyl", "Vinyl records"), ("figures", "Figures"), ("trading-cards", "Trading cards"),
            ("sneakers", "Sneakers"), ("rocks", "Rocks & minerals"), ("coins", "Coins"), ("lego", "LEGO"),
            ("thrifting", "Thrifting"),
        ]),
        group("outdoors", "Outdoors", [
            ("hiking", "Hiking"), ("camping", "Camping"), ("beach", "Beach days"), ("surfing", "Surfing"),
            ("fishing", "Fishing"), ("plants", "Plants"), ("stargazing", "Stargazing"),
        ]),
        group("building", "Tech", [
            ("coding", "Coding"), ("ai", "AI"), ("startups", "Startups"), ("hardware", "Hardware"),
            ("robotics", "Robotics"), ("3d-printing", "3D printing"),
            ("mechanical-keyboards", "Mechanical keyboards"), ("game-dev", "Game dev"),
        ]),
        group("design", "Art & design", [
            ("drawing", "Drawing"), ("painting", "Painting"), ("photography", "Photography"),
            ("graphic-design", "Graphic design"), ("fashion", "Fashion"), ("crafts", "Crafts"),
            ("filmmaking", "Filmmaking"),
        ]),
        group("words", "Books & stories", [
            ("fiction", "Fiction"), ("scifi", "Sci-fi"), ("fantasy", "Fantasy"), ("manga", "Manga"),
            ("comics", "Comics"), ("poetry", "Poetry"), ("podcasts", "Podcasts"), ("writing", "Writing"),
        ]),
        group("travel", "Travel", [
            ("road-trips", "Road trips"), ("backpacking", "Backpacking"), ("languages", "Learning languages"),
            ("city-trips", "City trips"), ("food-trips", "Food trips"),
        ]),
    ]

    private static func group(_ id: String, _ label: String,
                              _ kids: [(String, String)]) -> (Interest, [Interest]) {
        let category = Interest(id: id, label: label, parent: nil, specificity: 1)
        let children = kids.map { Interest(id: $0.0, label: $0.1, parent: id, specificity: 2) }
        return (category, children)
    }

    static let all: [Interest] = groups.flatMap { [$0.category] + $0.children }

    /// The catalogue id that best describes an interest for theming: its
    /// first Grok tag, else its own catalogue entry, else its category.
    static func themeHint(for interest: Interest) -> String? {
        if let tag = interest.tags?.first, byID[tag] != nil { return tag }
        let canonical = canonical(from: interest.label)
        if let id = canonical?.id, byID[id] != nil { return id }
        return canonical?.parent ?? interest.parent
    }

    /// Theme hint for a reveal highlight ("chess", "related:anime", or a
    /// custom id, which falls back to `profile`'s tags for that entry).
    static func themeHint(forHighlight id: String, entry: String, in profile: [Interest]) -> String? {
        let bare = id.hasPrefix("related:") ? String(id.dropFirst(8)) : id
        if byID[bare] != nil { return bare }
        return profile.first { $0.label.lowercased() == entry.lowercased() }.flatMap(themeHint(for:))
    }
    static let byID: [String: Interest] = Dictionary(uniqueKeysWithValues: all.map { ($0.id, $0) })

    /// A small, readable synonym map so free text lands on a canonical interest
    /// where we can be confident. Only TRUE equivalents belong here: a synonym
    /// must never narrow a broad interest ("coffee" is not "espresso", "jazz" is
    /// not "jazz piano") or broaden a specific one ("karate" is not every martial
    /// art). Anything not listed keeps its own normalized id and can still match
    /// another user who typed the same thing.
    static let synonyms: [String: String] = [
        // music
        "hip hop": "hip-hop", "rap": "hip-hop", "edm": "electronic", "electronic": "electronic",
        "kpop": "kpop", "k pop": "kpop", "rnb": "rnb", "r and b": "rnb",
        "concerts": "concerts", "live shows": "concerts", "gigs": "concerts", "jazz music": "jazz",
        "music production": "producing", "making beats": "producing", "beatmaking": "producing",
        // coffee & food
        "cafes": "cafes", "cafe hopping": "cafes", "coffee shops": "cafes",
        "restaurants": "restaurants", "eating out": "restaurants", "bubble tea": "boba",
        // sports
        "the gym": "gym", "working out": "gym", "going to the gym": "gym", "rock climbing": "climbing",
        "biking": "cycling", "bicycling": "cycling", "dance": "dance",
        // games & screen
        "boardgames": "board-games", "dnd": "tabletop-rpgs", "d d": "tabletop-rpgs",
        "dungeons and dragons": "tabletop-rpgs", "films": "movies",
        // collecting (older profiles said "Collecting vinyl")
        "collecting vinyl": "vinyl", "vinyl": "vinyl", "records": "vinyl", "record collecting": "vinyl",
        "lps": "vinyl", "legos": "lego", "thrift shopping": "thrifting", "thrift": "thrifting",
        // outdoors, tech, words, travel
        "houseplants": "plants", "house plants": "plants", "programming": "coding",
        "artificial intelligence": "ai", "3d print": "3d-printing", "3dprinting": "3d-printing",
        "mechanical keyboard": "mechanical-keyboards",
        "sci fi": "scifi", "science fiction": "scifi", "comic books": "comics", "podcast": "podcasts",
        "language learning": "languages", "road trip": "road-trips",
    ]

    /// Things that are NOT equivalent to any catalogue entry but clearly belong
    /// to one of its broad topics. They keep their own id (so "karate" never
    /// matches "jiu jitsu" as a shared interest) and only gain a parent, which
    /// lets two related-but-different interests become a complementary talking
    /// point. Also keeps interests from older profiles (e.g. "Jazz piano") in
    /// the right family.
    static let parentHints: [String: String] = [
        // music
        "jazz piano": "music", "piano": "music", "guitar": "music", "drums": "music", "violin": "music",
        "keyboards": "music", "singing in a choir": "music", "choir": "music",
        // coffee & food
        "latte art": "coffee", "sourdough": "food", "baking sourdough": "food", "bread baking": "food",
        "baking bread": "food", "fermenting": "food", "fermenting things": "food", "hot sauce": "food",
        "making hot sauce": "food", "ramen": "food", "hunting good ramen": "food", "sushi": "food",
        // sports
        "bouldering": "movement", "karate": "movement", "bjj": "movement", "jiu jitsu": "movement",
        "judo": "movement", "boxing": "movement", "jogging": "movement", "distance running": "movement",
        "weightlifting": "movement", "pilates": "movement", "swimming": "movement", "golf": "movement",
        "volleyball": "movement", "skateboarding": "movement", "snowboarding": "movement",
        "skiing": "movement", "swing dancing": "movement", "climbing gym": "movement",
        // games & screen
        "video games": "games", "minecraft": "games", "nintendo": "games", "pokemon": "games",
        "speedrunning": "games", "roguelikes": "games", "game jams": "games", "tabletop": "games",
        "tv shows": "screen", "k dramas": "screen", "sitcoms": "screen", "netflix": "screen",
        // collecting
        "pokemon cards": "collecting", "action figures": "collecting", "anime figures": "collecting",
        "stamps": "collecting", "plushies": "collecting", "crystals": "collecting",
        // outdoors
        "night hiking": "outdoors", "kayaking": "outdoors", "sea kayaking": "outdoors",
        "birding": "outdoors", "bird watching": "outdoors", "gardening": "outdoors",
        // tech
        "retro computing": "building", "home labs": "building", "electronics": "building",
        // art
        "typography": "design", "lettering": "design", "calligraphy": "design", "ux research": "design",
        "industrial design": "design", "making zines": "design", "woodworking": "design",
        // words
        "reading": "words", "audiobooks": "words", "journaling": "words", "history podcasts": "words",
    ]

    /// Normalize free text to a canonical interest.
    ///
    /// Case and whitespace are folded, punctuation dropped. If the text matches a
    /// known label or synonym we adopt that canonical interest (and its parent
    /// category, so specificity ranking still works). Otherwise we keep it as a
    /// custom interest keyed on its own normalized text — two people who type
    /// the same unusual thing will still match.
    static func canonical(from raw: String) -> Interest? {
        let key = normalize(raw)
        guard !key.isEmpty else { return nil }

        if let id = synonyms[key], let known = byID[id] { return known }
        if let known = byID[key] { return known }
        if let known = all.first(where: { normalize($0.label) == key }) { return known }

        // Unknown: a custom, specific interest. Not invented — it is exactly what
        // the user typed, just normalized. A parent hint only groups it for
        // complementary talking points; it never changes what it matches.
        return Interest(id: "custom:\(key)", label: raw.trimmed(), parent: parentHints[key],
                        specificity: 2, custom: true)
    }

    static func normalize(_ raw: String) -> String {
        raw.lowercased()
            .folding(options: [.diacriticInsensitive], locale: .current)
            .components(separatedBy: CharacterSet.alphanumerics.union(.whitespaces).inverted)
            .joined(separator: " ")
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }
}

extension String {
    func trimmed() -> String { trimmingCharacters(in: .whitespacesAndNewlines) }
}
