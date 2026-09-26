import SwiftUI

/// Testing tools: point the app at a BUMP server and check it. On a physical
/// iPhone, "localhost" is the phone itself — use the Mac's LAN address instead.
struct ServerSettingsSection: View {
    @ObservedObject var store: Store
    @ObservedObject var engine: BumpEngine

    @State private var draft = ""
    @State private var status: String?
    @State private var tone: StatusTone = .neutral
    @State private var checking = false

    private var buildDefault: String {
        (Bundle.main.object(forInfoDictionaryKey: "BumpAPIBaseURL") as? String) ?? ""
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            SectionHeading(title: "BUMP server",
                           subtitle: "Used for voice transcription and Grok. Build default: \(buildDefault.isEmpty ? "none" : buildDefault). On a phone, localhost means the phone itself, so use your Mac's address, e.g. http://192.168.1.20:8787.")
            BumpField(label: "Server URL override", placeholder: buildDefault, text: $draft)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(.URL)
                .onSubmit(save)
            HStack(spacing: Space.s) {
                Button("Save & check", action: save)
                    .buttonStyle(.bumpSecondary)
                Button("Use build default") { draft = ""; save() }
                    .buttonStyle(.bumpSecondary)
            }
            if checking {
                ProgressView().tint(BumpColor.action)
            } else if let status {
                StatusPill(text: status, tone: tone)
            }
        }
        .onAppear { draft = store.settings.apiBaseURL ?? "" }
    }

    private func save() {
        let value = draft.trimmed()
        store.settings.apiBaseURL = value.isEmpty ? nil : value
        guard let client = BumpAPIClient.resolve(override: store.settings.apiBaseURL) else {
            status = "Not a valid http(s) URL"; tone = .bad; return
        }
        checking = true
        Task {
            do {
                let health = try await client.health()
                status = health.grokConfigured
                    ? "Reachable · Grok ready (\(health.model ?? "model unknown"))"
                    : "Reachable · no xAI key on the server"
                tone = health.grokConfigured ? .good : .warn
            } catch {
                status = "Unreachable: \(BumpAPIError.map(error).localizedDescription)"
                tone = .bad
            }
            checking = false
            engine.refreshCloudStatus()
        }
    }
}
