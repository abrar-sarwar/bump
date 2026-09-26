import SwiftUI

struct BumpScreen: View {
    @ObservedObject var engine: BumpEngine
    @ObservedObject var store: Store

    @State private var roomCode = ""
    @State private var showManualPicker = false
    @State private var showEventCode = false
    @State private var showTutorial = false
    @State private var showNotifications = false
    @AppStorage(Store.tutorialSeenKey) private var tutorialSeen = false
    /// When the feed was last opened, so the bell can show a dot for what's new.
    @AppStorage("bump.notificationsSeenAt") private var notificationsSeenAt = 0.0

    var body: some View {
        NavigationStack {
            Screen {
                VStack(alignment: .leading, spacing: Space.l) {
                    topBar
                    header

                    // Waiting is one screen whether or not the room is up yet:
                    // joining happens by itself, so the person never sees a
                    // "not started" state they have to act on.
                    if engine.room == .none { ambientHome } else { roomActive }
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $showManualPicker) { manualPicker }
            .sheet(isPresented: $showEventCode) { eventCodeSheet }
            .sheet(isPresented: $showNotifications) { NotificationsScreen(store: store) }
            .fullScreenCover(isPresented: .constant(isRevealing)) { revealCover }
            .fullScreenCover(isPresented: $showTutorial) {
                BumpTutorial { tutorialSeen = true; showTutorial = false }
            }
            .onAppear {
                // First visit: explain bumping before anything else.
                if (!tutorialSeen && DemoMode.active == nil) || DemoMode.active == .tutorial { showTutorial = true }
                // Begin waiting for a bump straight away. autoStart is
                // idempotent, so tab switches and repeated appearances never
                // open a second session.
                if DemoMode.active == nil { engine.autoStart() }
                // DEBUG demo: land straight on the feed so it can be inspected.
                if DemoMode.active == .notifications { showNotifications = true }
            }
        }
    }

    // MARK: Top bar

    /// M3 small top app bar, drawn in the page: wordmark plus three icon actions.
    private var topBar: some View {
        HStack(spacing: Space.xs) {
            Wordmark()
            Spacer()
            Button {
                notificationsSeenAt = Date().timeIntervalSince1970
                showNotifications = true
            } label: {
                Image(systemName: unreadCount > 0 ? "bell.badge.fill" : "bell")
            }
            .buttonStyle(.bumpIcon)
            .accessibilityLabel("Notifications")
            .accessibilityValue(unreadCount > 0 ? "\(unreadCount) new" : "Nothing new")
            Button { showTutorial = true } label: { Image(systemName: "questionmark.circle") }
                .buttonStyle(.bumpIcon)
                .accessibilityLabel("How BUMP works")
            Button { showEventCode = true } label: { Image(systemName: "ticket") }
                .buttonStyle(.bumpIcon)
                .accessibilityLabel("Event code")
        }
        .padding(.top, -Space.s)
    }

    /// Bumps and passers-by since the feed was last opened.
    private var unreadCount: Int {
        let seen = Date(timeIntervalSince1970: notificationsSeenAt)
        return store.connections.filter { $0.metOn > seen }.count
            + store.streetpasses.filter { $0.seenAt > seen }.count
    }

    // MARK: Header

    @ViewBuilder
    private var header: some View {
        if let code = engine.room.code, code != BumpEngine.nearbyRoom {
            HStack {
                StatusPill(text: roomLabel(code), tone: roomTone, icon: roomIcon)
                Spacer()
                if let capacity = engine.capacityNote {
                    Text(capacity)
                        .font(BumpFont.bodySmall)
                        .foregroundStyle(BumpColor.onSurfaceVariant)
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

    private var roomIcon: String? {
        switch engine.room {
        case .hostLost: return "exclamationmark.triangle.fill"
        case .hosting: return "antenna.radiowaves.left.and.right"
        case .joined: return "ticket.fill"
        case .none: return nil
        }
    }

    // MARK: Ambient home

    /// The waiting screen. There is no Start button: opening BUMP is the start.
    private var ambientHome: some View {
        VStack(spacing: Space.l) {
            // The bump hero: rings + phones + the honest readiness line.
            ZStack {
                PulseRings(active: engine.autoStatus == .listening)
                PhonesIllustration(animated: engine.autoStatus == .listening)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, Space.s)

            readinessIndicator

            switch engine.autoStatus {
            case .blocked(let step):
                title("One thing first", step)
                Button("Open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
                .buttonStyle(.bumpPrimary)

            case .paused:
                title("Paused", "BUMP isn't listening for a bump right now.")
                Button("Resume") { engine.resume() }
                    .buttonStyle(.bumpPrimary)

            case .gettingReady:
                title("Getting ready", "Finding the phones around you.")

            case .listening:
                if engine.members.isEmpty {
                    title("Waiting for someone to meet",
                          "Ask the person in front of you to open BUMP too.")
                } else {
                    title("Tap your phones together",
                          "A gentle tap, back to back, with the person you want to meet.")
                }
            }

            nearbyPeople

            howItWorks

            secondaryControls
        }
        .frame(maxWidth: .infinity)
    }

    /// Compact, honest status. It says "Ready to bump" only once the motion
    /// sensor is actually running inside a live room.
    private var readinessIndicator: some View {
        HStack(spacing: Space.s) {
            switch engine.autoStatus {
            case .gettingReady:
                LoadingIndicator(size: 14)
                Text("Getting ready…")
            case .listening:
                BreathingDot()
                Text("Ready to bump")
            case .paused:
                Circle().fill(BumpColor.onSurfaceVariant).frame(width: 9, height: 9)
                Text("Paused")
            case .blocked:
                Circle().fill(BumpColor.warning).frame(width: 9, height: 9)
                Text("Needs one step")
            }
        }
        .font(BumpFont.labelLarge)
        .foregroundStyle(BumpColor.onSurface)
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(Capsule().fill(BumpColor.primaryContainer))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(readinessLabel)
    }

    private var readinessLabel: String {
        switch engine.autoStatus {
        case .gettingReady: return "Getting ready"
        case .listening: return "Ready to bump. Tap your phones together."
        case .paused: return "Paused"
        case .blocked(let step): return "Setup needed. \(step)"
        }
    }

    /// Small and secondary on purpose: pausing is the exception, not the flow.
    @ViewBuilder
    private var secondaryControls: some View {
        HStack(spacing: Space.s) {
            if engine.autoStatus != .paused, engine.setupBlocker == nil {
                Button("Pause", systemImage: "pause.fill") { engine.pause() }
                    .buttonStyle(.bumpText(BumpColor.onSurfaceVariant))
            }
            Button("Have an event code?") { showEventCode = true }
                .buttonStyle(.bumpText(BumpColor.onSurfaceVariant))
        }
    }

    /// Three quiet steps, always visible on the home screen.
    private var howItWorks: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            HStack {
                Eyebrow(text: "How it works")
                Spacer()
                Button("Watch the tour") { showTutorial = true }
                    .buttonStyle(.bumpText)
            }
            ListGroup {
                step(1, "Open BUMP on both phones", icon: "iphone.gen3")
                step(2, "Gently tap your phones together", icon: "hand.tap.fill")
                step(3, "Both confirm, then see what you share", icon: "sparkles")
            }
        }
    }

    private func step(_ n: Int, _ text: String, icon: String) -> some View {
        HStack(spacing: Space.m) {
            Text("\(n)")
                .font(BumpFont.labelLarge)
                .foregroundStyle(BumpColor.onPrimaryContainer)
                .frame(width: 40, height: 40)
                .background(Circle().fill(BumpColor.primaryContainer))
            Text(text)
                .font(BumpFont.bodyLarge)
                .foregroundStyle(BumpColor.onSurface)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Image(systemName: icon)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(BumpColor.outline)
        }
        .padding(.horizontal, Space.m)
        .padding(.vertical, 12)
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
                    VStack(spacing: Space.sm) {
                        Button("Join this event") { showEventCode = false; engine.join(roomCode: roomCode) }
                            .buttonStyle(.bumpPrimary)
                            .disabled(roomCode.trimmed().isEmpty)
                        Button("Host it on this phone") { showEventCode = false; engine.host(roomCode: roomCode) }
                            .buttonStyle(.bumpSecondary)
                            .disabled(roomCode.trimmed().isEmpty)
                    }
                    if !engine.transport.discoveredRooms.isEmpty {
                        VStack(alignment: .leading, spacing: Space.s) {
                            Eyebrow(text: "Events nearby")
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
            .toolbarBackground(BumpColor.surface, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { showEventCode = false } }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationCornerRadius(Radius.extraLarge)
        .presentationDragIndicator(.visible)
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
                title: "Waiting for them to confirm",
                body: "They need to tap confirm on their phone too.",
                tone: .active,
                busy: true,
                actions: [("Cancel", { engine.declineCurrent(reason: "Cancelled.") }, false)]
            )

        case .exchanging:
            statusCard(
                title: "Swapping interests",
                body: "Only the two of you see each other's profiles.",
                tone: .active, busy: true, actions: []
            )

        case .checking:
            statusCard(
                title: "Felt that. Finding who you bumped…",
                body: "Hold still for a moment.",
                tone: .active, busy: true,
                actions: [("Cancel", { engine.setReady(false) }, false)]
            )

        case .timedOut:
            statusCard(
                title: "Nobody bumped back",
                body: "Make sure they're in the same event and tapped ready too.",
                tone: .warn, busy: false,
                actions: [("Try again", { engine.bumpAgain() }, true),
                          ("Pick someone instead", { showManualPicker = true }, false)]
            )

        case .ambiguous(let count):
            statusCard(
                title: "A few people bumped at once",
                body: "\(count) bumps landed at almost the same moment, so BUMP can't tell who was yours. Try again with a little space, or pick them from the room.",
                tone: .warn, busy: false,
                actions: [("Try again", { engine.bumpAgain() }, true),
                          ("Pick someone instead", { showManualPicker = true }, false)]
            )

        case .needsRetry(let reason):
            statusCard(
                title: "Didn't connect",
                body: reason,
                tone: .warn, busy: false,
                actions: [("Try again", { engine.bumpAgain() }, true),
                          ("Leave event", { leave() }, false)]
            )

        case .unavailable(let reason):
            statusCard(
                title: "Can't use the sensors",
                body: reason,
                tone: .bad, busy: false,
                actions: [("Pick someone instead", { showManualPicker = true }, true),
                          ("Leave event", { leave() }, false)]
            )

        case .ready, .preparing, .notReady:
            ambientHome

        case .connected:
            EmptyView()          // shown in the full-screen reveal
        }
    }

    private func title(_ heading: String, _ detail: String) -> some View {
        VStack(spacing: Space.s) {
            Text(heading)
                .font(BumpFont.headlineLarge)
                .foregroundStyle(BumpColor.onSurface)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Text(detail)
                .font(BumpFont.bodyLarge)
                .foregroundStyle(BumpColor.onSurfaceVariant)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, Space.m)
        .contentTransition(.opacity)
    }

    /// Who else has BUMP open nearby. Names only; interests stay private
    /// until two people confirm a bump.
    @ViewBuilder
    private var nearbyPeople: some View {
        if !engine.members.isEmpty {
            HStack(spacing: Space.sm) {
                HStack(spacing: -10) {
                    ForEach(engine.members.prefix(6)) { member in
                        Avatar(name: member.displayName, size: 36)
                            .overlay(Circle().strokeBorder(BumpColor.surface, lineWidth: 2))
                    }
                }
                .accessibilityHidden(true)
                Text(engine.members.count == 1 ? "1 person nearby" : "\(engine.members.count) people nearby")
                    .font(BumpFont.labelLarge)
                    .foregroundStyle(BumpColor.positive)
            }
            .padding(.leading, 6)
            .padding(.trailing, 14)
            .padding(.vertical, 6)
            .background(Capsule().fill(BumpColor.positiveContainer))
            .transition(.scale(scale: 0.9).combined(with: .opacity))
        }
    }

    /// Only reachable from a named event room. Leaving drops back to waiting
    /// for whoever is nearby rather than stopping BUMP altogether.
    private func leave() {
        engine.leaveEvent()
    }

    // MARK: Reveal

    private var isRevealing: Bool {
        if case .connected = engine.phase { return true }
        return false
    }

    @ViewBuilder
    private var revealCover: some View {
        if case .connected(let result) = engine.phase {
            // The cover sits above the root, so it carries its own demo badge,
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
                            .font(BumpFont.bodyLarge)
                            .foregroundStyle(BumpColor.onSurfaceVariant)
                    } else {
                        ListGroup {
                            ForEach(engine.members) { member in
                                Button {
                                    showManualPicker = false
                                    engine.proposeManually(with: member)
                                } label: {
                                    HStack(spacing: Space.m) {
                                        Avatar(name: member.displayName, size: 40)
                                        Text(member.displayName)
                                            .font(BumpFont.titleMedium)
                                            .foregroundStyle(BumpColor.onSurface)
                                        Spacer()
                                        Chevron()
                                    }
                                    .padding(.horizontal, Space.m)
                                    .padding(.vertical, 12)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(NavigationRowStyle())
                            }
                        }
                    }
                }
            }
            .navigationTitle("Pick someone")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(BumpColor.surface, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { showManualPicker = false }
                }
            }
        }
        .presentationCornerRadius(Radius.extraLarge)
        .presentationDragIndicator(.visible)
    }

    // MARK: Status card

    private func statusCard(title: String, body: String, tone: StatusTone, busy: Bool,
                            actions: [(String, () -> Void, Bool)]) -> some View {
        VStack(alignment: .leading, spacing: Space.m) {
            Card(padding: Space.l) {
                VStack(alignment: .leading, spacing: Space.m) {
                    ZStack {
                        Circle().fill(tone.container).frame(width: 48, height: 48)
                        if busy {
                            LoadingIndicator(size: 24, tint: tone.color)
                        } else {
                            Image(systemName: tone == .bad ? "xmark" : "exclamationmark")
                                .font(.system(size: 18, weight: .bold))
                                .foregroundStyle(tone.color)
                        }
                    }
                    Text(title)
                        .font(BumpFont.headlineSmall)
                        .foregroundStyle(BumpColor.onSurface)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(body)
                        .font(BumpFont.bodyLarge)
                        .foregroundStyle(BumpColor.onSurfaceVariant)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            VStack(spacing: Space.sm) {
                ForEach(Array(actions.enumerated()), id: \.offset) { _, action in
                    Button(action.0, action: action.1)
                        .buttonStyle(action.2 ? AnyButtonStyleWrapper(.bumpPrimary) : AnyButtonStyleWrapper(.bumpSecondary))
                }
            }
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
