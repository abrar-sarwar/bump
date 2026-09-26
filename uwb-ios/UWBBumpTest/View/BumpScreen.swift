import SwiftUI

struct BumpScreen: View {
    @ObservedObject var engine: BumpEngine
    @ObservedObject var store: Store

    @State private var roomCode = ""
    @State private var showManualPicker = false

    var body: some View {
        NavigationStack {
            Screen {
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
            .fullScreenCover(isPresented: .constant(isRevealing)) { revealCover }
        }
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            if let code = engine.room.code {
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

    // MARK: Room setup

    private var roomSetup: some View {
        VStack(alignment: .leading, spacing: Space.l) {
            PhonesIllustration()
                .frame(maxWidth: .infinity)

            SectionHeading(
                title: "Start or join an event",
                subtitle: "Everyone bumping together uses the same code. One phone hosts; the rest join."
            )

            BumpField(label: "Event code", placeholder: "hackgt", text: $roomCode)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()

            Button("Join this event") { engine.join(roomCode: roomCode) }
                .buttonStyle(.bumpPrimary)
                .disabled(roomCode.trimmed().isEmpty)

            Button("Host it on this phone") { engine.host(roomCode: roomCode) }
                .buttonStyle(.bumpSecondary)
                .disabled(roomCode.trimmed().isEmpty)

            if !engine.transport.discoveredRooms.isEmpty {
                VStack(alignment: .leading, spacing: Space.s) {
                    Text("Events nearby")
                        .font(BumpFont.caption)
                        .foregroundStyle(BumpColor.secondaryText)
                    FlowLayout {
                        ForEach(engine.transport.discoveredRooms.keys.sorted(), id: \.self) { code in
                            InterestChip(title: code) { roomCode = code; engine.join(roomCode: code) }
                        }
                    }
                }
            }

            Text("A room holds up to \(PeerTransport.maxPeers) phones, and BUMP measures distance with at most \(RangingService.maxConcurrentPeers) of them at a time. For a big event, run several small rooms.")
                .font(BumpFont.caption)
                .foregroundStyle(BumpColor.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
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
                          ("Leave event", { engine.leaveRoom() }, false)]
            )

        case .unavailable(let reason):
            statusCard(
                title: "Can't use the sensors",
                body: reason,
                tone: .bad, busy: false,
                actions: [("Pick someone instead", { showManualPicker = true }, true),
                          ("Leave event", { engine.leaveRoom() }, false)]
            )

        case .ready:
            readyState

        case .preparing:
            statusCard(title: "Getting ready", body: "Starting the sensors.", tone: .active, busy: true, actions: [])

        case .connected:
            EmptyView()          // shown in the full-screen reveal

        case .notReady:
            notReadyState
        }
    }

    private var notReadyState: some View {
        VStack(alignment: .leading, spacing: Space.l) {
            PhonesIllustration().frame(maxWidth: .infinity)

            SectionHeading(
                title: "Ready when you are",
                subtitle: "Tap ready, then gently tap phones with the person you want to meet."
            )

            Button("Ready to bump") { engine.setReady(true) }
                .buttonStyle(.bumpPrimary)

            if !engine.members.isEmpty {
                VStack(alignment: .leading, spacing: Space.s) {
                    Text("In this event")
                        .font(BumpFont.caption)
                        .foregroundStyle(BumpColor.secondaryText)
                    FlowLayout {
                        ForEach(engine.members) { member in
                            InterestChip(title: member.displayName)
                        }
                    }
                }
            } else {
                Text("Nobody else here yet. They need to open BUMP and join the same event code.")
                    .font(BumpFont.caption)
                    .foregroundStyle(BumpColor.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Button("Leave event") { engine.leaveRoom() }
                .buttonStyle(.bumpSecondary)
        }
    }

    private var readyState: some View {
        VStack(spacing: Space.l) {
            PhonesIllustration(animated: true)
                .frame(maxWidth: .infinity)

            Text("Bring your phones together")
                .font(BumpFont.screenTitle)
                .foregroundStyle(BumpColor.navy)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            Text("A gentle tap, back to back. BUMP is listening.")
                .font(BumpFont.body)
                .foregroundStyle(BumpColor.secondaryText)
                .multilineTextAlignment(.center)

            Button("Cancel") { engine.setReady(false) }
                .buttonStyle(.bumpSecondary)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Ready to bump. Bring your phones together.")
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
                    ForEach(engine.members) { member in
                        Button {
                            showManualPicker = false
                            engine.proposeManually(with: member)
                        } label: {
                            HStack(spacing: Space.m) {
                                Avatar(name: member.displayName, size: 40)
                                Text(member.displayName)
                                    .font(BumpFont.bodyEmphasis)
                                    .foregroundStyle(BumpColor.navy)
                                Spacer()
                            }
                            .padding(Space.m)
                            .background(RoundedRectangle(cornerRadius: Space.corner, style: .continuous)
                                .fill(BumpColor.surface))
                        }
                        .buttonStyle(.plain)
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
    }

    // MARK: Status card

    private func statusCard(title: String, body: String, tone: StatusTone, busy: Bool,
                            actions: [(String, () -> Void, Bool)]) -> some View {
        VStack(alignment: .leading, spacing: Space.m) {
            Card {
                VStack(alignment: .leading, spacing: Space.m) {
                    HStack(spacing: Space.s) {
                        if busy { ProgressView().tint(BumpColor.action) }
                        StatusPill(text: title, tone: tone)
                    }
                    Text(body)
                        .font(BumpFont.body)
                        .foregroundStyle(BumpColor.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            ForEach(Array(actions.enumerated()), id: \.offset) { _, action in
                Button(action.0, action: action.1)
                    .buttonStyle(action.2 ? AnyButtonStyleWrapper(.bumpPrimary) : AnyButtonStyleWrapper(.bumpSecondary))
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
