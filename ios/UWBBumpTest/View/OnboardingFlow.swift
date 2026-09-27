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
            .animation(reduceMotion ? .easeInOut(duration: 0.2) : Motion.spatial, value: model.step)
        }
        .background(BumpColor.surface.ignoresSafeArea())
        .onChange(of: model.step) { old, new in movingForward = new > old }
        .onDisappear { model.tearDown() }
    }

    private var transition: AnyTransition {
        if reduceMotion { return .opacity }
        let edge: Edge = movingForward ? .trailing : .leading
        return .asymmetric(insertion: .move(edge: edge).combined(with: .opacity),
                           removal: .opacity)
    }

    private var topBar: some View {
        HStack {
            Button {
                movingForward = false
                model.goBack()
            } label: {
                Image(systemName: "arrow.left")
            }
            .buttonStyle(.bumpIcon(BumpColor.onSurface))
            .opacity(model.step == .name ? 0 : 1)
            .disabled(model.step == .name)
            .accessibilityLabel("Back")

            Spacer()
            StepIndicator(current: model.step.rawValue, total: OnboardingModel.Step.allCases.count)
            Spacer()
            Color.clear.frame(width: 44, height: 44)
        }
        .padding(.horizontal, Space.s)
    }

    private func finish() {
        guard model.finish() else { return }
        Haptics.success()
        onFinished()
    }
}

// MARK: - Step indicator

struct StepIndicator: View {
    let current: Int
    let total: Int

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<total, id: \.self) { i in
                Capsule()
                    .fill(i <= current ? BumpColor.primary : BumpColor.surfaceContainerHighest)
                    .frame(width: i == current ? 28 : 8, height: 8)
            }
        }
        .animation(reduceMotion ? nil : Motion.spatial, value: current)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Step \(current + 1) of \(total)")
    }
}

// MARK: - 1. Name

private struct NameStep: View {
    @ObservedObject var model: OnboardingModel
    @FocusState private var focused: Bool

    var body: some View {
        Screen {
            VStack(alignment: .leading, spacing: Space.l) {
                Wordmark()
                Text("What should we call you?")
                    .font(BumpFont.headlineLarge)
                    .foregroundStyle(BumpColor.onSurface)
                    .fixedSize(horizontal: false, vertical: true)
                Text("This is the name people see after you bump.")
                    .font(BumpFont.bodyLarge)
                    .foregroundStyle(BumpColor.onSurfaceVariant)
                BumpField(label: "Your name", placeholder: "First name is fine", text: $model.name)
                    .focused($focused)
                    .submitLabel(.next)
                    .onSubmit(model.continueFromName)
                    .textContentType(.givenName)
            }
        }
        .safeAreaInset(edge: .bottom) {
            BottomBar {
                Button("Continue", action: model.continueFromName)
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
                VStack(alignment: .leading, spacing: Space.s) {
                    Text("Introduce yourself")
                        .font(BumpFont.headlineLarge)
                        .foregroundStyle(BumpColor.onSurface)
                    Text("Say what you're into, what you've done, and what you're hoping to find. We'll turn it into a card you can edit.")
                        .font(BumpFont.bodyLarge)
                        .foregroundStyle(BumpColor.onSurfaceVariant)
                        .fixedSize(horizontal: false, vertical: true)
                }

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
                        Button("Draft my profile", action: model.draftProfile)
                            .buttonStyle(.bumpPrimary)
                            .disabled(!model.canDraft)
                    }
                    Button("Skip, I'll pick interests myself", action: model.skipIntro)
                        .buttonStyle(.bumpText(BumpColor.onSurfaceVariant))
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
                    .font(BumpFont.bodySmall)
                    .foregroundStyle(BumpColor.onSurfaceVariant)

            case .requestingPermission:
                ProgressView("Asking for microphone access…")
                    .foregroundStyle(BumpColor.onSurfaceVariant)
                    .padding(.vertical, Space.l)

            case .denied:
                Card {
                    VStack(alignment: .leading, spacing: Space.s) {
                        Text("Microphone access is off")
                            .font(BumpFont.titleMedium).foregroundStyle(BumpColor.onSurface)
                        Text("Turn it on in Settings to record, or type your intro instead. It works the same.")
                            .font(BumpFont.bodySmall).foregroundStyle(BumpColor.onSurfaceVariant)
                            .fixedSize(horizontal: false, vertical: true)
                        Button("Open Settings") {
                            if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                        }
                        .buttonStyle(.bumpSecondary)
                    }
                }

            case .recording:
                RecordButton(recording: true) { recorder.stop() }
                LevelMeter(level: recorder.level)
                Text("\(Self.clock(recorder.remaining)) left")
                    .font(BumpFont.titleMedium.monospacedDigit())
                    .foregroundStyle(BumpColor.onSurface)
                    .accessibilityLabel("\(Int(recorder.remaining)) seconds left")

            case .finished(let duration, let interrupted):
                Card {
                    VStack(alignment: .leading, spacing: Space.s) {
                        Text("Recorded \(Self.clock(duration))")
                            .font(BumpFont.titleMedium).foregroundStyle(BumpColor.onSurface)
                        if interrupted {
                            Text("Recording stopped because of an interruption. You can use what you have or record again.")
                                .font(BumpFont.bodySmall).foregroundStyle(BumpColor.onSurfaceVariant)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        if let error = model.error {
                            Text(error).font(BumpFont.bodySmall).foregroundStyle(BumpColor.negative)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Button(model.error == nil ? "Use this recording" : "Try again", action: model.useRecording)
                            .buttonStyle(.bumpPrimary)
                        Button("Record again", action: model.recordAgain)
                            .buttonStyle(.bumpSecondary)
                    }
                }

            case .failed(let message):
                Card {
                    VStack(alignment: .leading, spacing: Space.s) {
                        Text(message).font(BumpFont.bodyLarge).foregroundStyle(BumpColor.onSurface)
                            .fixedSize(horizontal: false, vertical: true)
                        Button("Record again", action: model.recordAgain)
                            .buttonStyle(.bumpSecondary)
                    }
                }
            }

            if recorder.state != .recording {
                Button("Type instead", systemImage: "keyboard") { recorder.discard(); model.typing = true }
                    .buttonStyle(.bumpText)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var transcriptReview: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            SectionHeading(title: "Here's what we heard",
                           subtitle: "Fix anything that's off before we draft your card. This text isn't saved or shared.")
            BumpField(label: "Transcript", placeholder: "", axis: .vertical, lines: 4...12, text: $model.transcript)
                .focused($focused)
            HStack {
                Text("Transcribed by xAI speech-to-text")
                    .font(BumpFont.bodySmall).foregroundStyle(BumpColor.onSurfaceVariant)
                Spacer()
                Button("Record again", action: model.recordAgain)
                    .buttonStyle(.bumpText)
            }
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
                    .font(BumpFont.bodySmall).foregroundStyle(BumpColor.onSurfaceVariant)
                Spacer()
                if model.cloudAllowed {
                    Button("Record instead", systemImage: "mic") { model.typing = false; focused = false }
                        .buttonStyle(.bumpText)
                }
            }
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
        Card(padding: Space.l) {
            VStack(alignment: .leading, spacing: Space.m) {
                HStack(spacing: Space.sm) {
                    Image(systemName: "lock.shield.fill")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(BumpColor.primary)
                        .frame(width: 40, height: 40)
                        .background(Circle().fill(BumpColor.primaryContainer))
                    Text("Before anything leaves your phone")
                        .font(BumpFont.titleLarge)
                        .foregroundStyle(BumpColor.onSurface)
                }
                Text("To transcribe your intro and suggest a card, BUMP sends your recording, anything you type here, and your answers to the BUMP server, which passes them to xAI's Grok.")
                    .font(BumpFont.bodyMedium).foregroundStyle(BumpColor.onSurface)
                    .fixedSize(horizontal: false, vertical: true)
                Text("The BUMP server doesn't store your audio or text. xAI's documentation says API requests are kept for up to 30 days for auditing. Later, if you and the person you bump both allow it, your shared interests are sent the same way to write talking points.")
                    .font(BumpFont.bodySmall).foregroundStyle(BumpColor.onSurfaceVariant)
                    .fixedSize(horizontal: false, vertical: true)
                VStack(spacing: Space.sm) {
                    Button("Allow cloud processing") { model.chooseCloud(true) }
                        .buttonStyle(.bumpPrimary)
                    Button("Keep everything on this phone") { model.chooseCloud(false) }
                        .buttonStyle(.bumpSecondary)
                }
                Text("On this phone you type instead of speak. You can change this any time in You.")
                    .font(BumpFont.bodySmall).foregroundStyle(BumpColor.onSurfaceVariant)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

// MARK: - 3. Questions

private struct QuestionsStep: View {
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
                VStack(alignment: .leading, spacing: Space.s) {
                    Text("A little more")
                        .font(BumpFont.headlineLarge)
                        .foregroundStyle(BumpColor.onSurface)
                    Text("Up to three quick questions. Skip anything.")
                        .font(BumpFont.bodyLarge)
                        .foregroundStyle(BumpColor.onSurfaceVariant)
                }

                if model.busy == .transcribing {
                    WorkingCard(title: "Listening back to your answer…", detail: nil, onCancel: model.cancelUpload)
                } else if model.busy == .thinking {
                    WorkingCard(title: "Thinking of a good question…", detail: nil, onCancel: model.finishQuestions)
                } else if let question = model.current {
                    VStack(alignment: .leading, spacing: Space.s) {
                        Eyebrow(text: "Question \(model.questionNumber) of up to \(OnboardingModel.maxQuestions)")
                        Card(style: .primaryTonal, padding: Space.l) {
                            VStack(alignment: .leading, spacing: Space.sm) {
                                Image(systemName: "quote.opening")
                                    .font(.system(size: 18, weight: .bold))
                                    .foregroundStyle(BumpColor.primary)
                                Text(question.text)
                                    .font(BumpFont.headlineSmall)
                                    .foregroundStyle(BumpColor.onPrimaryContainer)
                                    .fixedSize(horizontal: false, vertical: true)
                                Text(question.origin == .grok ? "Question from Grok" : "Question from your phone")
                                    .font(BumpFont.labelMedium)
                                    .foregroundStyle(BumpColor.onPrimaryContainer.opacity(0.7))
                            }
                        }
                        .id(question.text)
                        .transition(.opacity)
                        HStack {
                            Button(model.speaksQuestions ? "Read aloud: on" : "Read aloud: off",
                                   systemImage: model.speaksQuestions ? "speaker.wave.2.fill" : "speaker.slash.fill") {
                                model.speaksQuestions.toggle()
                                if model.speaksQuestions { model.speakCurrent() }
                            }
                            .buttonStyle(.bumpText(BumpColor.onSurfaceVariant))
                            Spacer()
                        }
                        if model.canAnswerByVoice {
                            voiceAnswer
                        }
                        if let error = model.error {
                            NoticeText(text: error)
                        }
                        BumpField(label: model.canAnswerByVoice ? "Or type your answer" : "Your answer",
                                  placeholder: "A sentence is plenty",
                                  axis: .vertical, lines: 2...6, text: $model.answer)
                            .focused($focused)
                    }
                }

                if model.busy == .idle && model.current == nil {
                    Card {
                        VStack(alignment: .leading, spacing: Space.s) {
                            Text("That's everything we wanted to ask.")
                                .font(BumpFont.titleMedium).foregroundStyle(BumpColor.onSurface)
                            Button("See your card", action: model.finishQuestions)
                                .buttonStyle(.bumpPrimary)
                        }
                    }
                }

                if let notice = model.notice {
                    NoticeText(text: notice)
                }

                if !model.answered.isEmpty {
                    VStack(alignment: .leading, spacing: Space.xs) {
                        ForEach(model.answered) { qa in
                            HStack(alignment: .top, spacing: Space.s) {
                                Image(systemName: qa.answer == nil ? "arrow.uturn.right" : "checkmark.circle.fill")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(qa.answer == nil ? BumpColor.onSurfaceVariant : BumpColor.positive)
                                    .padding(.top, 2)
                                Text(qa.answer == nil ? "Skipped: \(qa.question.text)" : qa.question.text)
                                    .font(BumpFont.bodySmall)
                                    .foregroundStyle(BumpColor.onSurfaceVariant)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                    .accessibilityElement(children: .combine)
                }
            }
            .animation(Motion.effects, value: model.current)
        }
        .safeAreaInset(edge: .bottom) {
            if model.busy == .idle && model.current != nil {
                BottomBar {
                    Button("Next") { model.submitAnswer() }
                        .buttonStyle(.bumpPrimary)
                        .disabled(model.answer.trimmed().isEmpty)
                    HStack {
                        Button("Skip question", action: model.skipQuestion)
                        Spacer()
                        Button("Done with questions", action: model.finishQuestions)
                    }
                    .buttonStyle(.bumpText(BumpColor.onSurfaceVariant))
                }
            }
        }
        // Talking first: the keyboard stays down when voice answers are on,
        // so the mic is the obvious next move.
        .onAppear {
            focused = !model.canAnswerByVoice
            model.speakCurrent()
        }
        .onChange(of: model.current) { _, q in if q != nil { focused = !model.canAnswerByVoice } }
        .onChange(of: recorder.state) { _, state in
            if case .finished = state { model.useAnswerRecording() }
        }
        .onDisappear { model.voice.stop() }
    }

    @ViewBuilder
    private var voiceAnswer: some View {
        HStack(spacing: Space.m) {
            switch recorder.state {
            case .recording:
                RecordButton(recording: true) { recorder.stop() }
                LevelMeter(level: recorder.level)
                Text("Tap to finish")
                    .font(BumpFont.labelLarge).foregroundStyle(BumpColor.onSurfaceVariant)
            case .denied:
                Text("Microphone access is off for BUMP. Turn it on in Settings, or type below.")
                    .font(BumpFont.bodySmall).foregroundStyle(BumpColor.onSurfaceVariant)
                    .fixedSize(horizontal: false, vertical: true)
            case .failed(let why):
                RecordButton(recording: false) { model.startVoiceAnswer() }
                Text(why)
                    .font(BumpFont.bodySmall).foregroundStyle(BumpColor.onSurfaceVariant)
                    .fixedSize(horizontal: false, vertical: true)
            default:
                RecordButton(recording: false) { focused = false; model.startVoiceAnswer() }
                Text("Tap to answer out loud")
                    .font(BumpFont.labelLarge).foregroundStyle(BumpColor.onSurface)
            }
            Spacer(minLength: 0)
        }
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
                VStack(alignment: .leading, spacing: Space.s) {
                    Text("Your Bump card")
                        .font(BumpFont.headlineLarge)
                        .foregroundStyle(BumpColor.onSurface)
                    Text("Confirmed partners receive this card. Keep what's right, fix what isn't, and uncheck anything you'd rather not share.")
                        .font(BumpFont.bodyLarge)
                        .foregroundStyle(BumpColor.onSurfaceVariant)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if let notice = model.notice { NoticeText(text: notice) }

                HStack(alignment: .top, spacing: Space.m) {
                    PhotoPickerAvatar(photo: $model.photo, name: model.name, size: 64)
                    BumpField(label: "Name", placeholder: "Your name", text: $model.name)
                }

                VStack(alignment: .leading, spacing: Space.xs) {
                    BumpField(label: "Short bio (optional)", placeholder: "One line about you",
                              axis: .vertical, lines: 1...4, text: Binding(get: { model.bio },
                                                             set: { model.bio = $0; model.bioEdited() }))
                    if model.bioOrigin == .grok {
                        Text("Suggested by Grok from your intro. Edit freely.")
                            .font(BumpFont.bodySmall).foregroundStyle(BumpColor.onSurfaceVariant)
                    }
                }

                ForEach(ProfileFact.Kind.allCases, id: \.self) { kind in
                    section(kind)
                }

                Text("Only your name, photo, bio and the checked items are shared, and only with someone you've both confirmed after a bump. Your recording, transcript and answers are never saved or shared.")
                    .font(BumpFont.bodySmall)
                    .foregroundStyle(BumpColor.onSurfaceVariant)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .safeAreaInset(edge: .bottom) {
            BottomBar {
                Button("Start meeting people", action: onFinished)
                    .buttonStyle(.bumpPrimary)
                    .disabled(!model.canFinish)
                if !model.canFinish {
                    Text("Add your name and check at least one thing to continue.")
                        .font(BumpFont.bodySmall)
                        .foregroundStyle(BumpColor.onSurfaceVariant)
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
                    .font(BumpFont.titleLarge)
                    .foregroundStyle(BumpColor.onSurface)
                Spacer()
                Button {
                    addText = ""
                    adding = kind
                } label: {
                    Label("Add", systemImage: "plus")
                }
                .buttonStyle(.bumpText)
                .accessibilityLabel("Add \(kind.title.lowercased())")
            }

            let items = model.items(kind)
            if items.isEmpty {
                Text(emptyText(kind))
                    .font(BumpFont.bodySmall)
                    .foregroundStyle(BumpColor.onSurfaceVariant)
            } else {
                ListGroup {
                    ForEach(items) { item in
                        row(item)
                    }
                }
            }

            if kind == .interest {
                DisclosureGroup(isExpanded: $browsing) {
                    TopicBrowser(isSelected: model.isSelected, toggle: model.toggleCatalog)
                        .padding(.top, Space.s)
                } label: {
                    Text("Browse interests")
                        .font(BumpFont.labelLarge)
                        .foregroundStyle(BumpColor.primary)
                }
                .tint(BumpColor.primary)
            }
        }
    }

    private func row(_ item: OnboardingModel.Item) -> some View {
        HStack(alignment: .top, spacing: Space.s) {
            Button { withAnimation(Motion.spatialFast) { model.toggle(item.id) } } label: {
                ZStack {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(item.included ? BumpColor.primary : .clear)
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(item.included ? .clear : BumpColor.outline, lineWidth: 2)
                    if item.included {
                        Image(systemName: "checkmark")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(BumpColor.onPrimary)
                    }
                }
                .frame(width: 22, height: 22)
                .frame(width: 40, height: 40)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(item.included ? "Shared: \(item.text)" : "Not shared: \(item.text)")
            .accessibilityHint("Double-tap to \(item.included ? "stop sharing" : "share") this")

            VStack(alignment: .leading, spacing: 2) {
                Text(item.text)
                    .font(BumpFont.bodyLarge)
                    .foregroundStyle(item.included ? BumpColor.onSurface : BumpColor.onSurfaceVariant)
                    .strikethrough(!item.included, color: BumpColor.onSurfaceVariant)
                    .fixedSize(horizontal: false, vertical: true)
                if let evidence = item.evidence {
                    Text("From “\(evidence)”")
                        .font(BumpFont.bodySmall)
                        .foregroundStyle(BumpColor.onSurfaceVariant)
                        .lineLimit(2)
                }
                Text(item.origin.label)
                    .font(.caption2)
                    .foregroundStyle(BumpColor.onSurfaceVariant)
            }
            Spacer(minLength: 0)
            Menu {
                Button("Edit", systemImage: "pencil") { editText = item.text; editing = item }
                Button("Remove", systemImage: "trash", role: .destructive) { model.remove(item.id) }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(BumpColor.onSurfaceVariant)
                    .frame(width: 40, height: 40)
                    .contentShape(Circle())
            }
            .accessibilityLabel("More for \(item.text)")
        }
        .padding(.horizontal, Space.sm)
        .padding(.vertical, Space.s)
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

private struct WorkingCard: View {
    let title: String
    let detail: String?
    var onCancel: (() -> Void)?

    var body: some View {
        Card(style: .filled, padding: Space.l) {
            HStack(alignment: .top, spacing: Space.m) {
                LoadingIndicator(size: 28)
                VStack(alignment: .leading, spacing: Space.xs) {
                    Text(title).font(BumpFont.titleMedium).foregroundStyle(BumpColor.onSurface)
                    if let detail {
                        Text(detail).font(BumpFont.bodySmall).foregroundStyle(BumpColor.onSurfaceVariant)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if let onCancel {
                        Button("Cancel", action: onCancel)
                            .buttonStyle(.bumpText)
                            .padding(.leading, -12)
                    }
                }
            }
        }
        .accessibilityElement(children: .combine)
    }
}

private struct RecordButton: View {
    let recording: Bool
    let action: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulse = false

    var body: some View {
        Button(action: action) {
            ZStack {
                if recording {
                    Circle()
                        .fill(BumpColor.negative.opacity(0.18))
                        .frame(width: 120, height: 120)
                        .scaleEffect(pulse ? 1.15 : 0.9)
                        .opacity(pulse ? 0.3 : 0.8)
                }
                RoundedRectangle(cornerRadius: recording ? Radius.extraLarge : 48, style: .continuous)
                    .fill(recording ? BumpColor.negative : BumpColor.primary)
                    .frame(width: 96, height: 96)
                    .shadow(color: (recording ? BumpColor.negative : BumpColor.primary).opacity(0.25), radius: 14, y: 6)
                if recording {
                    RoundedRectangle(cornerRadius: 6, style: .continuous).fill(.white).frame(width: 30, height: 30)
                } else {
                    Image(systemName: "mic.fill").font(.system(size: 34, weight: .semibold)).foregroundStyle(.white)
                }
            }
            .frame(width: 120, height: 120)
        }
        .buttonStyle(RecordPressStyle())
        .animation(reduceMotion ? nil : Motion.spatial, value: recording)
        .animation(reduceMotion || !recording ? nil : .easeInOut(duration: 0.9).repeatForever(autoreverses: true), value: pulse)
        .onAppear { pulse = recording && !reduceMotion }
        .onChange(of: recording) { _, on in pulse = on && !reduceMotion }
        .accessibilityLabel(recording ? "Stop recording" : "Start recording")
        .padding(.top, Space.s)
    }
}

private struct RecordPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .animation(Motion.spatialFast, value: configuration.isPressed)
    }
}

private struct LevelMeter: View {
    let level: Float
    var body: some View {
        GeometryReader { geo in
            Capsule().fill(BumpColor.surfaceContainerHighest)
                .overlay(alignment: .leading) {
                    Capsule().fill(BumpColor.primary)
                        .frame(width: max(8, geo.size.width * CGFloat(level)))
                        .animation(.linear(duration: 0.1), value: level)
                }
        }
        .frame(width: 200, height: 10)
        .accessibilityHidden(true)
    }
}

// MARK: - Previews (SAMPLE DATA: not real people)

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
