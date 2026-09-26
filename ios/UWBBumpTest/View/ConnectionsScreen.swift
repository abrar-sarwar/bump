import SwiftUI

struct ConnectionsScreen: View {
    @ObservedObject var store: Store

    var body: some View {
        NavigationStack {
            Group {
                if store.connections.isEmpty {
                    emptyState
                } else {
                    list
                }
            }
            .background(BumpColor.surface.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
        }
    }

    private var header: some View {
        PageTitle(title: "Connections",
                  subtitle: store.connections.isEmpty ? nil
                    : (store.connections.count == 1 ? "1 person you've met" : "\(store.connections.count) people you've met"))
            .padding(.horizontal, Space.gutter)
            .padding(.top, Space.l)
            .padding(.bottom, Space.s)
    }

    private var emptyState: some View {
        VStack(spacing: 0) {
            header
            Spacer()
            VStack(spacing: Space.m) {
                PhonesIllustration()
                Text("Nobody yet")
                    .font(BumpFont.headlineMedium)
                    .foregroundStyle(BumpColor.onSurface)
                Text("The people you bump show up here, with what you have in common and the question you started on.")
                    .font(BumpFont.bodyLarge)
                    .foregroundStyle(BumpColor.onSurfaceVariant)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, Space.xl)
            }
            Spacer()
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private var list: some View {
        List {
            Section {
                ForEach(store.connections) { connection in
                    NavigationLink {
                        ConnectionDetail(connection: connection, store: store)
                    } label: {
                        row(connection)
                    }
                    .listRowBackground(BumpColor.surfaceContainerLowest)
                    .listRowSeparatorTint(BumpColor.outlineVariant)
                    .listRowInsets(EdgeInsets(top: 12, leading: Space.m, bottom: 12, trailing: Space.m))
                    .alignmentGuide(.listRowSeparatorLeading) { _ in 68 }
                }
                .onDelete { store.deleteConnections(at: $0) }
            } header: {
                header
                    .textCase(nil)
                    .listRowInsets(EdgeInsets())
            }
        }
        .listStyle(.insetGrouped)
        .listSectionSpacing(0)
        .scrollContentBackground(.hidden)
        .background(BumpColor.surface)
        .environment(\.defaultMinListHeaderHeight, 0)
    }

    private func row(_ connection: SavedConnection) -> some View {
        HStack(spacing: Space.m) {
            Avatar(name: connection.partnerName, size: 44, photo: connection.partnerPhoto)
            VStack(alignment: .leading, spacing: 2) {
                Text(connection.partnerName)
                    .font(BumpFont.titleMedium)
                    .foregroundStyle(BumpColor.onSurface)
                Text(summary(connection))
                    .font(BumpFont.bodyMedium)
                    .foregroundStyle(BumpColor.onSurfaceVariant)
                    .lineLimit(2)
            }
        }
    }

    private func summary(_ connection: SavedConnection) -> String {
        let shared = connection.insight.highlights.map(\.yourEntry)
        let when = connection.metOn.formatted(date: .abbreviated, time: .omitted)
        if shared.isEmpty { return "\(when) · \(connection.roomName) · no shared interests yet" }
        return "\(when) · \(shared.joined(separator: ", "))"
    }
}

struct ConnectionDetail: View {
    let connection: SavedConnection
    @ObservedObject var store: Store
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Screen {
            VStack(alignment: .leading, spacing: Space.l) {
                HStack(spacing: Space.m) {
                    Avatar(name: connection.partnerName, size: 72, photo: connection.partnerPhoto)
                        .overlay(Circle().strokeBorder(BumpColor.primaryContainer, lineWidth: 3))
                    VStack(alignment: .leading, spacing: Space.xs) {
                        Text(connection.partnerName)
                            .font(BumpFont.headlineMedium)
                            .foregroundStyle(BumpColor.onSurface)
                        Text("\(connection.metOn.formatted(date: .abbreviated, time: .shortened)) · \(connection.roomName)")
                            .font(BumpFont.bodyMedium)
                            .foregroundStyle(BumpColor.onSurfaceVariant)
                    }
                }

                StatusPill(text: connection.pairingEvidence.label,
                           tone: connection.pairingEvidence == .manualSelection ? .warn : .good,
                           icon: connection.pairingEvidence == .manualSelection ? "hand.point.up.left.fill" : "checkmark.seal.fill")

                if !connection.partnerBio.isEmpty {
                    Card(style: .filled) {
                        Text(connection.partnerBio)
                            .font(BumpFont.bodyLarge)
                            .foregroundStyle(BumpColor.onSurface)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                if connection.insight.highlights.isEmpty {
                    Text("No shared interests were found.")
                        .font(BumpFont.bodyLarge)
                        .foregroundStyle(BumpColor.onSurfaceVariant)
                } else {
                    VStack(alignment: .leading, spacing: Space.s) {
                        Eyebrow(text: "Specific things you share")
                        ForEach(connection.insight.highlights) { highlight in
                            HighlightCard(highlight: highlight, point: connection.insight.point(for: highlight))
                        }
                    }
                }

                if !connection.insight.unattachedPoints.isEmpty {
                    TalkingPointsSection(points: connection.insight.unattachedPoints)
                }

                VStack(alignment: .leading, spacing: Space.s) {
                    Eyebrow(text: "Something to talk about")
                    OpenerCard(opener: connection.insight.opener, source: connection.insight.openerSource.label)
                }

                Button("Delete connection", role: .destructive) {
                    store.delete(connection)
                    dismiss()
                }
                .buttonStyle(.bumpSecondary)
                .padding(.top, Space.m)
            }
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(BumpColor.surface, for: .navigationBar)
    }
}

#Preview {
    ConnectionsScreen(store: PreviewFixtures.populatedStore())
}
