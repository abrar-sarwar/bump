import SwiftUI

/// The spoken interview and the card review that follows it.
struct VoiceOnboardingView: View {
    @ObservedObject var model: VoiceOnboardingModel
    var onSaved: () -> Void
    var onTypeInstead: () -> Void
    var onClose: () -> Void

    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        VStack(spacing: 0) {
            topBar
            switch model.phase {
            case .review, .saved:
                ReviewView(model: model)
            default:
                conversation
            }
        }
        .background(BumpColor.background.ignoresSafeArea())
        .onChange(of: model.phase) { _, phase in if phase == .saved { onSaved() } }
        .onChange(of: scenePhase) { _, phase in
            // Mic and playback never run in the background.
            if phase == .background { model.suspend() }
        }
        .onDisappear { model.stop() }
    }

    // MARK: Top bar

    private var topBar: some View {
        HStack {
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(BumpColor.navy)
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel("Close voice onboarding")
            Spacer()
            Wordmark()
            Spacer()
            Text(progressText)
                .font(BumpFont.caption.monospacedDigit())
                .foregroundStyle(BumpColor.secondaryText)
                .frame(width: 44)
                .accessibilityLabel(progressText.isEmpty ? "" : "Question \(model.questionsAsked) of \(VoiceOnboardingModel.maxQuestions)")
        }
        .padding(.horizontal, Space.s)
    }

    private var progressText: String {
        guard model.phase == .conversation else { return "" }
        return "\(min(model.questionsAsked, VoiceOnboardingModel.maxQuestions))/\(VoiceOnboardingModel.maxQuestions)"
    }

    // MARK: Conversation

    private var conversation: some View {
        VStack(spacing: 0) {
            VoiceIndicator(activity: model.activity, phase: model.phase, level: model.level)
                .padding(.vertical, Space.m)

            TranscriptView(lines: model.lines)

            if let notice = model.notice {
                NoticeText(text: notice).padding(.horizontal, Space.gutter).padding(.bottom, Space.s)
            }
            controls
        }
    }

    @ViewBuilder
    private var controls: some View {
        switch model.phase {
        case .micDenied:
            problem(title: "Microphone access is off",
                    body: "Turn it on in Settings to talk to Bump, or type your intro instead. It works the same.",
                    primary: ("Type instead", onTypeInstead),
                    secondary: ("Open Settings", {
                        if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                    }))
        case .failed(let message):
            problem(title: "Voice stopped", body: message,
                    primary: ("Try again", model.retry),
                    secondary: ("Type instead", onTypeInstead))
        case .building:
            BottomBar {
                WorkingCard(title: "Putting your card together…", detail: "Using only what you said.", onCancel: nil)
            }
        default:
            BottomBar {
                if model.tapToTalk {
                    HoldToTalkButton(holding: $model.holdingToTalk, onRelease: model.releaseTalk)
                        .disabled(model.phase != .conversation)
                }
                HStack(spacing: Space.s) {
                    ToggleChip(on: model.muted, onIcon: "mic.slash.fill", offIcon: "mic.fill",
                               label: model.muted ? "Unmute" : "Mute") { model.muted.toggle() }
                    ToggleChip(on: model.tapToTalk, onIcon: "hand.tap.fill", offIcon: "hand.tap",
                               label: "Tap to talk") { model.tapToTalk.toggle(); model.holdingToTalk = false }
                    if model.activity == .speaking {
                        ToggleChip(on: false, onIcon: "stop.fill", offIcon: "stop.fill", label: "Stop") { model.interrupt() }
                    }
                }
                Button("I'm done", action: model.done)
                    .buttonStyle(.bumpPrimary)
                    .disabled(model.phase != .conversation)
                Button("Type instead", action: onTypeInstead)
                    .font(BumpFont.caption.weight(.semibold))
                    .foregroundStyle(BumpColor.secondaryText)
                    .padding(.top, Space.xs)
            }
        }
    }

    private func problem(title: String, body: String,
                         primary: (String, () -> Void), secondary: (String, () -> Void)) -> some View {
        BottomBar {
            VStack(alignment: .leading, spacing: Space.xs) {
                Text(title).font(BumpFont.bodyEmphasis).foregroundStyle(BumpColor.navy)
                Text(body).font(BumpFont.caption).foregroundStyle(BumpColor.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.bottom, Space.s)
            Button(primary.0, action: primary.1).buttonStyle(.bumpPrimary)
            Button(secondary.0, action: secondary.1).buttonStyle(.bumpSecondary)
        }
    }
}

// MARK: - Review

private struct ReviewView: View {
    @ObservedObject var model: VoiceOnboardingModel
    @ObservedObject private var onboarding: OnboardingModel
    @State private var showTranscript = false

    init(model: VoiceOnboardingModel) {
        self.model = model
        self.onboarding = model.onboarding
    }

    var body: some View {
        Screen {
            VStack(alignment: .leading, spacing: Space.l) {
                VStack(alignment: .leading, spacing: Space.s) {
                    Text("Does this sound right?")
                        .font(BumpFont.screenTitle)
                        .foregroundStyle(BumpColor.navy)
                    Text("Say yes, tell Bump what to change, or edit the card yourself. Nothing is saved until you confirm.")
                        .font(BumpFont.body)
                        .foregroundStyle(BumpColor.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let notice = model.notice { NoticeText(text: notice) }

                BumpCardEditor(model: onboarding)

                DisclosureGroup(isExpanded: $showTranscript) {
                    VStack(alignment: .leading, spacing: Space.s) {
                        ForEach(model.lines) { TranscriptRow(line: $0) }
                    }
                    .padding(.top, Space.s)
                } label: {
                    Text("What Bump heard")
                        .font(BumpFont.bodyEmphasis)
                        .foregroundStyle(BumpColor.navy)
                }
                .tint(BumpColor.action)
            }
        }
        .safeAreaInset(edge: .bottom) {
            BottomBar {
                HStack(spacing: Space.s) {
                    VoiceDot(activity: model.activity)
                    Text(listeningHint)
                        .font(BumpFont.caption)
                        .foregroundStyle(BumpColor.secondaryText)
                    Spacer()
                    ToggleChip(on: model.muted, onIcon: "mic.slash.fill", offIcon: "mic.fill",
                               label: model.muted ? "Unmute" : "Mute") { model.muted.toggle() }
                }
                Button("Looks right, save my card") { model.confirm() }
                    .buttonStyle(.bumpPrimary)
                    .disabled(!onboarding.canFinish)
            }
        }
    }

    private var listeningHint: String {
        if model.muted { return "Mic off. Edit the card or tap save." }
        switch model.activity {
        case .speaking: return "Bump is reading your card…"
        case .thinking: return "Updating your card…"
        default: return "Listening. Say \u{201C}yes\u{201D} or what to change."
        }
    }
}

// MARK: - Transcript

/// Both sides of the conversation. Follows the newest turn, unless you've
/// scrolled up to read, in which case a "Latest" button appears instead.
struct TranscriptView: View {
    let lines: [VoiceOnboardingModel.Line]
    @State private var atBottom = true

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: Space.m) {
                    ForEach(lines) { TranscriptRow(line: $0) }
                    Color.clear.frame(height: 1).id("bottom")
                        .onAppear { atBottom = true }
                        .onDisappear { atBottom = false }
                }
                .padding(.horizontal, Space.gutter)
                .padding(.bottom, Space.m)
            }
            .overlay(alignment: .bottom) {
                if !atBottom && !lines.isEmpty {
                    Button {
                        withAnimation { proxy.scrollTo("bottom", anchor: .bottom) }
                    } label: {
                        Label("Latest", systemImage: "arrow.down")
                            .font(BumpFont.caption.weight(.semibold))
                            .padding(.horizontal, Space.m).padding(.vertical, Space.s)
                            .background(Capsule().fill(BumpColor.surface))
                            .foregroundStyle(BumpColor.action)
                    }
                    .padding(.bottom, Space.s)
                }
            }
            .onChange(of: lines) { _, _ in
                // Only follow along if the reader is already at the end.
                if atBottom { proxy.scrollTo("bottom", anchor: .bottom) }
            }
        }
    }
}

struct TranscriptRow: View {
    let line: VoiceOnboardingModel.Line

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(line.speaker == .you ? "You" : "Bump")
                .font(BumpFont.caption.weight(.semibold))
                .foregroundStyle(line.speaker == .you ? BumpColor.navy : BumpColor.action)
            Text(line.text.isEmpty ? "…" : line.text)
                .font(BumpFont.body)
                .foregroundStyle(line.isFinal ? BumpColor.navy : BumpColor.secondaryText)
                .italic(!line.isFinal && line.speaker == .you)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Voice indicator

private struct VoiceIndicator: View {
    let activity: VoiceOnboardingModel.Activity
    let phase: VoiceOnboardingModel.Phase
    let level: Float
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: Space.s) {
            ZStack {
                Circle()
                    .fill(tint.opacity(0.18))
                    .frame(width: 84, height: 84)
                    .scaleEffect(reduceMotion ? 1 : 1 + CGFloat(activity == .listening ? level : 0) * 0.5)
                    .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: level)
                Circle()
                    .fill(tint)
                    .frame(width: 56, height: 56)
                Image(systemName: icon)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(.white)
            }
            Text(label)
                .font(BumpFont.bodyEmphasis)
                .foregroundStyle(BumpColor.navy)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
    }

    private var label: String {
        switch phase {
        case .connecting: return "Connecting…"
        case .building: return "Thinking…"
        case .micDenied: return "Microphone off"
        case .failed: return "Stopped"
        default: break
        }
        switch activity {
        case .idle: return "Getting ready…"
        case .listening: return "Listening"
        case .thinking: return "Thinking…"
        case .speaking: return "Speaking"
        }
    }

    private var icon: String {
        switch activity {
        case .speaking: return "waveform"
        case .thinking: return "ellipsis"
        default: return phase == .micDenied ? "mic.slash.fill" : "mic.fill"
        }
    }

    private var tint: Color {
        switch phase {
        case .failed, .micDenied: return BumpColor.secondaryText
        default: return activity == .speaking ? BumpColor.brand : BumpColor.action
        }
    }
}

private struct VoiceDot: View {
    let activity: VoiceOnboardingModel.Activity
    var body: some View {
        Circle()
            .fill(activity == .listening ? BumpColor.positive : BumpColor.action)
            .frame(width: 10, height: 10)
            .accessibilityHidden(true)
    }
}

// MARK: - Controls

private struct ToggleChip: View {
    let on: Bool
    let onIcon: String
    let offIcon: String
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(label, systemImage: on ? onIcon : offIcon)
                .font(BumpFont.caption.weight(.semibold))
                .padding(.horizontal, Space.m).padding(.vertical, Space.s)
                .background(Capsule().fill(on ? BumpColor.action : BumpColor.paleBlue))
                .foregroundStyle(on ? .white : BumpColor.navy)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}

/// Press and hold to talk; release to send. For noisy rooms.
private struct HoldToTalkButton: View {
    @Binding var holding: Bool
    var onRelease: () -> Void

    var body: some View {
        Text(holding ? "Listening… release to send" : "Hold to talk")
            .font(BumpFont.button)
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 18)
            .background(RoundedRectangle(cornerRadius: Space.corner, style: .continuous)
                .fill(holding ? BumpColor.positive : BumpColor.action))
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { _ in if !holding { holding = true } }
                .onEnded { _ in onRelease() })
            .accessibilityLabel("Hold to talk")
            .accessibilityAddTraits(.isButton)
    }
}

// MARK: - Previews (SAMPLE DATA, not a real person)

#if DEBUG
#Preview("Conversation") {
    let store = Store(inMemory: true)
    let voice = VoiceOnboardingModel(onboarding: OnboardingModel(store: store), backend: { nil })
    voice.seedSample(phase: .conversation, activity: .speaking, lines: [
        .init(id: "1", speaker: .bump, text: "Tell me a little about yourself. What do you enjoy doing?", isFinal: true),
        .init(id: "2", speaker: .you, text: "I study cybersecurity, play games, and go to concerts.", isFinal: true),
        .init(id: "3", speaker: .bump, text: "Nice mix. What games or artists have you been into lately?", isFinal: false),
    ], questions: 2, elapsed: 30)
    return VoiceOnboardingView(model: voice, onSaved: {}, onTypeInstead: {}, onClose: {})
}
#endif
