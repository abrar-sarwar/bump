import SwiftUI

struct YouScreen: View {
    @ObservedObject var store: Store
    @ObservedObject var engine: BumpEngine

    var body: some View {
        NavigationStack {
            Screen {
                VStack(alignment: .leading, spacing: Space.l) {

                    // Profile header
                    VStack(alignment: .leading, spacing: Space.m) {
                        HStack(alignment: .center, spacing: Space.m) {
                            PhotoPickerAvatar(photo: $store.profile.photo, name: store.profile.displayName, size: 80)
                            VStack(alignment: .leading, spacing: Space.xs) {
                                Text(store.profile.displayName.isEmpty ? "You" : store.profile.displayName)
                                    .font(BumpFont.displaySmall)
                                    .foregroundStyle(BumpColor.onSurface)
                                    .lineLimit(2)
                                    .minimumScaleFactor(0.7)
                                HStack(spacing: Space.s) {
                                    stat(store.profile.interests.count, "interests")
                                    stat(store.profile.details.count, "details")
                                }
                            }
                            Spacer(minLength: 0)
                        }

                        if !store.profile.bio.isEmpty {
                            Text(store.profile.bio)
                                .font(BumpFont.bodyLarge)
                                .foregroundStyle(BumpColor.onSurface)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        if !store.profile.interests.isEmpty {
                            FlowLayout {
                                ForEach(store.profile.interests) { InterestChip(title: $0.label, selected: true) }
                            }
                        }

                        ForEach([ProfileFact.Kind.experience, .goal], id: \.self) { kind in
                            let facts = store.profile.details.filter { $0.kind == kind }
                            if !facts.isEmpty {
                                VStack(alignment: .leading, spacing: Space.s) {
                                    Eyebrow(text: kind.title)
                                    ForEach(facts) { fact in
                                        HStack(alignment: .top, spacing: Space.s) {
                                            Image(systemName: kind == .goal ? "flag.fill" : "star.fill")
                                                .font(.system(size: 11, weight: .bold))
                                                .foregroundStyle(BumpColor.tertiary)
                                                .padding(.top, 5)
                                            Text(fact.text)
                                                .font(BumpFont.bodyLarge)
                                                .foregroundStyle(BumpColor.onSurface)
                                                .fixedSize(horizontal: false, vertical: true)
                                        }
                                    }
                                }
                            }
                        }

                        NavigationLink {
                            ProfileEditor(profile: $store.profile, isOnboarding: false, onDone: {})
                        } label: {
                            Label("Edit profile", systemImage: "pencil")
                        }
                        .buttonStyle(.bumpPrimary)
                    }

                    // Cloud processing
                    VStack(alignment: .leading, spacing: Space.s) {
                        Eyebrow(text: "Cloud processing")
                        ListGroup {
                            HStack(alignment: .top, spacing: Space.m) {
                                Image(systemName: "cloud.fill")
                                    .font(.system(size: 17, weight: .semibold))
                                    .foregroundStyle(store.privacy.allowsCloud ? BumpColor.primary : BumpColor.onSurfaceVariant)
                                    .frame(width: 40, height: 40)
                                    .background(Circle().fill(store.privacy.allowsCloud ? BumpColor.primaryContainer : BumpColor.surfaceContainerHigh))
                                Toggle(isOn: Binding(
                                    get: { store.privacy.allowsCloud },
                                    set: { store.privacy.cloud = $0 ? .allowed : .localOnly; engine.refreshCloudStatus() })) {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("Allow cloud processing")
                                            .font(BumpFont.titleMedium).foregroundStyle(BumpColor.onSurface)
                                        Text(cloudStatusText)
                                            .font(BumpFont.bodyMedium).foregroundStyle(BumpColor.onSurfaceVariant)
                                            .fixedSize(horizontal: false, vertical: true)
                                    }
                                }
                                .tint(BumpColor.primary)
                            }
                            .padding(Space.m)
                        }
                        Text("Voice transcription, profile drafting and Grok talking points go through the BUMP server to xAI. Talking points use Grok only when you AND the person you bump both allow it.")
                            .font(BumpFont.bodySmall)
                            .foregroundStyle(BumpColor.onSurfaceVariant)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    // Permissions
                    VStack(alignment: .leading, spacing: Space.s) {
                        Eyebrow(text: "Permissions & capabilities")
                        ListGroup {
                            permissionRow("Motion", icon: "waveform.path.ecg",
                                          engine.motion.isAvailable ? "Available" : "Not available on this iPhone",
                                          engine.motion.isAvailable ? .good : .bad)
                            permissionRow("Ultra-wideband", icon: "dot.radiowaves.left.and.right",
                                          engine.ranging.isSupported
                                            ? (engine.ranging.supportsDirection ? "Distance and direction" : "Distance only")
                                            : "Not supported on this iPhone",
                                          engine.ranging.isSupported ? .good : .warn)
                            permissionRow("Nearby Interaction", icon: "location.fill",
                                          engine.ranging.permissionDenied ? "Denied. Turn it on in Settings" : "Allowed",
                                          engine.ranging.permissionDenied ? .bad : .good)
                            permissionRow("On-device AI", icon: "cpu",
                                          ConversationService.availabilityDescription,
                                          ConversationService.onDeviceModelAvailable ? .good : .neutral)
                        }
                        Text("BUMP needs Local Network and Nearby Interaction access to find the phone next to you. Your card goes only to a partner you've both confirmed, directly between the two phones. There's no account. With cloud processing off, nothing goes to the BUMP server or xAI.")
                            .font(BumpFont.bodySmall)
                            .foregroundStyle(BumpColor.onSurfaceVariant)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    // More
                    ListGroup {
                        Button {
                            if let url = URL(string: UIApplication.openSettingsURLString) {
                                UIApplication.shared.open(url)
                            }
                        } label: {
                            ListRow(icon: "gearshape.fill", iconTint: BumpColor.onSurfaceVariant,
                                    iconContainer: BumpColor.surfaceContainerHigh,
                                    title: "Open iPhone Settings") {
                                Image(systemName: "arrow.up.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(BumpColor.outline)
                            }
                        }
                        .buttonStyle(NavigationRowStyle())

                        NavigationLink {
                            TestingToolsScreen(engine: engine, store: store)
                        } label: {
                            ListRow(icon: "wrench.and.screwdriver.fill", iconTint: BumpColor.onSurfaceVariant,
                                    iconContainer: BumpColor.surfaceContainerHigh,
                                    title: "Testing tools", subtitle: "Live sensor readings and tuning") {
                                Chevron()
                            }
                        }
                        .buttonStyle(NavigationRowStyle())
                    }
                }
            }
            .toolbar(.hidden, for: .navigationBar)
        }
    }

    private func stat(_ count: Int, _ label: String) -> some View {
        HStack(spacing: 4) {
            Text("\(count)").font(BumpFont.labelLarge).foregroundStyle(BumpColor.onSurface)
            Text(label).font(BumpFont.bodyMedium).foregroundStyle(BumpColor.onSurfaceVariant)
        }
        .padding(.horizontal, 10)
        .frame(height: 28)
        .background(Capsule().fill(BumpColor.surfaceContainerHigh))
    }

    private var cloudStatusText: String {
        switch store.privacy.cloud {
        case .undecided: return "Not chosen yet, so nothing is sent."
        case .localOnly: return "Off. Nothing goes to the BUMP server or xAI, and you type instead of speak."
        case .allowed: return engine.grokReady ? "On. The BUMP server is reachable and Grok is ready." : "On, but the BUMP server isn't reachable right now, so BUMP uses on-phone suggestions."
        }
    }

    private func permissionRow(_ title: String, icon: String, _ value: String, _ tone: StatusTone) -> some View {
        ListRow(icon: icon, iconTint: tone.color, iconContainer: tone.container, title: title, subtitle: value) {
            Circle().fill(tone.color).frame(width: 8, height: 8)
        }
    }
}
