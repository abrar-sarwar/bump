import SwiftUI

struct YouScreen: View {
    @ObservedObject var store: Store
    @ObservedObject var engine: BumpEngine

    var body: some View {
        NavigationStack {
            Screen(backdrop: .soft) {
                VStack(alignment: .leading, spacing: Space.l) {
                    profileCard

                    Bento(wash: .lilac, label: "Cloud processing", systemImage: "cloud.fill") {
                        Text("Voice transcription, profile drafting and Grok talking points go through the BUMP server to xAI. Talking points use Grok only when you AND the person you bump both allow it.")
                            .font(BumpFont.caption)
                            .foregroundStyle(BumpColor.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
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
                        .tint(BumpColor.primary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.white.opacity(0.7)))
                    }

                    VStack(alignment: .leading, spacing: Space.s) {
                        Eyebrow("Permissions & help")
                            .padding(.horizontal, Space.xs)
                        permissionRow("iphone.radiowaves.left.and.right", "Motion",
                                      engine.motion.isAvailable ? "Available" : "Not available on this iPhone",
                                      engine.motion.isAvailable ? .good : .bad)
                        permissionRow("dot.radiowaves.left.and.right", "Ultra-wideband",
                                      engine.ranging.isSupported
                                        ? (engine.ranging.supportsDirection ? "Distance and direction" : "Distance only")
                                        : "Not supported on this iPhone",
                                      engine.ranging.isSupported ? .good : .warn)
                        permissionRow("location.fill", "Nearby Interaction permission",
                                      engine.ranging.permissionDenied ? "Denied. Turn it on in Settings" : "OK",
                                      engine.ranging.permissionDenied ? .bad : .good)
                        permissionRow("sparkles", "On-device AI", ConversationService.availabilityDescription,
                                      ConversationService.onDeviceModelAvailable ? .good : .neutral)
                    }

                    Text("BUMP needs Local Network and Nearby Interaction access to find the phone next to you. Your card goes only to a partner you've both confirmed, directly between the two phones. There's no account. With cloud processing off, nothing goes to the BUMP server or xAI.")
                        .font(BumpFont.caption)
                        .foregroundStyle(BumpColor.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, Space.xs)

                    VStack(spacing: Space.s) {
                        Button {
                            if let url = URL(string: UIApplication.openSettingsURLString) {
                                UIApplication.shared.open(url)
                            }
                        } label: {
                            TrailingIconLabel("Open iPhone Settings", systemImage: "gearshape.fill")
                        }
                        .buttonStyle(.bumpSecondary)

                        NavigationLink {
                            TestingToolsScreen(engine: engine, store: store)
                        } label: {
                            Text("Testing tools")
                        }
                        .buttonStyle(.bumpSecondary)
                    }
                }
            }
            .navigationTitle("You")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    /// The site's person card: an orb avatar, the name, your bio as a bubble,
    /// your interests as tags.
    private var profileCard: some View {
        Card(padding: 22) {
            VStack(alignment: .leading, spacing: Space.m) {
                HStack(spacing: Space.m) {
                    PhotoPickerAvatar(photo: $store.profile.photo, name: store.profile.displayName, size: 72)
                    VStack(alignment: .leading, spacing: 2) {
                        ScreenTitle(store.profile.displayName.isEmpty ? "You" : store.profile.displayName)
                        Text("\(store.profile.interests.count) interests")
                            .font(BumpFont.caption)
                            .foregroundStyle(BumpColor.secondaryText)
                    }
                }

                if !store.profile.bio.isEmpty {
                    ChatBubble(store.profile.bio)
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
                            Eyebrow(kind.title)
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
                    TrailingIconLabel("Edit profile", systemImage: "pencil")
                }
                .buttonStyle(.bumpTonal)
            }
        }
    }

    private var cloudStatusText: String {
        switch store.privacy.cloud {
        case .undecided: return "Not chosen yet, so nothing is sent."
        case .localOnly: return "Off. Nothing goes to the BUMP server or xAI, and you type instead of speak."
        case .allowed: return engine.grokReady ? "On. The BUMP server is reachable and Grok is ready." : "On, but the BUMP server isn't reachable right now, so BUMP uses on-phone suggestions."
        }
    }

    private func permissionRow(_ systemImage: String, _ title: String, _ value: String, _ tone: StatusTone) -> some View {
        RowPill {
            IconOrb(systemImage: systemImage, size: 40)
        } content: {
            RowText.title(title)
            RowText.subtitle(value)
        } trail: {
            Circle().fill(tone.color).frame(width: 8, height: 8).padding(.trailing, 4)
        }
        .accessibilityElement(children: .combine)
    }
}
