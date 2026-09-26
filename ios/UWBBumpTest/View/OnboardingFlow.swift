import SwiftUI

/// First-run onboarding: name → spoken intro → a few follow-ups → your card.
/// All state lives in `OnboardingModel`, so moving back and forth never loses
/// an answer or an edit.
struct OnboardingFlow: View {
    @StateObject private var model: OnboardingModel
    var onFinished: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var movingForward = true

    init(store: Store, model: OnboardingModel? = nil, onFinished: @escaping () -> Void) {
        _model = StateObject(wrappedValue: model ?? OnboardingModel(store: store))
        self.onFinished = onFinished
    }

    var body: some View {
        VStack(spacing: 0) {
            topBar
            ZStack {
                switch model.step {
                case .name: NameStep(model: model).transition(transition)
                case .intro: IntroStep(model: model).transition(transition)
                case .questions: QuestionsStep(model: model).transition(transition)
                case .card: CardStep(model: model, onFinished: finish).transition(transition)
                }
            }
            .animation(reduceMotion ? .easeInOut(duration: 0.2) : .easeInOut(duration: 0.28), value: model.step)
        }
        .background(BumpColor.background.ignoresSafeArea())
        .onChange(of: model.step) { old, new in movingForward = new > old }
        .onDisappear { model.tearDown() }
    }

    private var transition: AnyTransition {
        if reduceMotion { return .opacity }
        let edge: Edge = movingForward ? .trailing : .leading
        return .asymmetric(insertion: .move(edge: edge).combined(with: .opacity),
                           removal: .opacity)
    }

    /// The site's square back button, then the step progress.
    private var topBar: some View {
        HStack(spacing: Space.m) {
            SquareIconButton(systemImage: "arrow.left", label: "Back") {
                movingForward = false
                model.goBack()
            }
            .opacity(model.step == .name ? 0 : 1)
            .disabled(model.step == .name)

            SegmentedProgress(current: model.step.rawValue, total: OnboardingModel.Step.allCases.count)
        }
        .padding(.horizontal, Space.gutter)
        .padding(.vertical, Space.s)
    }

    private func finish() {
        guard model.finish() else { return }
        Haptics.success()
        onFinished()
    }
}

// MARK: - Step indicator (tutorial page dots)

struct StepIndicator: View {
    let current: Int
    let total: Int

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<total, id: \.self) { i in
                Capsule()
                    .fill(i <= current ? BumpColor.primary : BumpColor.track)
                    .frame(width: i == current ? 22 : 7, height: 7)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: current)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Step \(current + 1) of \(total)")
    }
}

/// Eyebrow + title + subtitle, left aligned.
private struct StepHeader: View {
    let eyebrow: String
    let title: String
    var subtitle: String?

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            Eyebrow(eyebrow)
            ScreenTitle(title)
            if let subtitle {
                Text(subtitle)
                    .font(BumpFont.body)
                    .foregroundStyle(BumpColor.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - 1. Name

private struct NameStep: View {
    @ObservedObject var model: OnboardingModel
    @FocusState private var focused: Bool

    var body: some View {
        Screen(backdrop: .soft) {
            VStack(alignment: .leading, spacing: Space.l) {
                VStack(alignment: .leading, spacing: Space.m) {
                    Wordmark()
                    StepHeader(eyebrow: "Step 1 of 4", title: "What should we call you?",
                               subtitle: "This is the name people see after you bump.")
                }
                BumpField(label: "Your name", placeholder: "First name is fine", text: $model.name)
                    .focused($focused)
                    .submitLabel(.next)
                    .onSubmit(model.continueFromName)
                    .textContentType(.givenName)
                // A live preview of how you'll appear to the person you bump.
                if !model.name.trimmed().isEmpty {
                    RowPill {
                        Avatar(name: model.name, size: 44)
                    } content: {
                        RowText.title(model.name)
                    }
                    .accessibilityHidden(true)
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            BottomBar {
                Button(action: model.continueFromName) {
                    TrailingIconLabel("Continue", systemImage: "arrow.right")
                }
                .buttonStyle(.bumpPrimary)
                .disabled(!model.canContinueFromName)
            }
        }
        .onAppear { focused = model.name.isEmpty }
    }
}

// MARK: - 2. Intro

private struct IntroStep: View {
    @ObservedObject var model: OnboardingModel
    @ObservedObject private var recorder: IntroRecorder
    @FocusState private var focused: Bool

    init(model: OnboardingModel) {
        self.model = model
        self.recorder = model.recorder
    }

    var body: some View {
        Screen {
            VStack(alignment: .leading, spacing: Space.l) {
                StepHeader(eyebrow: "Step 2 of 4", title: "Introduce yourself",
                           subtitle: "Say what you're into, what you've done, and what you're hoping to find. We'll turn it into a card you can edit.")

                if model.cloud == .undecided {
                    CloudConsentCard(model: model)
                } else if model.busy == .drafting {
                    WorkingCard(title: "Drafting your profile…",
                                detail: model.cloudAllowed ? "Grok is reading your intro." : nil,
                                onCancel: model.cancelUpload)
                } else if !model.transcript.isEmpty && model.transcriptFromVoice && !model.typing {
                    transcriptReview
                } else if model.typing || !model.cloudAllowed {
                    typingPanel
                } else {
                    voicePanel
                }

                if let notice = model.notice {
                    NoticeText(text: notice)
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            if model.cloud != .undecided && model.busy == .idle {
                BottomBar {
                    if showDraftButton {
                        Button(action: model.draftProfile) {
                            TrailingIconLabel("Draft my profile", systemImage: "arrow.right")
                        }
                        .buttonStyle(.bumpPrimary)
                        .disabled(!model.canDraft)
                    }
                    Button("Skip, I'll pick interests myself", action: model.skipIntro)
                        .font(BumpFont.captionEmphasis)
                        .foregroundStyle(BumpColor.secondaryText)
                        .padding(.top, Space.xs)
                }
            }
        }
        .onChange(of: model.typing) { _, typing in if typing { focused = true } }
    }

    private var showDraftButton: Bool {
        model.typing || !model.cloudAllowed || (!model.transcript.isEmpty && model.transcriptFromVoice)
    }

    // Voice

    @ViewBuilder
    private var voicePanel: some View {
        switch model.busy {
        case .uploading:
            WorkingCard(title: "Uploading…", detail: "Sending your recording to the BUMP server.",
                        onCancel: model.cancelUpload)
        case .transcribing:
            WorkingCard(title: "Transcribing…", detail: "Turning your recording into text.",
                        onCancel: model.cancelUpload)
        default:
            recorderPanel
        }
    }

    @ViewBuilder
    private var recorderPanel: some View {
        VStack(spacing: Space.m) {
            switch recorder.state {
            case .idle:
                RecordButton(recording: false) { recorder.start() }
                Text("Tap to record · up to 45 seconds")
                    .font(BumpFont.caption)
                    .foregroundStyle(BumpColor.secondaryText)

            case .requestingPermission:
                ProgressView("Asking for microphone access…")
                    .tint(BumpColor.primary)
                    .foregroundStyle(BumpColor.secondaryText)
                    .padding(.vertical, Space.l)

            case .denied:
                Bento(wash: .peach, label: "Microphone access is off", systemImage: "mic.slash.fill") {
                    Text("Turn it on in Settings to record, or type your intro instead. It works the same.")
                        .font(BumpFont.body).foregroundStyle(BumpColor.navy)
                        .fixedSize(horizontal: false, vertical: true)
                    Button("Open Settings") {
                        if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                    }
                    .buttonStyle(.bumpSecondary)
                }

            case .recording:
                RecordButton(recording: true) { recorder.stop() }
                LevelMeter(level: recorder.level)
                Text("\(Self.clock(recorder.remaining)) left")
                    .font(BumpFont.bodyEmphasis.monospacedDigit())
                    .foregroundStyle(BumpColor.navy)
                    .accessibilityLabel("\(Int(recorder.remaining)) seconds left")

            case .finished(let duration, let interrupted):
                Card {
                    VStack(alignment: .leading, spacing: Space.s) {
                        Text("Recorded \(Self.clock(duration))")
                            .font(BumpFont.bodyEmphasis).foregroundStyle(BumpColor.navy)
                        if interrupted {
                            Text("Recording stopped because of an interruption. You can use what you have or record again.")
                                .font(BumpFont.caption).foregroundStyle(BumpColor.secondaryText)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        if let error = model.error {
                            Text(error).font(BumpFont.caption).foregroundStyle(BumpColor.negative)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Button(model.error == nil ? "Use this recording" : "Try again", action: model.useRecording)
                            .buttonStyle(.bumpPrimary)
                        Button("Record again", action: model.recordAgain)
                            .buttonStyle(.bumpSecondary)
                    }
                }

            case .failed(let message):
                Bento(wash: .peach) {
                    Text(message).font(BumpFont.body).foregroundStyle(BumpColor.navy)
                        .fixedSize(horizontal: false, vertical: true)
                    Button("Record again", action: model.recordAgain)
                        .buttonStyle(.bumpSecondary)
                }
            }

            if recorder.state != .recording {
                Button("Type instead") { recorder.discard(); model.typing = true }
                    .font(BumpFont.bodyEmphasis)
                    .foregroundStyle(BumpColor.primary)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var transcriptReview: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            SectionHeading(title: "Here's what we heard",
                           subtitle: "Fix anything that's off before we draft your card. This text isn't saved or shared.")
            BumpField(label: "", placeholder: "", axis: .vertical, lines: 4...12, text: $model.transcript)
                .focused($focused)
            HStack {
                Text("Transcribed by xAI speech-to-text")
                    .font(BumpFont.caption2).foregroundStyle(BumpColor.faint)
                Spacer()
                Button("Record again", action: model.recordAgain)
                    .font(BumpFont.captionEmphasis)
                    .foregroundStyle(BumpColor.primary)
            }
            .padding(.horizontal, Space.xs)
        }
    }

    private var typingPanel: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            BumpField(label: "Your intro",
                      placeholder: "I'm into…  I've been…  I'm hoping to…",
                      axis: .vertical, lines: 4...12, text: $model.transcript)
                .focused($focused)
            HStack {
                Text(model.cloudAllowed ? "Grok will suggest a card from this." : "Stays on this phone. Your phone suggests a card from this.")
                    .font(BumpFont.caption2).foregroundStyle(BumpColor.faint)
                Spacer()
                if model.cloudAllowed {
                    Button("Record instead") { model.typing = false; focused = false }
                        .font(BumpFont.captionEmphasis)
                        .foregroundStyle(BumpColor.primary)
                }
            }
            .padding(.horizontal, Space.xs)
        }
    }

    static func clock(_ t: TimeInterval) -> String {
        let s = max(0, Int(t.rounded()))
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}

// MARK: - Consent

private struct CloudConsentCard: View {
    @ObservedObject var model: OnboardingModel

    var body: some View {
        Bento(wash: .lilac, label: "Before anything leaves your phone", systemImage: "lock.fill") {
            Text("To transcribe your intro and suggest a card, BUMP sends your recording, anything you type here, and your answers to the BUMP server, which passes them to xAI's Grok.")
                .font(BumpFont.body).foregroundStyle(BumpColor.navy)
                .fixedSize(horizontal: false, vertical: true)
            Text("The BUMP server doesn't store your audio or text. xAI's documentation says API requests are kept for up to 30 days for auditing. Later, if you and the person you bump both allow it, your shared interests are sent the same way to write talking points.")
                .font(BumpFont.caption).foregroundStyle(BumpColor.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            VStack(spacing: Space.s) {
                Button("Allow cloud processing") { model.chooseCloud(true) }
                    .buttonStyle(.bumpPrimary)
                Button("Keep everything on this phone") { model.chooseCloud(false) }
                    .buttonStyle(.bumpSecondary)
            }
            .padding(.top, Space.xs)
            Text("On this phone you type instead of speak. You can change this any time in You.")
                .font(BumpFont.caption).foregroundStyle(BumpColor.secondaryText)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - 3. Questions (as a chat: Grok's questions are "them", answers are "me")

private struct QuestionsStep: View {
    @ObservedObject var model: OnboardingModel
    @FocusState private var focused: Bool

    var body: some View {
        Screen {
            VStack(alignment: .leading, spacing: Space.l) {
                StepHeader(eyebrow: "Step 3 of 4", title: "A little more",
                           subtitle: "Up to three quick questions. Skip anything.")

                if !model.answered.isEmpty {
                    VStack(spacing: Space.s) {
                        ForEach(model.answered) { qa in
                            ChatBubble(qa.question.text, who: Self.origin(qa.question.origin == .grok))
                            if let answer = qa.answer {
                                ChatBubble(answer, isMe: true)
                            } else {
                                Text("Skipped")
                                    .font(BumpFont.caption2).foregroundStyle(BumpColor.faint)
                                    .frame(maxWidth: .infinity, alignment: .trailing)
                                    .padding(.horizontal, 6)
                            }
                        }
                    }
                    .accessibilityElement(children: .combine)
                }

                if model.busy == .thinking {
                    WorkingCard(title: "Thinking of a good question…", detail: nil, onCancel: model.finishQuestions)
                } else if let question = model.current {
                    VStack(alignment: .leading, spacing: Space.s) {
                        Eyebrow("Question \(model.questionNumber) of up to \(OnboardingModel.maxQuestions)")
                            .frame(maxWidth: .infinity)
                        ChatBubble(who: Self.origin(question.origin == .grok)) {
                            Text(question.text).font(BumpFont.bodyEmphasis)
                        }
                        .id(question.text)
                        .transition(.opacity)
                        BumpField(label: "Your answer", placeholder: "A sentence is plenty",
                                  axis: .vertical, lines: 2...6, text: $model.answer)
                            .focused($focused)
                    }
                }

                if model.busy == .idle && model.current == nil {
                    Card {
                        VStack(alignment: .leading, spacing: Space.s) {
                            Text("That's everything we wanted to ask.")
                                .font(BumpFont.bodyEmphasis).foregroundStyle(BumpColor.navy)
                            Button(action: model.finishQuestions) {
                                TrailingIconLabel("See your card", systemImage: "arrow.right")
                            }
                            .buttonStyle(.bumpPrimary)
                        }
                    }
                }

                if let notice = model.notice {
                    NoticeText(text: notice)
                }
            }
            .animation(.easeInOut(duration: 0.2), value: model.current)
        }
        .safeAreaInset(edge: .bottom) {
            if model.busy == .idle && model.current != nil {
                BottomBar {
                    Button { model.submitAnswer() } label: {
                        TrailingIconLabel("Next", systemImage: "arrow.right")
                    }
                    .buttonStyle(.bumpPrimary)
                    .disabled(model.answer.trimmed().isEmpty)
                    HStack {
                        Button("Skip question", action: model.skipQuestion)
                        Spacer()
                        Button("Done with questions", action: model.finishQuestions)
                    }
                    .font(BumpFont.captionEmphasis)
                    .foregroundStyle(BumpColor.secondaryText)
                    .padding(.top, Space.xs)
                }
            }
        }
        .onAppear { focused = true }
        .onChange(of: model.current) { _, q in if q != nil { focused = true } }
    }

    private static func origin(_ fromGrok: Bool) -> String {
        fromGrok ? "Question from Grok" : "Question from your phone"
    }
}

// MARK: - 4. Card

private struct CardStep: View {
    @ObservedObject var model: OnboardingModel
    var onFinished: () -> Void

    @State private var editing: OnboardingModel.Item?
    @State private var editText = ""
    @State private var adding: ProfileFact.Kind?
    @State private var addText = ""
    @State private var browsing = false

    var body: some View {
        Screen {
            VStack(alignment: .leading, spacing: Space.l) {
                StepHeader(eyebrow: "Step 4 of 4", title: "Your Bump card",
                           subtitle: "Confirmed partners receive this card. Keep what's right, fix what isn't, and uncheck anything you'd rather not share.")

                if let notice = model.notice { NoticeText(text: notice) }

                Card(padding: 22) {
                    VStack(alignment: .leading, spacing: Space.m) {
                        HStack(alignment: .top, spacing: Space.m) {
                            PhotoPickerAvatar(photo: $model.photo, name: model.name, size: 64)
                            BumpField(label: "Name", placeholder: "Your name", text: $model.name)
                        }
                        BumpField(label: "Short bio (optional)", placeholder: "One line about you",
                                  axis: .vertical, lines: 1...4, text: Binding(get: { model.bio },
                                                                 set: { model.bio = $0; model.bioEdited() }))
                        if model.bioOrigin == .grok {
                            Text("Suggested by Grok from your intro. Edit freely.")
                                .font(BumpFont.caption2).foregroundStyle(BumpColor.faint)
                        }
                    }
                }

                ForEach(ProfileFact.Kind.allCases, id: \.self) { kind in
                    section(kind)
                }

                Text("Only your name, photo, bio and the checked items are shared, and only with someone you've both confirmed after a bump. Your recording, transcript and answers are never saved or shared.")
                    .font(BumpFont.caption)
                    .foregroundStyle(BumpColor.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .safeAreaInset(edge: .bottom) {
            BottomBar {
                Button(action: onFinished) {
                    TrailingIconLabel("Start bumping", systemImage: "iphone.radiowaves.left.and.right")
                }
                .buttonStyle(.bumpPrimary)
                .disabled(!model.canFinish)
                if !model.canFinish {
                    Text("Add your name and check at least one thing to continue.")
                        .font(BumpFont.caption)
                        .foregroundStyle(BumpColor.secondaryText)
                        .multilineTextAlignment(.center)
                }
            }
        }
        .alert("Edit", isPresented: Binding(get: { editing != nil }, set: { if !$0 { editing = nil } })) {
            TextField("Text", text: $editText)
            Button("Save") { if let e = editing { model.rename(e.id, to: editText) }; editing = nil }
            Button("Cancel", role: .cancel) { editing = nil }
        }
        .alert(addTitle, isPresented: Binding(get: { adding != nil }, set: { if !$0 { adding = nil } })) {
            TextField(addPlaceholder, text: $addText)
            Button("Add") { if let k = adding { model.add(k, addText) }; adding = nil }
            Button("Cancel", role: .cancel) { adding = nil }
        }
    }

    private var addTitle: String {
        switch adding {
        case .interest: return "Add an interest"
        case .experience: return "Add an experience"
        case .goal: return "Add a goal"
        case nil: return ""
        }
    }

    private var addPlaceholder: String {
        switch adding {
        case .interest: return "e.g. Bouldering"
        case .experience: return "e.g. Built a weather station"
        case .goal: return "e.g. Find a climbing partner"
        case nil: return ""
        }
    }

    private func section(_ kind: ProfileFact.Kind) -> some View {
        VStack(alignment: .leading, spacing: Space.s) {
            HStack {
                Text(kind.title)
                    .font(BumpFont.sectionTitle)
                    .foregroundStyle(BumpColor.navy)
                Spacer()
                Button {
                    addText = ""
                    adding = kind
                } label: {
                    Label("Add", systemImage: "plus")
                        .font(BumpFont.captionEmphasis)
                        .foregroundStyle(BumpColor.primary)
                }
                .accessibilityLabel("Add \(kind.title.lowercased())")
            }
            .padding(.horizontal, Space.xs)

            let items = model.items(kind)
            if items.isEmpty {
                Text(emptyText(kind))
                    .font(BumpFont.caption)
                    .foregroundStyle(BumpColor.secondaryText)
                    .padding(.horizontal, Space.xs)
            } else {
                VStack(spacing: Space.s) {
                    ForEach(items) { item in row(item) }
                }
            }

            if kind == .interest {
                DisclosureGroup(isExpanded: $browsing) {
                    TopicBrowser(isSelected: model.isSelected, toggle: model.toggleCatalog)
                        .padding(.top, Space.s)
                } label: {
                    Text("Browse interests")
                        .font(BumpFont.captionEmphasis)
                        .foregroundStyle(BumpColor.primary)
                }
                .tint(BumpColor.primary)
                .padding(.horizontal, Space.xs)
            }
        }
    }

    private func row(_ item: OnboardingModel.Item) -> some View {
        RowPill(block: true) {
            Button { model.toggle(item.id) } label: {
                BumpCheckbox(checked: item.included)
            }
            .buttonStyle(.plain)
            .padding(-8)
            .accessibilityLabel(item.included ? "Shared: \(item.text)" : "Not shared: \(item.text)")
            .accessibilityHint("Double-tap to \(item.included ? "stop sharing" : "share") this")
        } content: {
            Text(item.text)
                .font(BumpFont.bodyEmphasis)
                .foregroundStyle(item.included ? BumpColor.navy : BumpColor.secondaryText)
                .strikethrough(!item.included, color: BumpColor.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            if let evidence = item.evidence {
                Text("From “\(evidence)”")
                    .font(BumpFont.caption)
                    .foregroundStyle(BumpColor.secondaryText)
                    .lineLimit(2)
            }
            RowText.faint(item.origin.label)
        } trail: {
            Menu {
                Button("Edit") { editText = item.text; editing = item }
                Button("Remove", role: .destructive) { model.remove(item.id) }
            } label: {
                Image(systemName: "ellipsis")
                    .foregroundStyle(BumpColor.secondaryText)
                    .frame(width: 32, height: 32)
            }
            .accessibilityLabel("More for \(item.text)")
        }
    }

    private func emptyText(_ kind: ProfileFact.Kind) -> String {
        switch kind {
        case .interest: return "Nothing yet. Add your own or browse below."
        case .experience: return "Anything you've done, built, studied or worked on."
        case .goal: return "What you're hoping to find or do. Optional."
        }
    }
}

// MARK: - Shared bits

private struct BottomBar<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        VStack(spacing: Space.xs) { content }
            .padding(.horizontal, Space.gutter)
            .padding(.top, Space.m)
            .padding(.bottom, Space.s)
            .background(
                LinearGradient(colors: [BumpColor.background.opacity(0), BumpColor.background],
                               startPoint: .top, endPoint: .init(x: 0.5, y: 0.3))
                    .ignoresSafeArea(edges: .bottom)
            )
    }
}

/// A busy state, as the site's notification toast with a spinner.
private struct WorkingCard: View {
    let title: String
    let detail: String?
    var onCancel: (() -> Void)?

    var body: some View {
        VStack(spacing: Space.m) {
            Toast(systemImage: "waveform", title: title, message: detail) {
                ProgressView().tint(BumpColor.primary)
            }
            if let onCancel {
                Button("Cancel", action: onCancel)
                    .font(BumpFont.captionEmphasis)
                    .foregroundStyle(BumpColor.primary)
            }
        }
    }
}

/// A warning line on a peach wash.
private struct NoticeText: View {
    let text: String
    var body: some View {
        HStack(alignment: .top, spacing: Space.s) {
            Image(systemName: "info.circle.fill").foregroundStyle(BumpColor.warning)
            Text(text).font(BumpFont.caption).foregroundStyle(BumpColor.navy)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Space.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Wash.peach.background.clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous)))
    }
}

/// Idle: a large glossy orb with a mic. Recording: the red morphing blob.
private struct RecordButton: View {
    let recording: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            if recording {
                MorphingBlob(size: 180, loop: 6, container: BumpColor.errorContainer, form: BumpColor.error) { _ in
                    Image(systemName: "stop.fill")
                        .font(.system(size: 34, weight: .semibold))
                        .foregroundStyle(Color.white)
                }
            } else {
                ZStack {
                    PulseRings(active: false)
                    IconOrb(systemImage: "mic.fill", size: 116, tint: BumpColor.primary)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(recording ? "Stop recording" : "Start recording")
        .padding(.top, Space.m)
    }
}

private struct LevelMeter: View {
    let level: Float
    var body: some View {
        GeometryReader { geo in
            Capsule().fill(BumpColor.track)
                .overlay(alignment: .leading) {
                    Capsule().fill(BumpColor.error)
                        .frame(width: max(8, geo.size.width * CGFloat(level)))
                        .animation(.linear(duration: 0.1), value: level)
                }
        }
        .frame(width: 180, height: 5)
        .accessibilityHidden(true)
    }
}

// MARK: - Previews (SAMPLE DATA — not real people)

#if DEBUG
#Preview("1 · Name") {
    OnboardingFlow(store: Store(inMemory: true), onFinished: {})
}

#Preview("2 · Intro, consent") {
    let store = Store(inMemory: true)
    let model = OnboardingModel(store: store)
    model.name = "Sam (sample)"
    model.step = .intro
    return OnboardingFlow(store: store, model: model, onFinished: {})
}

#Preview("2 · Intro, transcript") {
    OnboardingFlow(store: PreviewFixtures.onboardingStore(), model: PreviewFixtures.onboarding(.intro), onFinished: {})
}

#Preview("3 · Question") {
    OnboardingFlow(store: PreviewFixtures.onboardingStore(), model: PreviewFixtures.onboarding(.questions), onFinished: {})
}

#Preview("4 · Card") {
    OnboardingFlow(store: PreviewFixtures.onboardingStore(), model: PreviewFixtures.onboarding(.card), onFinished: {})
}
#endif
