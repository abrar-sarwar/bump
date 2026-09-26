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

    init(inMemory: Bool = false) {
        if inMemory {
            profile = Profile(); connections = []; settings = Settings(); privacy = PrivacyPreferences()
            return
        }
        profile = Self.load(Profile.self, from: Self.profileURL) ?? Profile()
        connections = Self.load([SavedConnection].self, from: Self.connectionsURL) ?? []
        settings = Self.load(Settings.self, from: Self.settingsURL) ?? Settings()
        privacy = Self.load(PrivacyPreferences.self, from: Self.privacyURL) ?? PrivacyPreferences()
    }

    /// Bumped by `resetOnboarding()` so the root view can return to Welcome.
    @Published private(set) var onboardingResets = 0

    /// Testing: forget the profile and the cloud choice so onboarding runs
    /// again from the start. Saved connections and settings are kept.
    func resetOnboarding() {
        profile = Profile()
        privacy = PrivacyPreferences()
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
    }

    func deleteConnections(at offsets: IndexSet) {
        connections.remove(atOffsets: offsets)
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
