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

    init(id: String, label: String, parent: String? = nil, specificity: Int = 1, custom: Bool = false) {
        self.id = id
        self.label = label
        self.parent = parent
        self.specificity = specificity
        self.custom = custom
    }
}

/// The starter catalogue. Deliberately mixes broad categories with the kind of
/// specific interest that actually produces a conversation.
enum InterestCatalog {

    static let groups: [(category: Interest, children: [Interest])] = [
        group("music", "Music", [
            ("jazz-piano", "Jazz piano"), ("vinyl", "Collecting vinyl"),
            ("producing", "Making beats"), ("choir", "Singing in a choir"),
            ("concerts", "Live shows"),
        ]),
        group("outdoors", "Outdoors", [
            ("night-hiking", "Night hiking"), ("bouldering", "Bouldering"),
            ("birding", "Birding"), ("sea-kayaking", "Sea kayaking"),
            ("camping", "Camping"),
        ]),
        group("games", "Games", [
            ("speedrunning", "Speedrunning"), ("board-games", "Board games"),
            ("chess", "Chess"), ("game-jams", "Game jams"),
            ("roguelikes", "Roguelikes"),
        ]),
        group("food", "Food", [
            ("sourdough", "Baking sourdough"), ("hot-sauce", "Making hot sauce"),
            ("espresso", "Espresso"), ("ramen", "Hunting good ramen"),
            ("fermenting", "Fermenting things"),
        ]),
        group("design", "Design", [
            ("typography", "Typography"), ("industrial-design", "Industrial design"),
            ("zines", "Making zines"), ("ux", "UX research"),
        ]),
        group("building", "Building things", [
            ("3d-printing", "3D printing"), ("mechanical-keyboards", "Mechanical keyboards"),
            ("retro-computing", "Retro computing"), ("robotics", "Robotics"),
            ("home-lab", "Home labs"),
        ]),
        group("words", "Reading & writing", [
            ("scifi", "Science fiction"), ("poetry", "Poetry"),
            ("journaling", "Journaling"), ("history-podcasts", "History podcasts"),
        ]),
        group("movement", "Movement", [
            ("climbing", "Climbing"), ("running", "Distance running"),
            ("swing-dance", "Swing dancing"), ("martial-arts", "Martial arts"),
            ("cycling", "Cycling"),
        ]),
    ]

    private static func group(_ id: String, _ label: String,
                              _ kids: [(String, String)]) -> (Interest, [Interest]) {
        let category = Interest(id: id, label: label, parent: nil, specificity: 1)
        let children = kids.map { Interest(id: $0.0, label: $0.1, parent: id, specificity: 2) }
        return (category, children)
    }

    static let all: [Interest] = groups.flatMap { [$0.category] + $0.children }
    static let byID: [String: Interest] = Dictionary(uniqueKeysWithValues: all.map { ($0.id, $0) })

    /// A small, readable synonym map so free text lands on a canonical interest
    /// where we can be confident. Anything not listed keeps its own normalized
    /// id and can still match another user who typed the same thing.
    static let synonyms: [String: String] = [
        "piano jazz": "jazz-piano", "jazz": "jazz-piano", "jazz pianist": "jazz-piano",
        "records": "vinyl", "record collecting": "vinyl", "lps": "vinyl",
        "beatmaking": "producing", "music production": "producing", "producer": "producing",
        "hiking at night": "night-hiking", "moonlight hiking": "night-hiking",
        "climbing gym": "bouldering", "boulder": "bouldering",
        "bird watching": "birding", "birdwatching": "birding",
        "kayaking": "sea-kayaking",
        "speed running": "speedrunning", "speed runs": "speedrunning", "any%": "speedrunning",
        "boardgames": "board-games", "tabletop": "board-games",
        "sourdough": "sourdough", "bread baking": "sourdough", "baking bread": "sourdough",
        "coffee": "espresso", "latte art": "espresso", "pour over": "espresso",
        "type design": "typography", "fonts": "typography", "lettering": "typography",
        "3d print": "3d-printing", "3dprinting": "3d-printing",
        "keyboards": "mechanical-keyboards", "keycaps": "mechanical-keyboards",
        "retro computers": "retro-computing", "vintage computing": "retro-computing",
        "sci-fi": "scifi", "science fiction": "scifi", "scifi books": "scifi",
        "lindy hop": "swing-dance", "swing dancing": "swing-dance",
        "marathon": "running", "5k": "running", "jogging": "running",
        "bjj": "martial-arts", "jiu jitsu": "martial-arts", "karate": "martial-arts",
        "biking": "cycling", "road cycling": "cycling",
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
        // the user typed, just normalized.
        return Interest(id: "custom:\(key)", label: raw.trimmed(), parent: nil, specificity: 2, custom: true)
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
