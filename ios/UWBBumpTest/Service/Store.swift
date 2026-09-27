import Foundation

/// Local persistence: profile + saved connections as JSON in Application
/// Support. No account, no database dependency, nothing synced anywhere.
@MainActor
final class Store: ObservableObject {

    @Published var profile: Profile {
        didSet { persist(profile, to: Self.profileURL) }
    }
    @Published private(set) var connections: [SavedConnection] {
        didSet { persist(connections, to: Self.connectionsURL) }
    }
    /// People seen nearby without a bump, newest first. Local only.
    @Published private(set) var streetpasses: [StreetpassEvent] {
        didSet { persist(streetpasses, to: Self.streetpassesURL) }
    }
    /// Private per-connection ratings, keyed by `SavedConnection.id`. Local only:
    /// never exchanged with a partner and never sent to the BUMP server.
    /// Persisted as a flat array, not as a dictionary: `UUID` is not a string
    /// coding key, so `[UUID: _]` would encode as an alternating key/value array
    /// that is unreadable on disk. The dictionary is the in-memory index.
    @Published private(set) var ratings: [UUID: InteractionRating] {
        didSet { persist(Array(ratings.values).sorted { $0.ratedOn > $1.ratedOn },
                         to: Self.ratingsURL) }
    }
    /// Developer/testing settings, persisted so a tuning session survives a relaunch.
    @Published var settings: Settings {
        didSet { persist(settings, to: Self.settingsURL) }
    }
    /// Cloud-processing choice. Local only: it is never part of the profile and
    /// only a yes/no capability ever reaches a confirmed partner.
    @Published var privacy: PrivacyPreferences {
        didSet { persist(privacy, to: Self.privacyURL) }
    }

    struct Settings: Codable, Equatable {
        var motionThreshold: Double = 20.0
        var motionCooldown: TimeInterval = 1.5
        var pairingWindow: TimeInterval = 0.500
        var ambiguityMargin: TimeInterval = 0.050
        var pairingBuffer: TimeInterval = 0.250
        var uwbProximity: Double = 0.15
        var uwbFreshness: TimeInterval = 1.5
        var detectionMode: DetectionMode = .combined
        /// Overrides the build's `BumpAPIBaseURL` (e.g. your Mac's LAN address
        /// when testing on a phone). Optional, so older settings files still load.
        var apiBaseURL: String?
        /// How phones reach each other. nil means automatic: the BUMP server's
        /// relay when it answers, Multipeer otherwise. Optional so older
        /// settings files still load.
        var transport: TransportPreference?

        enum TransportPreference: String, Codable, CaseIterable, Identifiable {
            case automatic, server, nearby
            var id: String { rawValue }
            var label: String {
                switch self {
                case .automatic: return "Automatic"
                case .server: return "Server only"
                case .nearby: return "Nearby only"
                }
            }
        }

        enum DetectionMode: String, Codable, CaseIterable, Identifiable {
            case motionOnly, uwbOnly, combined
            var id: String { rawValue }
            var label: String {
                switch self {
                case .motionOnly: return "Motion only"
                case .uwbOnly: return "UWB only"
                case .combined: return "Combined"
                }
            }
        }
    }

    private static let directory: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("BUMP", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }()
    private static let profileURL = directory.appendingPathComponent("profile.json")
    private static let connectionsURL = directory.appendingPathComponent("connections.json")
    private static let settingsURL = directory.appendingPathComponent("settings.json")
    private static let privacyURL = directory.appendingPathComponent("privacy.json")
    private static let streetpassesURL = directory.appendingPathComponent("streetpasses.json")
    private static let ratingsURL = directory.appendingPathComponent("ratings.json")

    init(inMemory: Bool = false) {
        if inMemory {
            profile = Profile(); connections = []; settings = Settings(); privacy = PrivacyPreferences()
            streetpasses = []; ratings = [:]
            return
        }
        profile = Self.load(Profile.self, from: Self.profileURL) ?? Profile()
        connections = Self.load([SavedConnection].self, from: Self.connectionsURL) ?? []
        settings = Self.load(Settings.self, from: Self.settingsURL) ?? Settings()
        privacy = Self.load(PrivacyPreferences.self, from: Self.privacyURL) ?? PrivacyPreferences()
        streetpasses = Self.load([StreetpassEvent].self, from: Self.streetpassesURL) ?? []
        // Older installs have no ratings file; every connection simply reads as
        // unrated, which is the correct starting state.
        let loaded = Self.load([InteractionRating].self, from: Self.ratingsURL) ?? []
        ratings = Dictionary(loaded.map { ($0.id, $0) }, uniquingKeysWith: { a, b in
            a.ratedOn >= b.ratedOn ? a : b    // newest answer wins
        })
    }

    /// Whether the bump tutorial has been shown (a UI convenience, kept in
    /// UserDefaults rather than the profile).
    static let tutorialSeenKey = "bump.tutorialSeen"

    /// Bumped by `resetOnboarding()` so the root view can return to Welcome.
    @Published private(set) var onboardingResets = 0

    /// Testing: forget the profile and the cloud choice so onboarding runs
    /// again from the start. Saved connections and settings are kept.
    func resetOnboarding() {
        profile = Profile()
        privacy = PrivacyPreferences()
        UserDefaults.standard.removeObject(forKey: Self.tutorialSeenKey)
        onboardingResets += 1
    }

    // MARK: Connections

    func save(_ connection: SavedConnection) {
        // Idempotent by id, so a retried save can't duplicate a row.
        if let index = connections.firstIndex(where: { $0.id == connection.id }) {
            connections[index] = connection
        } else {
            connections.insert(connection, at: 0)
        }
    }

    func delete(_ connection: SavedConnection) {
        connections.removeAll { $0.id == connection.id }
        ratings[connection.id] = nil
    }

    func deleteConnections(at offsets: IndexSet) {
        // Capture the ids BEFORE removing: after the removal the offsets no
        // longer point at the rows they described.
        let doomed = offsets.compactMap { connections.indices.contains($0) ? connections[$0].id : nil }
        connections.remove(atOffsets: offsets)
        for id in doomed { ratings[id] = nil }
    }

    // MARK: Ratings

    /// Records what landed. Idempotent by id, so re-rating a connection
    /// overwrites the previous answer instead of accumulating two.
    func saveRating(_ rating: InteractionRating) {
        ratings[rating.id] = rating
    }

    func rating(for id: UUID) -> InteractionRating? { ratings[id] }

    /// Connections the user has never answered for. Order follows `connections`,
    /// which is newest first.
    var unratedConnections: [SavedConnection] {
        connections.filter { ratings[$0.id] == nil }
    }

    // MARK: Streetpasses

    /// How many passers-by we keep. Old ones are not interesting, and the file
    /// stays small enough to load synchronously at launch.
    static let streetpassLimit = 100
    /// A repeat of the same person inside this window is the same encounter.
    /// Multipeer drops and re-advertises constantly; without this, one person
    /// standing next to you fills the whole feed.
    static let streetpassDedupeWindow: TimeInterval = 30 * 60

    /// Records a person seen nearby. `now` is injectable so the window is testable.
    func recordStreetpass(name: String, roomName: String,
                          at now: Date = Date(),
                          within window: TimeInterval = Store.streetpassDedupeWindow) {
        let name = name.trimmed()
        guard !name.isEmpty else { return }
        let isRepeat = streetpasses.contains {
            $0.peerName == name && now.timeIntervalSince($0.seenAt) < window
        }
        guard !isRepeat else { return }
        streetpasses.insert(StreetpassEvent(peerName: name, seenAt: now, roomName: roomName), at: 0)
        if streetpasses.count > Self.streetpassLimit {
            streetpasses.removeLast(streetpasses.count - Self.streetpassLimit)
        }
    }

    func clearStreetpasses() {
        guard !streetpasses.isEmpty else { return }
        streetpasses = []
    }

    // MARK: Disk

    private static func load<T: Decodable>(_ type: T.Type, from url: URL) -> T? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    private func persist<T: Encodable>(_ value: T, to url: URL) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        try? data.write(to: url, options: .atomic)
    }
}
