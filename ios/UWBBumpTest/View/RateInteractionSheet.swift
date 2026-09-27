import SwiftUI

/// Asks two questions about an interaction that already happened: of the things
/// you turned out to share, which did you actually talk about, and would you want
/// to connect with this person again?
///
/// Deliberately not a star rating. There is no score and no grade — the app needs
/// to know which shared ground carried a conversation, and whether there is
/// mutual interest in more.
///
/// The two answers have DIFFERENT privacy, so they carry their own separate
/// promises rather than one blanket line: what landed never leaves the phone,
/// while the thumb is revealed only if the other person also tapped up.
struct RateInteractionSheet: View {
    let connection: SavedConnection
    /// Already-recorded answer, when re-rating from the Connections tab.
    var existing: InteractionRating?
    var onSave: (InteractionRating) -> Void
    var onSkip: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var selected: Set<String> = []
    /// `nil` until answered — skipping is allowed and can never match.
    @State private var wantsToConnect: Bool?

    private var isUpdate: Bool { existing != nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: Space.l) {
                    header
                    question
                    choices
                    connectAsk
                }
                .padding(.horizontal, Space.gutter)
                .padding(.top, Space.l)
                .padding(.bottom, Space.m)
            }
            .scrollBounceBehavior(.basedOnSize)

            bottomBar {
                Button(primaryLabel) {
                    onSave(InteractionRating(id: connection.id,
                                             landedInterestIDs: Array(selected),
                                             wantsToConnect: wantsToConnect))
                    dismiss()
                }
                .buttonStyle(.bumpPrimary)

                Button(isUpdate ? "Cancel" : "Not now") {
                    onSkip()
                    dismiss()
                }
                .buttonStyle(.bumpText)
            }
        }
        .background(BumpColor.surfaceContainerLowest)
        .onAppear {
            selected = Set(existing?.landedInterestIDs ?? [])
            wantsToConnect = existing?.wantsToConnect
        }
    }

    /// `BottomBar` is private to the onboarding flow, so the card carries the
    /// same treatment itself: the actions sit on the page background, clear of
    /// the scroll, with the primary on top.
    private func bottomBar<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: Space.xs) { content() }
            .padding(.horizontal, Space.gutter)
            .padding(.top, Space.m)
            .padding(.bottom, Space.s)
            .background(BumpColor.surfaceContainerLowest.ignoresSafeArea(edges: .bottom))
    }

    /// "Nothing landed" is a real answer worth recording, so the primary button
    /// stays enabled with an empty selection and says what it will save.
    private var primaryLabel: String {
        if selected.isEmpty { return "Nothing landed" }
        return isUpdate ? "Update" : "Done"
    }

    private var header: some View {
        HStack(spacing: Space.m) {
            Avatar(name: connection.partnerName, size: 56, photo: connection.partnerPhoto)
            VStack(alignment: .leading, spacing: 2) {
                Text(connection.partnerName)
                    .font(BumpFont.titleMedium)
                    .foregroundStyle(BumpColor.onSurface)
                Text("\(connection.metOn.formatted(date: .abbreviated, time: .shortened)) · \(connection.roomName)")
                    .font(BumpFont.bodyMedium)
                    .foregroundStyle(BumpColor.onSurfaceVariant)
            }
        }
    }

    private var question: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            Text("Which of these did you actually talk about?")
                .font(BumpFont.sectionTitle)
                .foregroundStyle(BumpColor.onSurface)
                .fixedSize(horizontal: false, vertical: true)
            Text("Private. This stays on your phone — \(connection.partnerName) never sees it.")
                .font(BumpFont.bodyMedium)
                .foregroundStyle(BumpColor.onSurfaceVariant)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// The second question. Its privacy line is its own, because unlike the tags
    /// above, this answer CAN reach the other person — and only in the one case
    /// where they said the same thing.
    private var connectAsk: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            Divider().overlay(BumpColor.outlineVariant)
                .padding(.bottom, Space.xs)
            Text("Would you Bump again?")
                .font(BumpFont.sectionTitle)
                .foregroundStyle(BumpColor.onSurface)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: Space.s) {
                thumbButton(up: true, label: "Yes", symbol: "hand.thumbsup.fill")
                thumbButton(up: false, label: "No", symbol: "hand.thumbsdown.fill")
            }
            Text("Only shared if you both tap yes, and then you each unlock the other\u{2019}s full profile. A no stays private: \(connection.partnerName) is never told either way.")
                .font(BumpFont.bodySmall)
                .foregroundStyle(BumpColor.onSurfaceVariant)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// Tapping the chosen thumb again clears it, so an answer given by mistake can
    /// be taken back to unanswered rather than forced to the opposite.
    private func thumbButton(up: Bool, label: String, symbol: String) -> some View {
        let isOn = wantsToConnect == up
        return Button {
            wantsToConnect = isOn ? nil : up
            Haptics.tap()
        } label: {
            HStack(spacing: Space.xs) {
                Image(systemName: symbol)
                    .font(.system(size: 18, weight: .regular))
                Text(label)
                    .font(BumpFont.bodyLarge)
            }
            .foregroundStyle(isOn ? BumpColor.primary : BumpColor.onSurfaceVariant)
            .padding(.vertical, Space.m)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: Space.corner, style: .continuous)
                    .fill(isOn ? BumpColor.primaryContainer : BumpColor.track)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Space.corner, style: .continuous)
                    .stroke(isOn ? BumpColor.primary : .clear, lineWidth: 1.5)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .animation(Motion.effects, value: isOn)
        .accessibilityLabel(label)
        .accessibilityHint("Whether you would bump \(connection.partnerName) again")
        .accessibilityAddTraits(isOn ? [.isButton, .isSelected] : .isButton)
    }

    private var choices: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            ForEach(connection.insight.highlights) { highlight in
                choiceRow(highlight)
            }
            Text("Pick as many as fit, or none. Either way it helps Bump stop suggesting things that don't land.")
                .font(BumpFont.bodySmall)
                .foregroundStyle(BumpColor.onSurfaceVariant)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, Space.xs)
        }
    }

    private func choiceRow(_ highlight: SharedHighlight) -> some View {
        let isOn = selected.contains(highlight.interestID)
        return Button {
            if isOn { selected.remove(highlight.interestID) }
            else { selected.insert(highlight.interestID) }
            Haptics.tap()
        } label: {
            HStack(alignment: .top, spacing: Space.m) {
                Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 22, weight: .regular))
                    .foregroundStyle(isOn ? BumpColor.primary : BumpColor.outline)
                VStack(alignment: .leading, spacing: 2) {
                    Text(highlight.statement)
                        .font(BumpFont.bodyLarge)
                        .foregroundStyle(BumpColor.onSurface)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("\(highlight.yourEntry) · \(highlight.theirEntry)")
                        .font(BumpFont.bodySmall)
                        .foregroundStyle(BumpColor.onSurfaceVariant)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(Space.m)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: Space.corner, style: .continuous)
                    .fill(isOn ? BumpColor.primaryContainer : BumpColor.track)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .animation(Motion.effects, value: isOn)
        .accessibilityLabel(highlight.statement)
        .accessibilityAddTraits(isOn ? [.isButton, .isSelected] : .isButton)
    }
}

/// The app's single rating target, so any screen can raise the rating card
/// without the card — or the state behind it — being duplicated per screen.
///
/// An environment value rather than a chain of `Binding` parameters on purpose:
/// `ConnectionDetail` is pushed from two different tabs, and a screen that only
/// passes the value through should not have to mention it. It also means the UI
/// overhaul can rearrange the view tree without re-threading anything.
private struct RatingTargetKey: EnvironmentKey {
    /// No target: previews and tests render the entry points without a card.
    static let defaultValue: Binding<SavedConnection?> = .constant(nil)
}

extension EnvironmentValues {
    var ratingTarget: Binding<SavedConnection?> {
        get { self[RatingTargetKey.self] }
        set { self[RatingTargetKey.self] = newValue }
    }
}

/// Presents the rating card, in one place.
///
/// Three screens put up the same card (the automatic prompt, the Connections
/// list, a connection's detail screen), so the detents, corner radius, card
/// background and height live here rather than being repeated at each site — a
/// change to the card's treatment is then a change to one file.
///
/// The `SavedConnection?` is owned by the caller and deliberately NOT stored
/// here: `RootView` keeps the single copy — published as `\.ratingTarget` — so
/// its automatic prompt can tell whether a card is already up before raising
/// another one.
struct RateInteractionPresentation: ViewModifier {
    @Binding var connection: SavedConnection?
    @ObservedObject var store: Store
    /// Called with the connection's id when the card is waved off rather than
    /// answered, so a caller that tracks "Not now" can record it.
    var onSkip: (UUID) -> Void
    /// Where the partner's answer comes from. Injected so tests and the DEBUG demo
    /// entry points can make a match happen on demand.
    var resolver: MutualLikeResolver = LocalMutualLikeResolver()
    /// Called once, with the connection, the moment a new mutual match is recorded.
    var onMatch: (SavedConnection) -> Void = { _ in }

    /// Tall enough that the second question is visible without scrolling on a
    /// typical connection — a thumb the person never scrolls to is a thumb they
    /// never answer. `.large` is offered alongside it for long highlight lists and
    /// for larger Dynamic Type, where the content genuinely does not fit.
    @ScaledMetric(relativeTo: .body) private var cardHeight: CGFloat = 760

    func body(content: Content) -> some View {
        content.sheet(item: $connection) { connection in
            RateInteractionSheet(
                connection: connection,
                existing: store.rating(for: connection.id),
                onSave: { rating in
                    store.saveRating(rating)
                    recordMatchIfAny(rating, connection)
                },
                onSkip: { onSkip(connection.id) }
            )
            .presentationDetents([.height(cardHeight), .large])
            .presentationCornerRadius(Radius.extraLargeIncreased)
            .presentationBackground(BumpColor.surfaceContainerLowest)
            .presentationDragIndicator(.visible)
        }
    }

    /// Evaluates the answer, and tells the caller only about a match that is NEW.
    /// `MatchEvaluator` returns nil for an existing match, so re-rating a matched
    /// connection never celebrates twice.
    private func recordMatchIfAny(_ rating: InteractionRating, _ connection: SavedConnection) {
        let match = MatchEvaluator().evaluate(rating: rating,
                                              partnerLike: resolver.partnerLike(for: connection),
                                              existing: store.match(for: connection.id))
        guard let match else { return }
        store.recordMatch(match)
        onMatch(connection)
    }
}

extension View {
    /// Shows the rating card whenever `item` holds a connection, and publishes
    /// `item` as `\.ratingTarget` so descendants can raise the card themselves.
    func rateInteraction(item: Binding<SavedConnection?>,
                         store: Store,
                         onSkip: @escaping (UUID) -> Void = { _ in },
                         resolver: MutualLikeResolver = LocalMutualLikeResolver(),
                         onMatch: @escaping (SavedConnection) -> Void = { _ in }) -> some View {
        modifier(RateInteractionPresentation(connection: item, store: store, onSkip: onSkip,
                                             resolver: resolver, onMatch: onMatch))
            .environment(\.ratingTarget, item)
    }
}

#Preview("Rate") {
    let store = PreviewFixtures.populatedStore()
    return RateInteractionSheet(connection: store.connections[0], onSave: { _ in }, onSkip: {})
}
