import SwiftUI
import UIKit

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
            Screen(backdrop: .hero) {
                VStack(alignment: .leading, spacing: Space.l) {
                    topBar
                    header

                    // Nearby discovery starts automatically. The primary
                    // action also resumes or retries it when tapped.
                    if engine.room == .none { ambientHome } else { roomActive }
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $showManualPicker) { manualPicker }
            .sheet(isPresented: $showEventCode) { eventCodeSheet }
            .sheet(isPresented: $showNotifications) { NotificationsScreen(store: store) }
            .fullScreenCover(isPresented: .constant(isRevealing)) { revealCover }
            .fullScreenCover(isPresented: $showTutorial) {
                BumpTutorial(interests: store.profile.interests) {
                    tutorialSeen = true; showTutorial = false
                }
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

    /// The waiting screen, with the steps below the first viewport.
    private var ambientHome: some View {
        VStack(spacing: Space.l) {
            VStack(spacing: Space.l) {
                Spacer(minLength: Space.s)
                ZStack {
                    PulseRings(active: engine.autoStatus == .listening)
                    PhonesIllustration(animated: engine.autoStatus == .listening)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, Space.m)

                readinessIndicator

                if let common = engine.nearbyCommon {
                    commonGroundCard(common)
                        .transition(.scale(scale: 0.92).combined(with: .opacity))
                }

                nearbyPeople
                Spacer(minLength: Space.s)

                // No Start button: opening BUMP is the start.
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

                case .preparing:
                    title("Getting ready", "Starting BUMP on this phone.")

                case .lookingForPhones(let hint):
                    title("Looking for nearby phones", hint ?? "Ask the person in front of you to open BUMP too.")
                    if hint != nil {
                        Button("Open Settings") {
                            if let url = URL(string: UIApplication.openSettingsURLString) {
                                UIApplication.shared.open(url)
                            }
                        }
                        .buttonStyle(.bumpSecondary)
                    }

                case .connecting:
                    title("Connecting", "Found a nearby phone. Joining it now.")

                case .reconnecting:
                    title("Reconnecting", "The other phone went away. Finding it again.")

                case .listening:
                    if engine.members.isEmpty {
                        title("Waiting for someone to meet",
                              "Ask the person in front of you to open BUMP too.")
                    } else {
                        title("Tap your phones together",
                              "A gentle tap, back to back, with the person you want to meet.")
                    }
                }
            }
            .frame(minHeight: max(548, UIScreen.main.bounds.height - 262))

            howItWorks
                .padding(.top, 90)
            HStack(spacing: Space.s) {
                if engine.autoStatus != .paused, engine.setupBlocker == nil {
                    Button("Pause") { engine.pause() }
                        .buttonStyle(.bumpText(BumpColor.secondaryText))
                }
                Button("Have an event code?") { showEventCode = true }
                    .buttonStyle(.bumpText(BumpColor.secondaryText))
            }
        }
        .frame(maxWidth: .infinity)
        .animation(Motion.effects, value: engine.nearbyCommon)
    }

    /// Someone within reach shares at least two broad topics. No name until
    /// both people confirm a bump.
    private func commonGroundCard(_ common: BumpEngine.NearbyCommon) -> some View {
        Card(padding: Space.l) {
            VStack(alignment: .leading, spacing: Space.s) {
                Label("Someone nearby", systemImage: "sparkles")
                    .font(BumpFont.captionEmphasis)
                    .foregroundStyle(BumpColor.primary)
                Text("You're both into \(Self.list(common.topics))")
                    .font(BumpFont.sectionTitle)
                    .foregroundStyle(BumpColor.navy)
                    .fixedSize(horizontal: false, vertical: true)
                Text(String(format: "About %.1f m away. Bump phones to connect.", common.distance))
                    .font(BumpFont.caption)
                    .foregroundStyle(BumpColor.secondaryText)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .animation(Motion.effects, value: common)
        .accessibilityElement(children: .combine)
    }

    static func list(_ items: [String]) -> String {
        switch items.count {
        case 0: return ""
        case 1: return items[0]
        case 2: return "\(items[0]) and \(items[1])"
        default: return items.dropLast().joined(separator: ", ") + " and " + items.last!
        }
    }

    private var readinessIndicator: some View {
        HStack(spacing: Space.s) {
            switch engine.autoStatus {
            case .preparing: LoadingIndicator(size: 14); Text("Getting ready…")
            case .lookingForPhones: LoadingIndicator(size: 14); Text("Looking for phones")
            case .connecting: LoadingIndicator(size: 14); Text("Connecting…")
            case .reconnecting: LoadingIndicator(size: 14); Text("Reconnecting…")
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
        .font(BumpFont.captionEmphasis)
        .foregroundStyle(BumpColor.navy)
        .padding(.horizontal, Space.m)
        .padding(.vertical, Space.s)
        .frostedCapsule()
        .accessibilityElement(children: .combine)
        .accessibilityLabel(readinessLabel)
    }

    private var readinessLabel: String {
        switch engine.autoStatus {
        case .preparing: return "Getting ready"
        case .lookingForPhones(let hint): return "Looking for nearby phones. \(hint ?? "")"
        case .connecting: return "Connecting to a nearby phone"
        case .reconnecting: return "Reconnecting"
        case .listening: return "Ready to bump. Tap your phones together."
        case .paused: return "Paused"
        case .blocked(let step): return "Setup needed. \(step)"
        }
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
            step("iphone.radiowaves.left.and.right", BumpColor.primary, "Open BUMP on both phones")
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
            .toolbarBackground(BumpColor.surface, for: .navigationBar)
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
                // bumpAgain, not setReady(false): that parked the phase at
                // .notReady with motion off and nothing to restart it.
                actions: [("Cancel", { engine.bumpAgain() }, false)]
            )

        case .timedOut:
            statusCard(
                systemImage: "person.fill.questionmark",
                title: "Nobody bumped back",
                body: "Make sure BUMP is open on their phone too, then try again.",
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
                          ("Leave event", { leave() }, false)]
            )

        case .unavailable(let reason):
            statusCard(
                systemImage: "exclamationmark.triangle.fill",
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
            ScreenTitle(heading, alignment: .center)
            Text(detail)
                .font(BumpFont.bodyLarge)
                .foregroundStyle(BumpColor.onSurfaceVariant)
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
                HStack(spacing: Space.xs) {
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
                        subtitle: "Couldn't pinpoint who you bumped. Pick the person you met."
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
            .toolbarBackground(BumpColor.surface, for: .navigationBar)
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
                        .font(BumpFont.bodyLarge)
                        .foregroundStyle(BumpColor.onSurfaceVariant)
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
