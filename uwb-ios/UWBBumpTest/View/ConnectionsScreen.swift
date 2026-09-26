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
        VStack(spacing: Space.m) {
            Spacer()
            PhonesIllustration()
            Text("Nobody yet")
                .font(BumpFont.screenTitle)
                .foregroundStyle(BumpColor.navy)
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
        .background(BumpColor.background)
    }

    private var list: some View {
        List {
            ForEach(store.connections) { connection in
                NavigationLink {
                    ConnectionDetail(connection: connection, store: store)
                } label: {
                    row(connection)
                }
                .listRowBackground(BumpColor.surface)
            }
            .onDelete { store.deleteConnections(at: $0) }
        }
        .scrollContentBackground(.hidden)
        .background(BumpColor.background)
    }

    private func row(_ connection: SavedConnection) -> some View {
        HStack(spacing: Space.m) {
            Avatar(name: connection.partnerName, size: 44, photo: connection.partnerPhoto)
            VStack(alignment: .leading, spacing: 2) {
                Text(connection.partnerName)
                    .font(BumpFont.bodyEmphasis)
                    .foregroundStyle(BumpColor.navy)
                Text(summary(connection))
                    .font(BumpFont.caption)
                    .foregroundStyle(BumpColor.secondaryText)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, Space.xs)
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
                    Avatar(name: connection.partnerName, size: 64, photo: connection.partnerPhoto)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(connection.partnerName)
                            .font(BumpFont.screenTitle)
                            .foregroundStyle(BumpColor.navy)
                        Text("\(connection.metOn.formatted(date: .abbreviated, time: .shortened)) · \(connection.roomName)")
                            .font(BumpFont.caption)
                            .foregroundStyle(BumpColor.secondaryText)
                    }
                }

                StatusPill(text: connection.pairingEvidence.label,
                           tone: connection.pairingEvidence == .manualSelection ? .warn : .good)

                if !connection.partnerBio.isEmpty {
                    Card {
                        Text(connection.partnerBio)
                            .font(BumpFont.body)
                            .foregroundStyle(BumpColor.navy)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                if connection.insight.highlights.isEmpty {
                    Text("No shared interests were found.")
                        .font(BumpFont.body)
                        .foregroundStyle(BumpColor.secondaryText)
                } else {
                    SectionHeading(title: "Specific things you share")
                    ForEach(connection.insight.highlights) { highlight in
                        Card {
                            VStack(alignment: .leading, spacing: Space.xs) {
                                Text(highlight.statement)
                                    .font(BumpFont.bodyEmphasis)
                                    .foregroundStyle(BumpColor.navy)
                                    .fixedSize(horizontal: false, vertical: true)
                                Text(highlight.yourEntry == highlight.theirEntry
                                     ? "Both of you list “\(highlight.yourEntry)”"
                                     : "You listed “\(highlight.yourEntry)” · they listed “\(highlight.theirEntry)”")
                                    .font(BumpFont.caption)
                                    .foregroundStyle(BumpColor.secondaryText)
                                    .fixedSize(horizontal: false, vertical: true)
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

                SectionHeading(title: "Something to talk about")
                Card {
                    VStack(alignment: .leading, spacing: Space.s) {
                        Text(connection.insight.opener)
                            .font(BumpFont.sectionTitle)
                            .foregroundStyle(BumpColor.navy)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(connection.insight.openerSource.label)
                            .font(BumpFont.caption)
                            .foregroundStyle(BumpColor.secondaryText)
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
