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
            .background(BumpColor.background)
            .navigationTitle("Connections")
            .navigationBarTitleDisplayMode(.large)
        }
    }

    private var emptyState: some View {
        ZStack {
            BumpColor.background.ignoresSafeArea()
            Backdrop(style: .soft).ignoresSafeArea()
            VStack(spacing: Space.m) {
                Spacer()
                PhonesIllustration(apart: true)
                    .padding(.top, 60)
                    .floaters([Floater(text: FloaterLine.lecture, alignment: .topLeading,
                                       offset: CGSize(width: 0, height: -10), rotation: -3)])
                    .padding(.horizontal, Space.gutter)
                ScreenTitle("Nobody yet", alignment: .center)
                Text("The people you bump show up here, with what you have in common and the question you started on.")
                    .font(BumpFont.body)
                    .foregroundStyle(BumpColor.secondaryText)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, Space.xl)
                Spacer()
                Spacer()
            }
            .frame(maxWidth: .infinity)
        }
    }

    /// A plain List, kept for swipe to delete, with each row a frosted pill.
    private var list: some View {
        List {
            ForEach(Array(store.connections.enumerated()), id: \.element.id) { index, connection in
                NavigationLink {
                    ConnectionDetail(connection: connection, store: store)
                } label: {
                    row(connection, warm: index.isMultiple(of: 2))
                }
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets(top: 5, leading: Space.gutter, bottom: 5, trailing: Space.gutter))
            }
            .onDelete { store.deleteConnections(at: $0) }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(BumpColor.background)
    }

    private func row(_ connection: SavedConnection, warm: Bool) -> some View {
        RowPill(block: true) {
            Avatar(name: connection.partnerName, size: 48,
                   tint: warm ? BumpColor.illustrationWarm : BumpColor.primary,
                   photo: connection.partnerPhoto)
        } content: {
            RowText.title(connection.partnerName)
            Text(summary(connection))
                .font(BumpFont.caption)
                .foregroundStyle(BumpColor.secondaryText)
                .lineLimit(2)
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
        Screen(backdrop: .soft) {
            VStack(alignment: .leading, spacing: Space.l) {
                Card(padding: 22) {
                    VStack(alignment: .leading, spacing: Space.m) {
                        HStack(spacing: Space.m) {
                            Avatar(name: connection.partnerName, size: 72, tint: BumpColor.illustrationWarm,
                                   photo: connection.partnerPhoto)
                            VStack(alignment: .leading, spacing: Space.xs) {
                                Text(connection.partnerName)
                                    .font(BumpFont.sectionTitle)
                                    .foregroundStyle(BumpColor.navy)
                                    .fixedSize(horizontal: false, vertical: true)
                                Text("\(connection.metOn.formatted(date: .abbreviated, time: .shortened)) · \(connection.roomName)")
                                    .font(BumpFont.caption)
                                    .foregroundStyle(BumpColor.secondaryText)
                                StatusPill(text: connection.pairingEvidence.label,
                                           tone: connection.pairingEvidence == .manualSelection ? .warn : .good)
                            }
                        }
                        if !connection.partnerBio.isEmpty {
                            ChatBubble(connection.partnerBio)
                        }
                    }
                }

                if connection.insight.highlights.isEmpty {
                    Text("No shared interests were found.")
                        .font(BumpFont.body)
                        .foregroundStyle(BumpColor.secondaryText)
                } else {
                    VStack(alignment: .leading, spacing: Space.s) {
                        Eyebrow("Specific things you share")
                            .padding(.horizontal, Space.xs)
                        ForEach(connection.insight.highlights) { highlight in
                            RowPill(block: true) {
                                IconOrb(systemImage: "sparkles", size: 44)
                            } content: {
                                RowText.title(highlight.statement)
                                RowText.subtitle(highlight.yourEntry == highlight.theirEntry
                                     ? "Both of you list “\(highlight.yourEntry)”"
                                     : "You listed “\(highlight.yourEntry)” · they listed “\(highlight.theirEntry)”")
                                if let point = connection.insight.point(for: highlight) {
                                    TalkingPromptLine(point: point)
                                }
                            }
                        }
                    }
                }

                if !connection.insight.unattachedPoints.isEmpty {
                    TalkingPointsSection(points: connection.insight.unattachedPoints)
                }

                VStack(alignment: .leading, spacing: Space.s) {
                    Eyebrow("Something to talk about")
                        .padding(.horizontal, Space.xs)
                    ChatBubble(isMe: true, who: connection.insight.openerSource.label) {
                        Text(connection.insight.opener)
                            .font(BumpFont.archivo(Archivo.semibold, 19, relativeTo: .title3))
                    }
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
    }
}

#Preview {
    ConnectionsScreen(store: PreviewFixtures.populatedStore())
}
