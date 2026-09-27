import SwiftUI

/// One chronological feed of what has already happened: people you bumped, and
/// people whose phone passed nearby without a bump.
///
/// Bumps are read straight from `store.connections` — there is no second copy of
/// that history. Passers-by carry a name and a time and nothing else; a profile
/// only ever arrives after a confirmed bump.
struct NotificationsScreen: View {
    @ObservedObject var store: Store
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Screen {
                VStack(alignment: .leading, spacing: Space.l) {
                    if items.isEmpty { emptyState } else { feed }
                }
            }
            .navigationTitle("Notifications")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(BumpColor.surface, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
        .presentationCornerRadius(Radius.extraLarge)
        .presentationDragIndicator(.visible)
    }

    // MARK: Feed

    private var feed: some View {
        VStack(alignment: .leading, spacing: Space.l) {
            SectionHeading(title: "Recently", subtitle: subtitle)
            ListGroup {
                ForEach(items) { item in
                    switch item {
                    case .bump(let connection):
                        NavigationLink {
                            ConnectionDetail(connection: connection, store: store)
                        } label: {
                            row(name: connection.partnerName,
                                detail: "Bumped · \(Self.relative.localizedString(for: connection.metOn, relativeTo: Date()))",
                                photo: connection.partnerPhoto,
                                tint: BumpColor.brand,
                                chevron: true)
                        }
                        .buttonStyle(NavigationRowStyle())

                    case .streetpass(let event):
                        row(name: event.peerName,
                            detail: "Passed nearby · \(Self.relative.localizedString(for: event.seenAt, relativeTo: Date()))",
                            photo: nil,
                            tint: BumpColor.outlineVariant,
                            chevron: false)
                    }
                }
            }
            if !store.streetpasses.isEmpty {
                Button("Clear passers-by") { store.clearStreetpasses() }
                    .buttonStyle(.bumpText)
            }
            InfoNotice(text: "BUMP only learns who someone is once you both bump. A passer-by is a name and a time, kept on this phone.", tone: .neutral)
        }
    }

    private var subtitle: String? {
        let passed = store.streetpasses.count
        guard passed > 0 else { return nil }
        return passed == 1 ? "1 person passed by without a bump"
                           : "\(passed) people passed by without a bump"
    }

    /// Shared by both row kinds, so a bump and a passer-by line up exactly.
    private func row(name: String, detail: String, photo: Data?,
                     tint: Color, chevron: Bool) -> some View {
        HStack(spacing: Space.m) {
            Avatar(name: name, size: 40, tint: tint, photo: photo)
            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(BumpFont.titleMedium)
                    .foregroundStyle(BumpColor.onSurface)
                Text(detail)
                    .font(BumpFont.bodyMedium)
                    .foregroundStyle(BumpColor.onSurfaceVariant)
            }
            Spacer(minLength: Space.s)
            if chevron { Chevron() }
        }
        .padding(.horizontal, Space.m)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            SectionHeading(title: "Nothing yet",
                           subtitle: "The people you bump show up here, along with anyone whose phone passed by without one.")
        }
        .padding(.top, Space.l)
    }

    // MARK: Merged, newest first

    private enum FeedItem: Identifiable {
        case bump(SavedConnection)
        case streetpass(StreetpassEvent)

        var date: Date {
            switch self {
            case .bump(let c): return c.metOn
            case .streetpass(let e): return e.seenAt
            }
        }
        var id: String {
            switch self {
            case .bump(let c): return "bump-\(c.id)"
            case .streetpass(let e): return "pass-\(e.id)"
            }
        }
    }

    private var items: [FeedItem] {
        let merged = store.connections.map(FeedItem.bump)
            + store.streetpasses.map(FeedItem.streetpass)
        return merged.sorted { $0.date > $1.date }
    }

    private static let relative: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .full
        return f
    }()
}

#Preview("Notifications") {
    NotificationsScreen(store: PreviewFixtures.populatedStore())
}

#Preview("Notifications — empty") {
    NotificationsScreen(store: Store(inMemory: true))
}
