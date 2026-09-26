import SwiftUI

struct YouScreen: View {
    @ObservedObject var store: Store
    @ObservedObject var engine: BumpEngine

    var body: some View {
        NavigationStack {
            Screen {
                VStack(alignment: .leading, spacing: Space.l) {
                    HStack(spacing: Space.m) {
                        PhotoPickerAvatar(photo: $store.profile.photo, name: store.profile.displayName, size: 64)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(store.profile.displayName.isEmpty ? "You" : store.profile.displayName)
                                .font(BumpFont.screenTitle)
                                .foregroundStyle(BumpColor.navy)
                            Text("\(store.profile.interests.count) interests")
                                .font(BumpFont.caption)
                                .foregroundStyle(BumpColor.secondaryText)
                        }
                    }

                    if !store.profile.bio.isEmpty {
                        Card {
                            Text(store.profile.bio)
                                .font(BumpFont.body)
                                .foregroundStyle(BumpColor.navy)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }

                    if !store.profile.interests.isEmpty {
                        FlowLayout {
                            ForEach(store.profile.interests) { InterestChip(title: $0.label) }
                        }
                    }

                    ForEach([ProfileFact.Kind.experience, .goal], id: \.self) { kind in
                        let facts = store.profile.details.filter { $0.kind == kind }
                        if !facts.isEmpty {
                            VStack(alignment: .leading, spacing: Space.xs) {
                                Text(kind.title)
                                    .font(BumpFont.caption)
                                    .foregroundStyle(BumpColor.secondaryText)
                                ForEach(facts) { fact in
                                    Text("· \(fact.text)")
                                        .font(BumpFont.body)
                                        .foregroundStyle(BumpColor.navy)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                        }
                    }

                    NavigationLink {
                        ProfileEditor(profile: $store.profile, isOnboarding: false, onDone: {})
                    } label: {
                        Text("Edit profile")
                            .font(BumpFont.button)
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 15)
                            .background(RoundedRectangle(cornerRadius: Space.corner, style: .continuous)
                                .fill(BumpColor.action))
                    }

                    SectionHeading(title: "Cloud processing",
                                   subtitle: "Voice transcription, profile drafting and Grok talking points go through the BUMP server to xAI. Talking points use Grok only when you AND the person you bump both allow it.")
                    Card {
                        VStack(alignment: .leading, spacing: Space.s) {
                            Toggle(isOn: Binding(
                                get: { store.privacy.allowsCloud },
                                set: { store.privacy.cloud = $0 ? .allowed : .localOnly; engine.refreshCloudStatus() })) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Allow cloud processing")
                                        .font(BumpFont.bodyEmphasis).foregroundStyle(BumpColor.navy)
                                    Text(cloudStatusText)
                                        .font(BumpFont.caption).foregroundStyle(BumpColor.secondaryText)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                            .tint(BumpColor.action)
                        }
                    }

                    SectionHeading(title: "Permissions & help")

                    Card {
                        VStack(alignment: .leading, spacing: Space.s) {
                            permissionRow("Motion",
                                          engine.motion.isAvailable ? "Available" : "Not available on this iPhone",
                                          engine.motion.isAvailable ? .good : .bad)
                            Divider()
                            permissionRow("Ultra-wideband",
                                          engine.ranging.isSupported
                                            ? (engine.ranging.supportsDirection ? "Distance and direction" : "Distance only")
                                            : "Not supported on this iPhone",
                                          engine.ranging.isSupported ? .good : .warn)
                            Divider()
                            permissionRow("Nearby Interaction permission",
                                          engine.ranging.permissionDenied ? "Denied. Turn it on in Settings" : "OK",
                                          engine.ranging.permissionDenied ? .bad : .good)
                            Divider()
                            permissionRow("On-device AI", ConversationService.availabilityDescription,
                                          ConversationService.onDeviceModelAvailable ? .good : .neutral)
                        }
                    }

                    Text("BUMP needs Local Network and Nearby Interaction access to find the phone next to you. Your card goes only to a partner you've both confirmed, directly between the two phones. There's no account. With cloud processing off, nothing goes to the BUMP server or xAI.")
                        .font(BumpFont.caption)
                        .foregroundStyle(BumpColor.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)

                    Button("Open iPhone Settings") {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    }
                    .buttonStyle(.bumpSecondary)

                    NavigationLink {
                        TestingToolsScreen(engine: engine, store: store)
                    } label: {
                        Text("Testing tools")
                            .font(BumpFont.button)
                            .foregroundStyle(BumpColor.navy)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 15)
                            .background(RoundedRectangle(cornerRadius: Space.corner, style: .continuous)
                                .fill(BumpColor.surface)
                                .overlay(RoundedRectangle(cornerRadius: Space.corner, style: .continuous)
                                    .strokeBorder(BumpColor.hairline, lineWidth: 1)))
                    }
                }
            }
            .navigationTitle("You")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private var cloudStatusText: String {
        switch store.privacy.cloud {
        case .undecided: return "Not chosen yet, so nothing is sent."
        case .localOnly: return "Off. Nothing goes to the BUMP server or xAI, and you type instead of speak."
        case .allowed: return engine.grokReady ? "On. The BUMP server is reachable and Grok is ready." : "On, but the BUMP server isn't reachable right now, so BUMP uses on-phone suggestions."
        }
    }

    private func permissionRow(_ title: String, _ value: String, _ tone: StatusTone) -> some View {
        HStack(alignment: .top, spacing: Space.s) {
            Circle().fill(tone.color).frame(width: 8, height: 8).padding(.top, 6)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(BumpFont.bodyEmphasis).foregroundStyle(BumpColor.navy)
                Text(value).font(BumpFont.caption).foregroundStyle(BumpColor.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }
}
