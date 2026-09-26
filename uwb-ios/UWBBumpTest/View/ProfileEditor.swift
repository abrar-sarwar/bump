import SwiftUI

/// Used both for first-run onboarding and for later editing from You.
struct ProfileEditor: View {
    @Binding var profile: Profile
    var isOnboarding: Bool
    var onDone: () -> Void

    @State private var customEntry = ""
    @FocusState private var customFocused: Bool

    private var selectedIDs: Set<String> { Set(profile.interests.map(\.id)) }

    var body: some View {
        Screen {
            VStack(alignment: .leading, spacing: Space.l) {

                if isOnboarding {
                    Wordmark()
                    SectionHeading(
                        title: "Tell people who you are",
                        subtitle: "Two minutes now, better conversations later."
                    )
                }

                BumpField(label: "Display name", placeholder: "What should people call you?",
                          text: $profile.displayName)

                BumpField(label: "Short bio (optional)", placeholder: "One line about you",
                          axis: .vertical, text: $profile.bio)

                VStack(alignment: .leading, spacing: Space.s) {
                    SectionHeading(
                        title: "What are you into?",
                        subtitle: "Specific beats broad. “Jazz piano” starts a better conversation than “music”."
                    )

                    ForEach(InterestCatalog.groups, id: \.category.id) { group in
                        VStack(alignment: .leading, spacing: Space.s) {
                            Text(group.category.label)
                                .font(BumpFont.bodyEmphasis)
                                .foregroundStyle(BumpColor.navy)
                                .padding(.top, Space.s)
                            FlowLayout {
                                ForEach([group.category] + group.children) { interest in
                                    InterestChip(title: interest.label,
                                                 selected: selectedIDs.contains(interest.id)) {
                                        toggle(interest)
                                    }
                                }
                            }
                        }
                    }
                }

                VStack(alignment: .leading, spacing: Space.s) {
                    BumpField(label: "Something else?", placeholder: "Add your own", text: $customEntry)
                        .focused($customFocused)
                        .onSubmit(addCustom)
                    Button("Add interest", action: addCustom)
                        .buttonStyle(.bumpSecondary)
                        .disabled(customEntry.trimmed().isEmpty)
                }

                if !profile.interests.isEmpty {
                    VStack(alignment: .leading, spacing: Space.s) {
                        Text("Your interests (\(profile.interests.count))")
                            .font(BumpFont.caption)
                            .foregroundStyle(BumpColor.secondaryText)
                        FlowLayout {
                            ForEach(profile.interests) { interest in
                                InterestChip(title: "\(interest.label)  ✕", selected: true) {
                                    profile.interests.removeAll { $0.id == interest.id }
                                }
                                .accessibilityLabel("Remove \(interest.label)")
                            }
                        }
                    }
                }

                Button(isOnboarding ? "Start bumping" : "Save", action: onDone)
                    .buttonStyle(.bumpPrimary)
                    .disabled(!profile.isComplete)

                if !profile.isComplete {
                    Text("Add a name and at least one interest to continue.")
                        .font(BumpFont.caption)
                        .foregroundStyle(BumpColor.secondaryText)
                }
            }
        }
        .navigationTitle(isOnboarding ? "" : "Edit profile")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func toggle(_ interest: Interest) {
        if let index = profile.interests.firstIndex(where: { $0.id == interest.id }) {
            profile.interests.remove(at: index)
        } else {
            profile.interests.append(interest)
            Haptics.tap()
        }
    }

    private func addCustom() {
        let raw = customEntry.trimmed()
        guard !raw.isEmpty, let interest = InterestCatalog.canonical(from: raw) else { return }
        if !profile.interests.contains(where: { $0.id == interest.id }) {
            profile.interests.append(interest)
            Haptics.tap()
        }
        customEntry = ""
        customFocused = false
    }
}

#Preview {
    NavigationStack {
        ProfileEditor(profile: .constant(PreviewFixtures.profile), isOnboarding: true, onDone: {})
    }
}
