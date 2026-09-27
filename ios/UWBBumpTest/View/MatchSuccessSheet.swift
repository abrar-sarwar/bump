import SwiftUI

/// The one moment where a private answer becomes shared: both people said they
/// wanted to connect again, so the card tells each of them and hands them
/// somewhere to go.
///
/// It says nothing about what the other person said beyond the yes itself — there
/// is no "they answered first", no timing, nothing that would let a no be inferred
/// from its absence elsewhere.
struct MatchSuccessSheet: View {
    let connection: SavedConnection
    var onSeeProfile: () -> Void
    var onDismiss: () -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: Space.l) {
                    badge
                    copy
                }
                .padding(.horizontal, Space.gutter)
                .padding(.top, Space.l)
                .padding(.bottom, Space.m)
            }
            .scrollBounceBehavior(.basedOnSize)

            VStack(spacing: Space.xs) {
                Button("See their full profile") {
                    onSeeProfile()
                    dismiss()
                }
                .buttonStyle(.bumpPrimary)

                Button("Later") {
                    onDismiss()
                    dismiss()
                }
                .buttonStyle(.bumpText)
            }
            .padding(.horizontal, Space.gutter)
            .padding(.top, Space.m)
            .padding(.bottom, Space.s)
            .background(BumpColor.surfaceContainerLowest.ignoresSafeArea(edges: .bottom))
        }
        .background(BumpColor.surfaceContainerLowest)
    }

    private var badge: some View {
        HStack(spacing: Space.m) {
            Avatar(name: connection.partnerName, size: 72, photo: connection.partnerPhoto)
            Image(systemName: "hand.thumbsup.fill")
                .font(.system(size: 28, weight: .regular))
                .foregroundStyle(BumpColor.primary)
                .padding(Space.m)
                .background(Circle().fill(BumpColor.primaryContainer))
        }
    }

    private var copy: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            Text("You both want to connect")
                .font(BumpFont.titleLarge)
                .foregroundStyle(BumpColor.onSurface)
                .fixedSize(horizontal: false, vertical: true)
            Text("\(connection.partnerName) said yes too, so you\u{2019}ve each unlocked the other\u{2019}s full profile \u{2014} their interests, experiences and what they\u{2019}re working towards.")
                .font(BumpFont.bodyLarge)
                .foregroundStyle(BumpColor.onSurfaceVariant)
                .fixedSize(horizontal: false, vertical: true)
            Text("This stays in your notifications, so it\u{2019}s here when you want it.")
                .font(BumpFont.bodySmall)
                .foregroundStyle(BumpColor.onSurfaceVariant)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

#Preview("Match") {
    let store = PreviewFixtures.populatedStore()
    return MatchSuccessSheet(connection: store.connections[0],
                             onSeeProfile: {}, onDismiss: {})
}
