import SwiftUI

/// First-run onboarding: name → spoken intro → a few follow-ups → your card.
/// All state lives in `OnboardingModel`, so moving back and forth never loses
/// an answer or an edit.
struct OnboardingFlow: View {
    @StateObject private var model: OnboardingModel
    @StateObject private var voice: VoiceOnboardingModel
    var onFinished: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var movingForward = true
    @State private var showVoice = false

    init(store: Store, model: OnboardingModel? = nil, voice: VoiceOnboardingModel? = nil,
         onFinished: @escaping () -> Void) {
        let onboarding = model ?? OnboardingModel(store: store)
        _model = StateObject(wrappedValue: onboarding)
        _voice = StateObject(wrappedValue: voice ?? VoiceOnboardingModel(onboarding: onboarding))
        self.onFinished = onFinished
    }

    var body: some View {
        VStack(spacing: 0) {
            topBar
            ZStack {
                switch model.step {
                case .name: NameStep(model: model).transition(transition)
                case .intro: IntroStep(model: model, startVoice: startVoice).transition(transition)
                case .questions: QuestionsStep(model: model).transition(transition)
                case .card: CardStep(model: model, onFinished: finish).transition(transition)
                }
            }
            .animation(reduceMotion ? .easeInOut(duration: 0.2) : .easeInOut(duration: 0.28), value: model.step)
        }
        .background(BumpColor.background.ignoresSafeArea())
        .onChange(of: model.step) { old, new in movingForward = new > old }
        .onDisappear { model.tearDown(); voice.stop() }
        .fullScreenCover(isPresented: $showVoice) {
            VoiceOnboardingView(model: voice,
                                onSaved: { showVoice = false; Haptics.success(); onFinished() },
                                onTypeInstead: { voice.typeInstead(); showVoice = false },
                                onClose: { voice.stop(); showVoice = false })
        }
    }

    private func startVoice() {
        showVoice = true
        voice.start()
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
                Image(systemName: "chevron.left")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(BumpColor.navy)
                    .frame(width: 44, height: 44)
            }
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

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<total, id: \.self) { i in
                Capsule()
                    .fill(i <= current ? BumpColor.action : BumpColor.hairline)
                    .frame(width: i == current ? 22 : 8, height: 8)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: current)
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
                    .font(BumpFont.screenTitle)
                    .foregroundStyle(BumpColor.navy)
                    .fixedSize(horizontal: false, vertical: true)
                Text("This is the name people see after you bump.")
                    .font(BumpFont.body)
                    .foregroundStyle(BumpColor.secondaryText)
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
    var startVoice: () -> Void
    @FocusState private var focused: Bool

    var body: some View {
        Screen {
            VStack(alignment: .leading, spacing: Space.l) {
                VStack(alignment: .leading, spacing: Space.s) {
                    Text("Tell us about yourself")
                        .font(BumpFont.screenTitle)
                        .foregroundStyle(BumpColor.navy)
                    Text("We'll turn it into your Bump profile.")
                        .font(BumpFont.body)
                        .foregroundStyle(BumpColor.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if !model.typing {
                    VoiceStartCard(start: startVoice, typeInstead: { model.typing = true })
                } else if model.cloud == .undecided {
                    CloudConsentCard(model: model)
                } else if model.busy == .drafting {
                    WorkingCard(title: "Drafting your profile…",
                                detail: model.cloudAllowed ? "Grok is reading your intro." : nil,
                                onCancel: model.cancelUpload)
                } else {
                    typingPanel
                }

                if let notice = model.notice {
                    NoticeText(text: notice)
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            if model.typing && model.cloud != .undecided && model.busy == .idle {
                BottomBar {
                    Button("Draft my profile", action: model.draftProfile)
                        .buttonStyle(.bumpPrimary)
                        .disabled(!model.canDraft)
                    Button("Skip, I'll pick interests myself", action: model.skipIntro)
                        .font(BumpFont.caption)
                        .foregroundStyle(BumpColor.secondaryText)
                        .padding(.top, Space.xs)
                }
            }
        }
        .onChange(of: model.typing) { _, typing in if typing { focused = true } }
    }

    private var typingPanel: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            BumpField(label: "Your intro",
                      placeholder: "I'm into…  I've been…  I'm hoping to…",
                      axis: .vertical, lines: 4...12, text: $model.transcript)
                .focused($focused)
            HStack {
                Text(model.cloudAllowed ? "Grok will suggest a card from this." : "Stays on this phone. Your phone suggests a card from this.")
                    .font(BumpFont.caption).foregroundStyle(BumpColor.secondaryText)
                Spacer()
                Button("Talk instead") { model.typing = false; focused = false }
                    .font(BumpFont.caption)
                    .foregroundStyle(BumpColor.action)
            }
        }
    }
}

/// "Start talking" / "Type instead", with the one-line xAI notice.
private struct VoiceStartCard: View {
    var start: () -> Void
    var typeInstead: () -> Void

    var body: some View {
        VStack(spacing: Space.l) {
            ZStack {
                PulseRings(active: false)
                Circle().fill(BumpColor.action).frame(width: 96, height: 96)
                Image(systemName: "waveform")
                    .font(.system(size: 36, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .frame(height: 180)
            .accessibilityHidden(true)

            Text("Bump will ask you two or three quick questions out loud. It takes about a minute, and you can check everything before it's saved.")
                .font(BumpFont.body)
                .foregroundStyle(BumpColor.navy)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            VStack(spacing: Space.s) {
                Button(action: start) {
                    Label("Start talking", systemImage: "mic.fill")
                }
                .buttonStyle(.bumpPrimary)
                Button("Type instead", action: typeInstead)
                    .buttonStyle(.bumpSecondary)
            }

            Text("Your voice and answers are processed by xAI through the Bump server. Audio isn't saved, and only the card you approve is kept.")
                .font(BumpFont.caption)
                .foregroundStyle(BumpColor.secondaryText)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Consent

private struct CloudConsentCard: View {
    @ObservedObject var model: OnboardingModel

    var body: some View {
        Card(padding: Space.l) {
            VStack(alignment: .leading, spacing: Space.m) {
                Label("Before anything leaves your phone", systemImage: "lock.shield")
                    .font(BumpFont.bodyEmphasis)
                    .foregroundStyle(BumpColor.navy)
                Text("To transcribe your intro and suggest a card, BUMP sends your recording, anything you type here, and your answers to the BUMP server, which passes them to xAI's Grok. The BUMP server saves the text of your intro and answers (never the audio).")
                    .font(BumpFont.caption).foregroundStyle(BumpColor.navy)
                    .fixedSize(horizontal: false, vertical: true)
                Text("The BUMP server doesn't store your audio or text. xAI's documentation says API requests are kept for up to 30 days for auditing. Later, if you and the person you bump both allow it, your shared interests are sent the same way to write talking points.")
                    .font(BumpFont.caption).foregroundStyle(BumpColor.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Allow cloud processing") { model.chooseCloud(true) }
                    .buttonStyle(.bumpPrimary)
                Button("Keep everything on this phone") { model.chooseCloud(false) }
                    .buttonStyle(.bumpSecondary)
                Text("On this phone you type instead of speak. You can change this any time in You.")
                    .font(BumpFont.caption).foregroundStyle(BumpColor.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

// MARK: - 3. Questions

private struct QuestionsStep: View {
    @ObservedObject var model: OnboardingModel
    @FocusState private var focused: Bool

    var body: some View {
        Screen {
            VStack(alignment: .leading, spacing: Space.l) {
                VStack(alignment: .leading, spacing: Space.s) {
                    Text("A little more")
                        .font(BumpFont.screenTitle)
                        .foregroundStyle(BumpColor.navy)
                    Text("Up to three quick questions. Skip anything.")
                        .font(BumpFont.body)
                        .foregroundStyle(BumpColor.secondaryText)
                }

                if model.busy == .thinking {
                    WorkingCard(title: "Thinking of a good question…", detail: nil, onCancel: model.finishQuestions)
                } else if let question = model.current {
                    VStack(alignment: .leading, spacing: Space.s) {
                        Text("Question \(model.questionNumber) of up to \(OnboardingModel.maxQuestions)")
                            .font(BumpFont.caption)
                            .foregroundStyle(BumpColor.secondaryText)
                        Card {
                            VStack(alignment: .leading, spacing: Space.s) {
                                Text(question.text)
                                    .font(BumpFont.sectionTitle)
                                    .foregroundStyle(BumpColor.navy)
                                    .fixedSize(horizontal: false, vertical: true)
                                Text(question.origin == .grok ? "Question from Grok" : "Question from your phone")
                                    .font(BumpFont.caption)
                                    .foregroundStyle(BumpColor.secondaryText)
                            }
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
                                Image(systemName: qa.answer == nil ? "arrow.uturn.right" : "checkmark")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(BumpColor.secondaryText)
                                    .padding(.top, 2)
                                Text(qa.answer == nil ? "Skipped: \(qa.question.text)" : qa.question.text)
                                    .font(BumpFont.caption)
                                    .foregroundStyle(BumpColor.secondaryText)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                    .accessibilityElement(children: .combine)
                }
            }
            .animation(.easeInOut(duration: 0.2), value: model.current)
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
                    .font(BumpFont.caption)
                    .foregroundStyle(BumpColor.secondaryText)
                    .padding(.top, Space.xs)
                }
            }
        }
        .onAppear { focused = true }
        .onChange(of: model.current) { _, q in if q != nil { focused = true } }
    }
}

// MARK: - 4. Card

private struct CardStep: View {
    @ObservedObject var model: OnboardingModel
    var onFinished: () -> Void

    var body: some View {
        Screen {
            VStack(alignment: .leading, spacing: Space.l) {
                VStack(alignment: .leading, spacing: Space.s) {
                    Text("Your Bump card")
                        .font(BumpFont.screenTitle)
                        .foregroundStyle(BumpColor.navy)
                    Text("Confirmed partners receive this card. Keep what's right, fix what isn't, and uncheck anything you'd rather not share.")
                        .font(BumpFont.body)
                        .foregroundStyle(BumpColor.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                BumpCardEditor(model: model)
            }
        }
        .safeAreaInset(edge: .bottom) {
            BottomBar {
                Button("Start bumping", action: onFinished)
                    .buttonStyle(.bumpPrimary)
                    .disabled(!model.canFinish)
                if !model.canFinish {
                    Text("Add your name and check at least one thing to continue.")
                        .font(BumpFont.caption)
                        .foregroundStyle(BumpColor.secondaryText)
                }
            }
        }
    }
}

/// The editable card: photo, name, bio, interests / experiences / goals with
/// their evidence, check to share, edit, remove, add, browse. Shared by the
/// typed flow and spoken review.
struct BumpCardEditor: View {
    @ObservedObject var model: OnboardingModel

    @State private var editing: OnboardingModel.Item?
    @State private var editText = ""
    @State private var adding: ProfileFact.Kind?
    @State private var addText = ""
    @State private var browsing = false

    var body: some View {
            VStack(alignment: .leading, spacing: Space.l) {
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
                            .font(BumpFont.caption).foregroundStyle(BumpColor.secondaryText)
                    }
                }

                ForEach(ProfileFact.Kind.allCases, id: \.self) { kind in
                    section(kind)
                }

                Text("Only your name, photo, bio and the checked items are shared, and only with someone you've both confirmed after a bump. Your voice is never saved\(model.cloudAllowed ? ". What you said and typed is saved on the BUMP server, never shared." : ", and your transcript and answers stay on this phone.")")
                    .font(BumpFont.caption)
                    .foregroundStyle(BumpColor.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
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
                        .font(BumpFont.caption.weight(.semibold))
                        .foregroundStyle(BumpColor.action)
                }
                .accessibilityLabel("Add \(kind.title.lowercased())")
            }

            let items = model.items(kind)
            if items.isEmpty {
                Text(emptyText(kind))
                    .font(BumpFont.caption)
                    .foregroundStyle(BumpColor.secondaryText)
            } else {
                VStack(spacing: 0) {
                    ForEach(items) { item in
                        row(item)
                        if item.id != items.last?.id { Divider().padding(.leading, 44) }
                    }
                }
                .background(RoundedRectangle(cornerRadius: Space.corner, style: .continuous).fill(BumpColor.surface))
            }

            if kind == .interest {
                DisclosureGroup(isExpanded: $browsing) {
                    TopicBrowser(isSelected: model.isSelected, toggle: model.toggleCatalog)
                        .padding(.top, Space.s)
                } label: {
                    Text("Browse interests")
                        .font(BumpFont.caption.weight(.semibold))
                        .foregroundStyle(BumpColor.action)
                }
                .tint(BumpColor.action)
            }
        }
    }

    private func row(_ item: OnboardingModel.Item) -> some View {
        HStack(alignment: .top, spacing: Space.s) {
            Button { model.toggle(item.id) } label: {
                Image(systemName: item.included ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 22))
                    .foregroundStyle(item.included ? BumpColor.action : BumpColor.secondaryText)
                    .frame(width: 32, height: 32)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(item.included ? "Shared: \(item.text)" : "Not shared: \(item.text)")
            .accessibilityHint("Double-tap to \(item.included ? "stop sharing" : "share") this")

            VStack(alignment: .leading, spacing: 2) {
                Text(item.text)
                    .font(BumpFont.body)
                    .foregroundStyle(item.included ? BumpColor.navy : BumpColor.secondaryText)
                    .strikethrough(!item.included, color: BumpColor.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                if let evidence = item.evidence {
                    Text("From “\(evidence)”")
                        .font(BumpFont.caption)
                        .foregroundStyle(BumpColor.secondaryText)
                        .lineLimit(2)
                }
                Text(item.origin.label)
                    .font(.caption2)
                    .foregroundStyle(BumpColor.secondaryText)
            }
            Spacer(minLength: 0)
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
        .padding(.horizontal, Space.s)
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

struct BottomBar<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        VStack(spacing: Space.xs) { content }
            .padding(.horizontal, Space.gutter)
            .padding(.top, Space.s)
            .padding(.bottom, Space.s)
            .background(BumpColor.background.ignoresSafeArea(edges: .bottom))
    }
}

struct WorkingCard: View {
    let title: String
    let detail: String?
    var onCancel: (() -> Void)?

    var body: some View {
        Card(padding: Space.l) {
            HStack(alignment: .top, spacing: Space.m) {
                ProgressView().tint(BumpColor.action)
                VStack(alignment: .leading, spacing: Space.xs) {
                    Text(title).font(BumpFont.bodyEmphasis).foregroundStyle(BumpColor.navy)
                    if let detail {
                        Text(detail).font(BumpFont.caption).foregroundStyle(BumpColor.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if let onCancel {
                        Button("Cancel", action: onCancel)
                            .font(BumpFont.caption.weight(.semibold))
                            .foregroundStyle(BumpColor.action)
                            .padding(.top, Space.xs)
                    }
                }
            }
        }
        .accessibilityElement(children: .combine)
    }
}

struct NoticeText: View {
    let text: String
    var body: some View {
        HStack(alignment: .top, spacing: Space.s) {
            Image(systemName: "info.circle").foregroundStyle(BumpColor.warning)
            Text(text).font(BumpFont.caption).foregroundStyle(BumpColor.navy)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Space.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Space.corner, style: .continuous).fill(BumpColor.paleBlue))
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
