import SwiftUI

struct BumpScreen: View {
    @ObservedObject var engine: BumpEngine
    @ObservedObject var store: Store

    @State private var roomCode = ""
    @State private var showManualPicker = false
    @State private var showEventCode = false
    @State private var showTutorial = false
    @AppStorage(Store.tutorialSeenKey) private var tutorialSeen = false

    var body: some View {
        NavigationStack {
            Screen(backdrop: .hero) {
                VStack(alignment: .leading, spacing: Space.l) {
                    header

                    switch engine.room {
                    case .none:
                        roomSetup
                    case .hosting, .joined, .hostLost:
                        roomActive
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .principal) { Wordmark() } }
            .sheet(isPresented: $showManualPicker) { manualPicker }
            .sheet(isPresented: $showEventCode) { eventCodeSheet }
            .fullScreenCover(isPresented: .constant(isRevealing)) { revealCover }
            .fullScreenCover(isPresented: $showTutorial) {
                BumpTutorial { tutorialSeen = true; showTutorial = false }
            }
            .onAppear {
                // First visit: explain bumping before anything else.
                if (!tutorialSeen && DemoMode.active == nil) || DemoMode.active == .tutorial { showTutorial = true }
            }
        }
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            if let code = engine.room.code, code != BumpEngine.nearbyRoom {
                HStack {
                    StatusPill(text: roomLabel(code), tone: roomTone)
                    Spacer()
                    if let capacity = engine.capacityNote {
                        Text(capacity)
                            .font(BumpFont.caption)
                            .foregroundStyle(BumpColor.secondaryText)
                    }
                }
            }
        }
    }

    private func roomLabel(_ code: String) -> String {
        switch engine.room {
        case .hosting: return "Hosting “\(code)”"
        case .joined: return "In “\(code)”"
        case .hostLost: return "Host left “\(code)”"
        case .none: return ""
        }
    }

    private var roomTone: StatusTone {
        switch engine.room {
        case .hostLost: return .bad
        case .hosting, .joined: return .good
        case .none: return .neutral
        }
    }

    // MARK: Home (not bumping yet)

    private var roomSetup: some View {
        VStack(spacing: Space.l) {
            PhonesIllustration(animated: true)
                .padding(.vertical, 40)
                .floaters([
                    Floater(text: FloaterLine.mixer, alignment: .topLeading, offset: CGSize(width: -4, height: -6), rotation: -3),
                    Floater(text: FloaterLine.film, isMe: true, alignment: .bottomTrailing, offset: CGSize(width: 4, height: 6), rotation: 4),
                ])

            title("Meet someone new",
                  "Tap phones with the person in front of you and see what you have in common.")

            Button { engine.startNearby() } label: {
                TrailingIconLabel("Start bumping", systemImage: "iphone.radiowaves.left.and.right")
            }
            .buttonStyle(.bumpPrimary)

            howItWorks

            Button("Have an event code?") { showEventCode = true }
                .font(BumpFont.captionEmphasis)
                .foregroundStyle(BumpColor.secondaryText)
        }
        .frame(maxWidth: .infinity)
    }

    /// Three quiet steps, always visible on the home screen: the site's
    /// "bump, confirm, connect" cards, as pill rows with orbs.
    private var howItWorks: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            HStack {
                Eyebrow("How it works")
                Spacer()
                Button("Watch the tour") { showTutorial = true }
                    .font(BumpFont.captionEmphasis)
                    .foregroundStyle(BumpColor.primary)
            }
            .padding(.horizontal, Space.xs)
            step("iphone.radiowaves.left.and.right", BumpColor.primary, "You both tap Start bumping")
            step("person.crop.circle.badge.checkmark", BumpColor.secondary, "Gently tap your phones together")
            step("sparkles", BumpColor.tertiary, "Both confirm, then see what you share")
        }
    }

    private func step(_ systemImage: String, _ tint: Color, _ text: String) -> some View {
        RowPill {
            IconOrb(systemImage: systemImage, size: 44, tint: tint)
        } content: {
            RowText.title(text)
        }
        .accessibilityElement(children: .combine)
    }

    /// Named rooms, for a big event that needs more than one (8 phones each).
    private var eventCodeSheet: some View {
        NavigationStack {
            Screen {
                VStack(alignment: .leading, spacing: Space.l) {
                    SectionHeading(
                        title: "Join a specific event",
                        subtitle: "Only needed at big events. Everyone using the same code ends up together. A room holds up to \(PeerTransport.maxPeers) phones."
                    )
                    BumpField(label: "Event code", placeholder: "hackgt", text: $roomCode)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    VStack(spacing: Space.s) {
                        Button("Join this event") { showEventCode = false; engine.join(roomCode: roomCode) }
                            .buttonStyle(.bumpPrimary)
                            .disabled(roomCode.trimmed().isEmpty)
                        Button("Host it on this phone") { showEventCode = false; engine.host(roomCode: roomCode) }
                            .buttonStyle(.bumpSecondary)
                            .disabled(roomCode.trimmed().isEmpty)
                    }
                    if !engine.transport.discoveredRooms.isEmpty {
                        VStack(alignment: .leading, spacing: Space.s) {
                            Eyebrow("Events nearby")
                            FlowLayout {
                                ForEach(engine.transport.discoveredRooms.keys.sorted().filter { $0 != BumpEngine.nearbyRoom }, id: \.self) { code in
                                    InterestChip(title: code) {
                                        roomCode = code; showEventCode = false; engine.join(roomCode: code)
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Event code")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { showEventCode = false } }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationCornerRadius(28)
    }

    // MARK: Room active

    @ViewBuilder
    private var roomActive: some View {
        switch engine.phase {

        case .confirming(let proposal):
            ConfirmPartnerView(
                proposal: proposal,
                onConfirm: { engine.confirmCurrent() },
                onDecline: { engine.declineCurrent() }
            )

        case .waitingForPartner:
            statusCard(
                systemImage: "person.crop.circle.badge.checkmark",
                title: "Waiting for them to confirm",
                body: "They need to tap confirm on their phone too.",
                tone: .active,
                busy: true,
                actions: [("Cancel", { engine.declineCurrent(reason: "Cancelled.") }, false)]
            )

        case .exchanging:
            statusCard(
                systemImage: "sparkles",
                title: "Swapping interests",
                body: "Only the two of you see each other's profiles.",
                tone: .active, busy: true, actions: []
            )

        case .checking:
            statusCard(
                systemImage: "iphone.radiowaves.left.and.right",
                title: "Felt that. Finding who you bumped…",
                body: "Hold still for a moment.",
                tone: .active, busy: true,
                actions: [("Cancel", { engine.setReady(false) }, false)]
            )

        case .timedOut:
            statusCard(
                systemImage: "person.fill.questionmark",
                title: "Nobody bumped back",
                body: "Make sure they're in the same event and tapped ready too.",
                tone: .warn, busy: false,
                actions: [("Try again", { engine.bumpAgain() }, true),
                          ("Pick someone instead", { showManualPicker = true }, false)]
            )

        case .ambiguous(let count):
            statusCard(
                systemImage: "person.3.fill",
                title: "A few people bumped at once",
                body: "\(count) bumps landed at almost the same moment, so BUMP can't tell who was yours. Try again with a little space, or pick them from the room.",
                tone: .warn, busy: false,
                actions: [("Try again", { engine.bumpAgain() }, true),
                          ("Pick someone instead", { showManualPicker = true }, false)]
            )

        case .needsRetry(let reason):
            statusCard(
                systemImage: "arrow.clockwise",
                title: "Didn't connect",
                body: reason,
                tone: .warn, busy: false,
                actions: [("Try again", { engine.bumpAgain() }, true),
                          (engine.nearbyMode ? "Stop bumping" : "Leave event", { leave() }, false)]
            )

        case .unavailable(let reason):
            statusCard(
                systemImage: "exclamationmark.triangle.fill",
                title: "Can't use the sensors",
                body: reason,
                tone: .bad, busy: false,
                actions: [("Pick someone instead", { showManualPicker = true }, true),
                          (engine.nearbyMode ? "Stop bumping" : "Leave event", { leave() }, false)]
            )

        case .ready:
            readyState

        case .preparing:
            statusCard(systemImage: "iphone.radiowaves.left.and.right", title: "Getting ready", body: "Starting the sensors.",
                       tone: .active, busy: true, actions: [])

        case .connected:
            EmptyView()          // shown in the full-screen reveal

        case .notReady:
            notReadyState
        }
    }

    private var notReadyState: some View {
        VStack(spacing: Space.l) {
            if engine.nearbyMode && engine.members.isEmpty {
                ZStack {
                    PulseRings(active: true)
                    IconOrb(systemImage: "location.magnifyingglass", size: 96)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, Space.l)
                .floaters([Floater(text: FloaterLine.lecture, alignment: .topLeading, rotation: -4)])
                title("Looking for people nearby…",
                      "Ask the person you want to meet to open BUMP and tap Start bumping.")
            } else {
                ZStack {
                    PulseRings(active: false)
                    PhonesIllustration(apart: true)
                }
                .frame(maxWidth: .infinity)
                title("Ready when you are", "Tap below, then gently tap phones with the person you want to meet.")
                Button { engine.setReady(true) } label: {
                    TrailingIconLabel("Ready to bump", systemImage: "iphone.radiowaves.left.and.right")
                }
                .buttonStyle(.bumpPrimary)
            }

            nearbyPeople

            Button(engine.nearbyMode ? "Stop bumping" : "Leave event", action: leave)
                .buttonStyle(.bumpSecondary)
        }
        .frame(maxWidth: .infinity)
    }

    private var readyState: some View {
        VStack(spacing: Space.l) {
            ZStack {
                PulseRings(active: true)
                PhonesIllustration(animated: true)
            }
            .frame(maxWidth: .infinity)
            .floaters([Floater(text: FloaterLine.film, isMe: true, alignment: .topTrailing, rotation: 4)])

            title("Tap your phones together",
                  "A gentle tap, back to back, with the person you want to meet. BUMP is listening.")

            nearbyPeople

            Button("Stop bumping", action: leave)
                .buttonStyle(.bumpSecondary)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Ready to bump. Tap your phones together.")
    }

    private func title(_ heading: String, _ detail: String) -> some View {
        VStack(spacing: Space.s) {
            ScreenTitle(heading, alignment: .center)
            Text(detail)
                .font(BumpFont.body)
                .foregroundStyle(BumpColor.secondaryText)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, Space.s)
    }

    /// Who else has BUMP open nearby. Names only; interests stay private
    /// until two people confirm a bump.
    @ViewBuilder
    private var nearbyPeople: some View {
        if !engine.members.isEmpty {
            RowPill {
                HStack(spacing: -12) {
                    ForEach(Array(engine.members.prefix(3).enumerated()), id: \.element.id) { i, member in
                        Avatar(name: member.displayName, size: 40,
                               tint: i.isMultiple(of: 2) ? BumpColor.illustrationWarm : BumpColor.primary)
                    }
                }
                .accessibilityHidden(true)
            } content: {
                RowText.title(engine.members.count == 1 ? "1 person nearby" : "\(engine.members.count) people nearby")
            } trail: {
                Circle().fill(BumpColor.positive).frame(width: 8, height: 8).padding(.trailing, 4)
            }
        }
    }

    private func leave() {
        if engine.nearbyMode { engine.stopNearby() } else { engine.leaveRoom() }
    }

    // MARK: Reveal

    private var isRevealing: Bool {
        if case .connected = engine.phase { return true }
        return false
    }

    @ViewBuilder
    private var revealCover: some View {
        if case .connected(let result) = engine.phase {
            // The cover sits above the root, so it carries its own demo badge —
            // demo data must never appear unlabelled.
            VStack(spacing: 0) {
                if DemoMode.active != nil { DemoBadge() }
                RevealView(
                    result: result,
                    myName: store.profile.displayName,
                    myPhoto: store.profile.photo,
                    onSave: { engine.saveCurrentConnection(); engine.bumpAgain() },
                    onAgain: { engine.bumpAgain() }
                )
            }
        }
    }

    // MARK: Manual picker

    private var manualPicker: some View {
        NavigationStack {
            Screen {
                VStack(alignment: .leading, spacing: Space.l) {
                    SectionHeading(
                        title: "Pick the person",
                        subtitle: "BUMP couldn't tell who you bumped, so you're choosing manually. This gets saved as a manual pick, not a detected bump."
                    )
                    if engine.members.isEmpty {
                        Text("Nobody else is in this event yet.")
                            .font(BumpFont.body)
                            .foregroundStyle(BumpColor.secondaryText)
                    }
                    VStack(spacing: Space.s) {
                        ForEach(Array(engine.members.enumerated()), id: \.element.id) { i, member in
                            Button {
                                showManualPicker = false
                                engine.proposeManually(with: member)
                            } label: {
                                RowPill {
                                    Avatar(name: member.displayName, size: 44,
                                           tint: i.isMultiple(of: 2) ? BumpColor.illustrationWarm : BumpColor.primary)
                                } content: {
                                    RowText.title(member.displayName)
                                } trail: {
                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundStyle(BumpColor.faint)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .navigationTitle("Pick someone")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { showManualPicker = false }
                }
            }
        }
        .presentationCornerRadius(28)
    }

    // MARK: Status card

    /// Busy: an orb in pulse rings over a toast with a spinner.
    /// Stopped: a peach bento with the problem, then the actions.
    @ViewBuilder
    private func statusCard(systemImage: String, title: String, body: String, tone: StatusTone, busy: Bool,
                            actions: [(String, () -> Void, Bool)]) -> some View {
        VStack(alignment: .leading, spacing: Space.m) {
            if busy {
                ZStack {
                    PulseRings(active: true)
                    IconOrb(systemImage: systemImage, size: 96)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, Space.l)
                Toast(systemImage: systemImage, title: title, message: body) {
                    ProgressView().tint(BumpColor.primary)
                }
            } else {
                Bento(wash: .peach) {
                    IconOrb(systemImage: systemImage, size: 52,
                            tint: tone == .bad ? BumpColor.negative : BumpColor.illustrationWarm)
                    ScreenTitle(title)
                    Text(body)
                        .font(BumpFont.body)
                        .foregroundStyle(BumpColor.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.top, Space.m)
            }
            VStack(spacing: Space.s) {
                ForEach(Array(actions.enumerated()), id: \.offset) { _, action in
                    Button(action.0, action: action.1)
                        .buttonStyle(action.2 ? AnyButtonStyleWrapper(.bumpPrimary) : AnyButtonStyleWrapper(.bumpSecondary))
                }
            }
            .padding(.top, Space.s)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Small shim so a row can choose primary vs secondary at runtime.
struct AnyButtonStyleWrapper: ButtonStyle {
    private let makeBody: (Configuration) -> AnyView

    init(_ style: PrimaryButtonStyle) {
        makeBody = { AnyView(style.makeBody(configuration: $0)) }
    }
    init(_ style: SecondaryButtonStyle) {
        makeBody = { AnyView(style.makeBody(configuration: $0)) }
    }
    func makeBody(configuration: Configuration) -> some View { makeBody(configuration) }
}
