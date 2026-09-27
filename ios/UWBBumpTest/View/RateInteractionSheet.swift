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

#Preview("Rate") {
    let store = PreviewFixtures.populatedStore()
    return RateInteractionSheet(connection: store.connections[0], onSave: { _ in }, onSkip: {})
}
