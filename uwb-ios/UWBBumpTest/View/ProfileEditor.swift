import SwiftUI

/// Used both for first-run onboarding and for later editing from You.
struct ProfileEditor: View {
    @Binding var profile: Profile
    var isOnboarding: Bool
    var onDone: () -> Void

    @State private var customEntry = ""
    @FocusState private var customFocused: Bool
    @State private var detailEntry = ""
    @State private var detailKind: ProfileFact.Kind = .experience

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

                HStack(alignment: .top, spacing: Space.m) {
                    PhotoPickerAvatar(photo: $profile.photo, name: profile.displayName, size: 64)
                    BumpField(label: "Display name", placeholder: "What should people call you?",
                              text: $profile.displayName)
                }

                BumpField(label: "Short bio (optional)", placeholder: "One line about you",
                          axis: .vertical, text: $profile.bio)

                VStack(alignment: .leading, spacing: Space.s) {
                    SectionHeading(
                        title: "What are you into?",
                        subtitle: "Start with a topic, then pick anything more specific. “Cold brew” starts a better conversation than “Coffee”."
                    )

                    TopicBrowser(isSelected: { selectedIDs.contains($0.id) }, toggle: toggle)
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

                VStack(alignment: .leading, spacing: Space.s) {
                    SectionHeading(title: "Experiences & goals",
                                   subtitle: "Shared with confirmed partners, like your interests.")
                    ForEach(profile.details) { fact in
                        HStack(alignment: .top) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(fact.text).font(BumpFont.body).foregroundStyle(BumpColor.navy)
                                    .fixedSize(horizontal: false, vertical: true)
                                Text(fact.kind == .goal ? "Goal" : "Experience")
                                    .font(BumpFont.caption).foregroundStyle(BumpColor.secondaryText)
                            }
                            Spacer()
                            Button {
                                profile.details.removeAll { $0.id == fact.id }
                            } label: {
                                Image(systemName: "xmark.circle.fill").foregroundStyle(BumpColor.secondaryText)
                            }
                            .accessibilityLabel("Remove \(fact.text)")
                        }
                    }
                    Picker("Kind", selection: $detailKind) {
                        Text("Experience").tag(ProfileFact.Kind.experience)
                        Text("Goal").tag(ProfileFact.Kind.goal)
                    }
                    .pickerStyle(.segmented)
                    BumpField(label: "Add one", placeholder: detailKind == .goal ? "e.g. Find a climbing partner" : "e.g. Built a weather station",
                              text: $detailEntry)
                        .onSubmit(addDetail)
                    Button("Add", action: addDetail)
                        .buttonStyle(.bumpSecondary)
                        .disabled(detailEntry.trimmed().isEmpty)
                }

                Button(isOnboarding ? "Start bumping" : "Save", action: onDone)
                    .buttonStyle(.bumpPrimary)
                    .disabled(!profile.isComplete)

                if !profile.isComplete {
                    Text("Add a name and at least one interest, experience or goal to continue.")
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

    private func addDetail() {
        let text = String(detailEntry.trimmed().prefix(60))
        guard !text.isEmpty else { return }
        profile.details.append(ProfileFact(kind: detailKind, text: text))
        detailEntry = ""
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
