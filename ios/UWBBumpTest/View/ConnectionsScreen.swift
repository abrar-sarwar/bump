import SwiftUI

struct ConnectionsScreen: View {
    @ObservedObject var store: Store

    /// The app's rating target, owned by `RootView`. Assigning to it raises the
    /// card. There must be exactly one of these, or the automatic
    /// post-interaction prompt cannot tell that a card is already up and will
    /// try to raise a second sheet that SwiftUI then silently drops.
    @Environment(\.ratingTarget) private var ratingTarget
    /// Pushes the Insights screen. Normally driven by the "What lands" link;
    /// also set by the DEBUG `.insights` demo so the screen can be inspected in
    /// the Simulator without tapping through.
    @State private var showingInsights = false

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
            .navigationDestination(isPresented: $showingInsights) {
                InsightsScreen(store: store, onRate: { ratingTarget.wrappedValue = $0 })
            }
            .onAppear {
                #if DEBUG
                if DemoMode.active == .insights { showingInsights = true }
                #endif
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            PageTitle(title: "Connections",
                      subtitle: store.connections.isEmpty ? nil
                        : (store.connections.count == 1 ? "1 person you've met" : "\(store.connections.count) people you've met"))
            if !store.connections.isEmpty {
                Button {
                    showingInsights = true
                } label: {
                    HStack(spacing: Space.xs) {
                        Image(systemName: "chart.bar.fill").font(.system(size: 12, weight: .semibold))
                        Text("What lands").font(BumpFont.labelLarge)
                        Chevron()
                    }
                    .foregroundStyle(BumpColor.primary)
                }
            }
        }
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
            if isRateable(connection) {
                Spacer(minLength: Space.xs)
                // Tappable independently of the row's NavigationLink, so "Rate"
                // opens the sheet instead of pushing the detail screen.
                Button { ratingTarget.wrappedValue = connection } label: { StatusPill(text: "Rate", tone: .active, icon: "text.bubble.fill") }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Rate your interaction with \(connection.partnerName)")
            }
        }
    }

    /// Worth asking about: never answered, and there was something shared to ask
    /// about in the first place.
    private func isRateable(_ connection: SavedConnection) -> Bool {
        store.rating(for: connection.id) == nil && !connection.insight.highlights.isEmpty
    }

    /// Once rated, the row reports what was actually talked about rather than
    /// everything the match predicted, so the list becomes a record of what worked.
    private func summary(_ connection: SavedConnection) -> String {
        let when = connection.metOn.formatted(date: .abbreviated, time: .omitted)
        let highlights = connection.insight.highlights

        // Checked first, so a connection with nothing shared reads the same
        // whether or not it somehow carries an answer.
        if highlights.isEmpty { return "\(when) · \(connection.roomName) · no shared interests yet" }

        if let rating = store.rating(for: connection.id) {
            let landed = rating.landedEntries(among: highlights)
            if landed.isEmpty { return "\(when) · nothing landed" }
            return "\(when) · talked about \(landed.joined(separator: ", "))"
        }

        return "\(when) · \(highlights.map(\.yourEntry).joined(separator: ", "))"
    }
}

struct ConnectionDetail: View {
    let connection: SavedConnection
    @ObservedObject var store: Store
    @Environment(\.dismiss) private var dismiss
    /// Same single rating target as the rest of the app; see `ConnectionsScreen`.
    @Environment(\.ratingTarget) private var ratingTarget

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

                if !connection.insight.highlights.isEmpty {
                    VStack(alignment: .leading, spacing: Space.s) {
                        Eyebrow(text: "What you talked about")
                        if let rating = store.rating(for: connection.id) {
                            Text(ratedRecap(rating))
                                .font(BumpFont.bodyLarge)
                                .foregroundStyle(BumpColor.onSurface)
                                .fixedSize(horizontal: false, vertical: true)
                        } else {
                            Text("You haven't said yet. Only you ever see this.")
                                .font(BumpFont.bodyLarge)
                                .foregroundStyle(BumpColor.onSurfaceVariant)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Button(store.rating(for: connection.id) == nil
                               ? "Rate this interaction" : "Update what landed") {
                            ratingTarget.wrappedValue = connection
                        }
                        .buttonStyle(.bumpSecondary)
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
        .toolbarBackground(BumpColor.surface, for: .navigationBar)
    }

    private func ratedRecap(_ rating: InteractionRating) -> String {
        let landed = rating.landedEntries(among: connection.insight.highlights)
        if landed.isEmpty { return "None of the shared interests came up." }
        return landed.joined(separator: ", ")
    }
}

#Preview {
    ConnectionsScreen(store: PreviewFixtures.populatedStore())
}
