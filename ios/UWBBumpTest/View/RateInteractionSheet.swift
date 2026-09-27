import SwiftUI

/// Asks one private question about an interaction that already happened: of the
/// things you turned out to share, which did you actually talk about?
///
/// Deliberately not a star rating. There is no score, no grade and no judgement
/// of the other person — the app only needs to know which shared ground carried a
/// conversation, so that is the only thing it asks.
struct RateInteractionSheet: View {
    let connection: SavedConnection
    /// Already-recorded answer, when re-rating from the Connections tab.
    var existing: InteractionRating?
    var onSave: (InteractionRating) -> Void
    var onSkip: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var selected: Set<String> = []

    private var isUpdate: Bool { existing != nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: Space.l) {
                    header
                    question
                    choices
                }
                .padding(.horizontal, Space.gutter)
                .padding(.top, Space.l)
                .padding(.bottom, Space.m)
            }
            .scrollBounceBehavior(.basedOnSize)

            BottomBar {
                Button(primaryLabel) {
                    onSave(InteractionRating(id: connection.id,
                                             landedInterestIDs: Array(selected)))
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
        .onAppear { selected = Set(existing?.landedInterestIDs ?? []) }
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
                .font(BumpFont.headlineMedium)
                .foregroundStyle(BumpColor.onSurface)
                .fixedSize(horizontal: false, vertical: true)
            Text("Private. This stays on your phone — \(connection.partnerName) never sees it.")
                .font(BumpFont.bodyMedium)
                .foregroundStyle(BumpColor.onSurfaceVariant)
                .fixedSize(horizontal: false, vertical: true)
        }
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
                RoundedRectangle(cornerRadius: Radius.large, style: .continuous)
                    .fill(isOn ? BumpColor.primaryContainer : BumpColor.surfaceContainerHigh)
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

    @ScaledMetric(relativeTo: .body) private var cardHeight: CGFloat = 520

    func body(content: Content) -> some View {
        content.sheet(item: $connection) { connection in
            RateInteractionSheet(
                connection: connection,
                existing: store.rating(for: connection.id),
                onSave: { store.saveRating($0) },
                onSkip: { onSkip(connection.id) }
            )
            .presentationDetents([.height(cardHeight)])
            .presentationCornerRadius(Radius.extraLargeIncreased)
            .presentationBackground(BumpColor.surfaceContainerLowest)
            .presentationDragIndicator(.visible)
        }
    }
}

extension View {
    /// Shows the rating card whenever `item` holds a connection, and publishes
    /// `item` as `\.ratingTarget` so descendants can raise the card themselves.
    func rateInteraction(item: Binding<SavedConnection?>,
                         store: Store,
                         onSkip: @escaping (UUID) -> Void = { _ in }) -> some View {
        modifier(RateInteractionPresentation(connection: item, store: store, onSkip: onSkip))
            .environment(\.ratingTarget, item)
    }
}

#Preview("Rate") {
    let store = PreviewFixtures.populatedStore()
    return RateInteractionSheet(connection: store.connections[0], onSave: { _ in }, onSkip: {})
}
