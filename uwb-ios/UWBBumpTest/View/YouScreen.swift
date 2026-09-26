import SwiftUI

struct YouScreen: View {
    @ObservedObject var store: Store
    @ObservedObject var engine: BumpEngine

    var body: some View {
        NavigationStack {
            Screen {
                VStack(alignment: .leading, spacing: Space.l) {
                    HStack(spacing: Space.m) {
                        Avatar(name: store.profile.displayName, size: 64)
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
                                          engine.ranging.permissionDenied ? "Denied — enable in Settings" : "OK",
                                          engine.ranging.permissionDenied ? .bad : .good)
                            Divider()
                            permissionRow("On-device AI", ConversationService.availabilityDescription,
                                          ConversationService.onDeviceModelAvailable ? .good : .neutral)
                        }
                    }

                    Text("BUMP needs Local Network and Nearby Interaction access to find the phone next to you. Nothing leaves your phone except what you share with a confirmed partner, and there is no account or server.")
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
