import SwiftUI

struct ConnectionsScreen: View {
    @ObservedObject var store: Store
    /// The connection to push on appear, set by `RootView` when a bump has just
    /// been saved, so saving lands on the person you met instead of the radar.
    @Binding var pushedConnection: SavedConnection?
    /// Lets the empty state send someone to the Bump tab. "Nobody yet" with no
    /// way to go and meet somebody was the flow's other dead end.
    @Binding var tab: MainTab

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
            .background(BumpColor.background)
            .navigationTitle("Friends")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                if !store.connections.isEmpty {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button { showingInsights = true } label: {
                            Image(systemName: "chart.bar.fill")
                        }
                        .buttonStyle(.bumpIcon)
                        .accessibilityLabel("What lands")
                    }
                }
            }
            .navigationDestination(isPresented: $showingInsights) {
                InsightsScreen(store: store, onRate: { ratingTarget.wrappedValue = $0 })
            }
            .navigationDestination(isPresented: pushedBinding) {
                if let connection = pushedConnection {
                    ConnectionDetail(connection: connection, store: store)
                }
            }
            .onAppear {
                #if DEBUG
                if DemoMode.active == .insights { showingInsights = true }
                #endif
            }
        }
    }

    /// `SavedConnection` is not `Hashable`, so the just-saved push runs off
    /// `isPresented` rather than `navigationDestination(item:)`. Clearing the
    /// connection on pop is what lets the same person be pushed again later.
    private var pushedBinding: Binding<Bool> {
        Binding(get: { pushedConnection != nil },
                set: { if !$0 { pushedConnection = nil } })
    }

    private var emptyState: some View {
        ZStack {
            BumpColor.background.ignoresSafeArea()
            Backdrop(style: .soft).ignoresSafeArea()
            VStack(spacing: Space.m) {
                Spacer()
                PhonesIllustration(apart: true)
                    .padding(.top, 60)
                    .padding(.horizontal, Space.gutter)
                ScreenTitle("Nobody yet", alignment: .center)
                Text("The people you bump show up here, with what you have in common and the question you started on.")
                    .font(BumpFont.body)
                    .foregroundStyle(BumpColor.secondaryText)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, Space.xl)
                Button("Bump someone") { tab = .bump }
                    .buttonStyle(.bumpPrimary)
                    .padding(.horizontal, Space.xl)
                    .padding(.top, Space.s)
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
        } trail: {
            if isRateable(connection) {
                // Tappable independently of the row's NavigationLink, so "Rate"
                // opens the sheet instead of pushing the detail screen.
                Button { ratingTarget.wrappedValue = connection } label: {
                    StatusPill(text: "Rate", tone: .active, icon: "text.bubble.fill")
                }
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
                            Text(connection.partnerBio)
                                .font(BumpFont.body)
                                .foregroundStyle(BumpColor.secondaryText)
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
                    Card {
                        VStack(alignment: .leading, spacing: Space.xs) {
                            Text(connection.insight.opener)
                                .font(BumpFont.archivo(Archivo.semibold, 19, relativeTo: .title3))
                            Text(connection.insight.openerSource.label)
                                .font(BumpFont.caption2)
                                .foregroundStyle(BumpColor.faint)
                        }
                    }
                }

                if !connection.insight.highlights.isEmpty {
                    VStack(alignment: .leading, spacing: Space.s) {
                        Eyebrow("What you talked about")
                            .padding(.horizontal, Space.xs)
                        Card {
                            if let rating = store.rating(for: connection.id) {
                                Text(ratedRecap(rating))
                                    .font(BumpFont.body)
                                    .foregroundStyle(BumpColor.navy)
                                    .fixedSize(horizontal: false, vertical: true)
                            } else {
                                Text("You haven\u{2019}t said yet. Only you ever see this.")
                                    .font(BumpFont.body)
                                    .foregroundStyle(BumpColor.secondaryText)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
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
    }

    private func ratedRecap(_ rating: InteractionRating) -> String {
        let landed = rating.landedEntries(among: connection.insight.highlights)
        if landed.isEmpty { return "None of the shared interests came up." }
        return landed.joined(separator: ", ")
    }
}

#Preview {
    ConnectionsScreen(store: PreviewFixtures.populatedStore(),
                      pushedConnection: .constant(nil),
                      tab: .constant(.connections))
}
