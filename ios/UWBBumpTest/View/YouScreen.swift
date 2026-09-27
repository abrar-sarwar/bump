import SwiftUI

struct YouScreen: View {
    @ObservedObject var store: Store
    @ObservedObject var engine: BumpEngine
    @State private var showCloudInfo = false

    var body: some View {
        NavigationStack {
            Screen(backdrop: .soft) {
                VStack(alignment: .leading, spacing: Space.l) {
                    profileCard

                    Card {
                        HStack(spacing: Space.s) {
                            Text("Allow cloud processing")
                                .font(BumpFont.bodyEmphasis)
                                .foregroundStyle(BumpColor.navy)
                            Button { showCloudInfo = true } label: {
                                Image(systemName: "info.circle")
                                    .font(.system(size: 20))
                                    .foregroundStyle(BumpColor.primary)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("About cloud processing")
                            Spacer(minLength: 0)
                        Toggle(isOn: Binding(
                            get: { store.privacy.allowsCloud },
                            set: { store.privacy.cloud = $0 ? .allowed : .localOnly; engine.refreshCloudStatus() })) {
                            Text("Allow cloud processing")
                        }
                        .labelsHidden()
                        .tint(BumpColor.primary)
                        }
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
            .sheet(isPresented: $showCloudInfo) { cloudInfoSheet }
        }
    }

    private var cloudInfoSheet: some View {
        NavigationStack {
            Screen {
                VStack(alignment: .leading, spacing: Space.m) {
                    Text("With this on, BUMP sends your intro and answers through its server to xAI for transcription and Grok suggestions. Talking points use Grok only when both people allow it.")
                    Text("The BUMP server doesn't store your audio or text. xAI says API requests can be kept for up to 30 days for auditing. Turn this off to keep drafting on your phone.")
                    Text(cloudStatusText)
                        .foregroundStyle(BumpColor.secondaryText)
                }
                .font(BumpFont.body)
                .fixedSize(horizontal: false, vertical: true)
            }
            .navigationTitle("Cloud processing")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { showCloudInfo = false } } }
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
    }

    /// The person's card: a flat avatar, name, bio,
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
                    Text(store.profile.bio)
                        .font(BumpFont.body)
                        .foregroundStyle(BumpColor.secondaryText)
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
