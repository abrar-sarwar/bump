import Foundation

/// Local persistence: profile + saved connections as JSON in Application
/// Support. No cloud, no account, no database dependency.
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

    struct Settings: Codable, Equatable {
        var motionThreshold: Double = 20.0
        var motionCooldown: TimeInterval = 1.5
        var pairingWindow: TimeInterval = 0.500
        var ambiguityMargin: TimeInterval = 0.050
        var pairingBuffer: TimeInterval = 0.250
        var uwbProximity: Double = 0.15
        var uwbFreshness: TimeInterval = 1.5
        var detectionMode: DetectionMode = .combined

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

    init(inMemory: Bool = false) {
        if inMemory {
            profile = Profile(); connections = []; settings = Settings()
            return
        }
        profile = Self.load(Profile.self, from: Self.profileURL) ?? Profile()
        connections = Self.load([SavedConnection].self, from: Self.connectionsURL) ?? []
        settings = Self.load(Settings.self, from: Self.settingsURL) ?? Settings()
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
