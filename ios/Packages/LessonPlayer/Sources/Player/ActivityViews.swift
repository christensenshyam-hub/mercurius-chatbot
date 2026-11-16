import SwiftUI
import DesignSystem

struct ActivityStepView: View {
    let model: LessonPlayerModel
    let activity: Activity
    /// This step's own record, not the model's current one: while a step
    /// fades out, the model has already moved on (see `StepTransition`).
    let record: StepRecord
    var headingFocused: AccessibilityFocusState<Bool>.Binding
    /// Brings the feedback into view; called as the panel starts to appear.
    var scrollToFeedback: () -> Void = {}

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// The submission whose result has fully played. A step that opens on a
    /// result (a resumed attempt) shows it as it is.
    @State private var settledIndex: Int?
    @State private var playing: (index: Int, reveal: FeedbackReveal)?
    @State private var playTask: Task<Void, Never>?
    /// After Try again, while the options ease back to neutral.
    @State private var easingBack = false
    /// After Try again, the last result's panel stays in the layout while it
    /// fades out, so nothing slides under it; then it leaves and the hint
    /// appears. The index is the submission whose panel has gone.
    @State private var dismissedPanelIndex: Int?
    @State private var leavingPanelOpacity: Double = 1
    @State private var popTick = 0
    @State private var pulseTick = 0
    @State private var shakeTick = 0
    @State private var successTick = 0
    @State private var warningTick = 0

    init(model: LessonPlayerModel, activity: Activity, record: StepRecord,
         headingFocused: AccessibilityFocusState<Bool>.Binding, scrollToFeedback: @escaping () -> Void = {}) {
        self.model = model
        self.activity = activity
        self.record = record
        self.headingFocused = headingFocused
        self.scrollToFeedback = scrollToFeedback
        _settledIndex = State(initialValue: record.lastSubmission?.index)
        _dismissedPanelIndex = State(initialValue: record.phase == .viewing ? record.lastSubmission?.index : nil)
    }

    /// Try again has just been tapped and the old panel is still fading.
    private var leavingPanel: Submission? {
        guard choreographed, record.phase == .viewing, let last = record.lastSubmission,
              last.index != dismissedPanelIndex else { return nil }
        return last
    }

    /// Choice and claim steps play their result (`FeedbackChoreography`);
    /// written answers show theirs as before.
    private var choreographed: Bool { activity.isDeterministic }

    private var reveal: FeedbackReveal {
        guard choreographed else { return .settled }
        return FeedbackReveal.display(record: record, settledIndex: settledIndex,
                                      playing: playing.map { ($0.index, $0.reveal) })
    }

    private var optionMotion: OptionMotion {
        OptionMotion(reveal: reveal, popTick: popTick, pulseTick: pulseTick, shakeTick: shakeTick,
                     interactive: playing == nil && !easingBack)
    }

    /// A key that changes when a new objective result needs playing.
    private var pendingResult: Int? {
        guard choreographed, record.phase == .feedback || record.phase == .done,
              let last = record.lastSubmission, last.index != settledIndex, last.status.verdict != nil else { return nil }
        return last.index
    }

    var body: some View {
        let reveal = self.reveal
        VStack(alignment: .leading, spacing: BrandSpacing.lg) {
            if let scenario = activity.scenario { MaterialCard(material: scenario) }
            if let evidence = activity.evidence { MaterialCard(material: evidence, emphasis: true) }
            Text(activity.prompt)
                .font(BrandFont.subheading)
                .foregroundStyle(BrandColor.text)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
                .accessibilityFocused(headingFocused)

            switch activity.kind {
            case .choice(let choice):
                ChoiceList(model: model, choice: choice, record: record, motion: optionMotion)
                    .animation(easeBackAnimation, value: record.phase == .viewing)
            case .claimSelection(let selection):
                ClaimSelectionView(model: model, selection: selection, record: record, motion: optionMotion)
                    .animation(easeBackAnimation, value: record.phase == .viewing)
            case .shortResponse(let response):
                ShortResponseView(model: model, record: record, maxCharacters: response.maxCharacters, placeholder: response.placeholder)
            case .practice(let practice):
                PracticeView(model: model, practice: practice, record: record)
            }

            if record.hintsShown > 0, leavingPanel == nil {
                HintList(hints: Array(activity.hints.prefix(record.hintsShown)))
            }
            if record.phase == .viewing, leavingPanel == nil, record.hintsShown < activity.hints.count {
                DepthButton(title: PlayerCopy.showHint, icon: "lightbulb") { model.send(.showHint) }
                    .accessibilityIdentifier("player.hint")
            }
            if record.phase == .feedback || record.phase == .done, let last = record.lastSubmission, reveal.panel {
                FeedbackPanel(activity: activity, submission: last, revealed: record.revealed)
                    // Joins the layout at once (so the scroll can reach it and
                    // nothing glides through it), then fades and rises itself.
                    .modifier(PanelArrival(animated: playing != nil, rise: reduceMotion ? 0 : FeedbackChoreography.panelRise,
                                           animation: panelAnimation))
            }
            if let leaving = leavingPanel {
                FeedbackPanel(activity: activity, submission: leaving, revealed: false)
                    .opacity(leavingPanelOpacity)
                    .transition(.identity)
                    .accessibilityHidden(true)
            }
        }
        .haptic(.success, trigger: successTick)
        .haptic(.warning, trigger: warningTick)
        .onChange(of: playing?.reveal.panel == true) { _, shown in
            if shown { scrollToFeedback() }
        }
        .onChange(of: pendingResult) { _, index in
            if let index { play(index) }
        }
        .onChange(of: record.phase) { _, phase in
            guard choreographed, phase == .viewing else { return }
            // Try again (possibly mid-sequence): stop the sequence, settle,
            // and ignore taps while the options ease back.
            playTask?.cancel()
            playing = nil
            let index = record.lastSubmission?.index
            settledIndex = index
            easingBack = true
            withAnimation(Motion.resolved(.easeOut(duration: Motion.Duration.fast), reduceMotion: reduceMotion, fallback: .fade)) {
                leavingPanelOpacity = 0
            }
            playTask = Task { @MainActor in
                try? await Task.sleep(for: .seconds(Motion.Duration.fast))
                guard !Task.isCancelled else { return }
                // The panel is gone: let the layout close up and the hint in.
                withAnimation(colorAnimation) { dismissedPanelIndex = index }
                leavingPanelOpacity = 1
                try? await Task.sleep(for: .seconds(Motion.Duration.standard - Motion.Duration.fast))
                guard !Task.isCancelled else { return }
                easingBack = false
            }
        }
        .onDisappear { playTask?.cancel() }
    }

    // MARK: The result sequence

    private var colorAnimation: Animation? {
        Motion.resolved(.easeInOut(duration: Motion.Duration.standard), reduceMotion: reduceMotion, fallback: .fade)
    }

    /// Try again: the options ease back to neutral. Only the options: the
    /// rest of the step changes at once, so nothing fades over anything.
    /// (On Check the rows look the same until the result beat, which
    /// animates them itself.)
    private var easeBackAnimation: Animation? { choreographed ? colorAnimation : nil }

    private var panelAnimation: Animation? {
        Motion.resolved(Motion.gentle, reduceMotion: reduceMotion, fallback: .fade)
    }

    private func play(_ index: Int) {
        guard let last = record.lastSubmission, last.index == index, let verdict = last.status.verdict else { return }
        let outcome = FeedbackChoreography.Outcome(verdict: verdict, revealed: record.revealed)
        playTask?.cancel()
        easingBack = false
        playing = (index, FeedbackReveal())
        let beats = FeedbackChoreography.beats(for: outcome)
        // The first beat lands in the frame Check answer is handled, not
        // after a hop through a task.
        for (at, beat) in beats where at == 0 { apply(beat, outcome: outcome, index: index) }
        playTask = Task { @MainActor in
            var elapsed: TimeInterval = 0
            for (at, beat) in beats where at > 0 {
                if at > elapsed {
                    try? await Task.sleep(for: .seconds(at - elapsed))
                    elapsed = at
                }
                guard !Task.isCancelled, playing?.index == index else { return }
                apply(beat, outcome: outcome, index: index)
            }
        }
    }

    private func apply(_ beat: FeedbackChoreography.Beat, outcome: FeedbackChoreography.Outcome, index: Int) {
        switch beat {
        case .result:
            withAnimation(colorAnimation) { playing?.reveal.apply(.result) }
            if outcome == .correct { successTick += 1 } else { warningTick += 1 }
            // Movement and scale are left out under Reduce Motion.
            if !reduceMotion {
                if outcome == .correct { popTick += 1; pulseTick += 1 } else { shakeTick += 1 }
            }
        case .panel:
            // Not animated: the panel animates its own arrival
            // (`PanelArrival`); the scroll follows in
            // `onChange(of: playing?.reveal.panel)`, once it's in the layout.
            playing?.reveal.apply(.panel)
        case .revealAnswer:
            withAnimation(colorAnimation) { playing?.reveal.apply(.revealAnswer) }
        case .settled:
            settledIndex = index
            playing = nil
        }
    }
}

/// The feedback panel's arrival: it takes its place in the layout at once,
/// then fades in from `rise` points lower. A panel that's already there (a
/// resumed step, a settled result) just shows.
struct PanelArrival: ViewModifier {
    let animated: Bool
    let rise: CGFloat
    let animation: Animation?
    @State private var arrived = false

    func body(content: Content) -> some View {
        let shown = arrived || !animated
        content
            .opacity(shown ? 1 : 0)
            .offset(y: shown ? 0 : rise)
            .onAppear {
                guard animated else { return }
                withAnimation(animation) { arrived = true }
            }
    }
}

/// What the option rows show of a result while it plays, and the counters
/// that start each row's one-off movement.
struct OptionMotion: Equatable {
    var reveal: FeedbackReveal = .settled
    var popTick = 0
    var pulseTick = 0
    var shakeTick = 0
    var interactive = true

    /// The row state to show: before the result beat, a submitted pick still
    /// looks selected; the revealed answer waits for its own beat.
    func rowState(id: String, draft: Set<String>, submitted: Set<String>?, correct: Set<String>,
                  phase: StepPhase, revealed: Bool) -> RowState {
        guard reveal.result else {
            return LessonPlayer.rowState(id: id, draft: submitted ?? draft, submitted: nil, correct: correct,
                                         phase: .viewing, revealed: false)
        }
        return LessonPlayer.rowState(id: id, draft: draft, submitted: submitted, correct: correct,
                                     phase: phase, revealed: revealed && reveal.answer)
    }
}

// MARK: - Choice

/// Shows the state of one option row, paired with words so color is never the
/// only signal.
enum RowState: Equatable {
    case idle, selected, correctAnswer, yourCorrectAnswer, yourWrongAnswer, partOfAnswer

    var value: String? {
        switch self {
        case .idle: return nil
        case .selected: return PlayerCopy.selected
        case .correctAnswer: return PlayerCopy.correctAnswer
        case .yourCorrectAnswer: return PlayerCopy.yourCorrectAnswer
        case .yourWrongAnswer: return PlayerCopy.yourWrongAnswer
        case .partOfAnswer: return PlayerCopy.yourCorrectAnswer
        }
    }
}

/// Row states once an answer is graded. The right answer is marked only when
/// it's right, or once it has been revealed.
func rowState(id: String, draft: Set<String>, submitted: Set<String>?, correct: Set<String>,
              phase: StepPhase, revealed: Bool) -> RowState {
    guard phase == .feedback || phase == .done, let submitted else {
        return draft.contains(id) ? .selected : .idle
    }
    let picked = submitted.contains(id)
    let isRight = correct.contains(id)
    let answerShown = revealed || submitted == correct
    switch (picked, isRight) {
    case (true, true): return .yourCorrectAnswer
    case (true, false): return .yourWrongAnswer
    case (false, true): return answerShown ? .correctAnswer : .idle
    case (false, false): return .idle
    }
}

struct ChoiceList: View {
    let model: LessonPlayerModel
    let choice: ChoiceActivity
    let record: StepRecord
    var motion = OptionMotion()

    var body: some View {
        let draft: Set<String> = { if case .options(let s)? = record.draft { return s }; return [] }()
        let submitted: Set<String>? = { if case .options(let s)? = record.lastSubmission?.response { return s }; return nil }()
        VStack(alignment: .leading, spacing: BrandSpacing.sm) {
            if choice.selection == .multiple {
                Text(PlayerCopy.chooseAll)
                    .font(BrandFont.caption)
                    .foregroundStyle(BrandColor.textSecondary)
            }
            ForEach(Array(choice.options.enumerated()), id: \.element.id) { index, option in
                let state = motion.rowState(id: option.id, draft: draft, submitted: submitted, correct: choice.correct,
                                            phase: record.phase, revealed: record.revealed)
                OptionRow(
                    letter: PlayerCopy.letter(index),
                    text: option.text,
                    state: state,
                    multiple: choice.selection == .multiple,
                    enabled: record.phase == .viewing && motion.interactive,
                    motion: motion
                ) { model.send(.choose(option.id)) }
                .accessibilityIdentifier("player.option.\(option.id)")
            }
        }
    }
}

struct OptionRow: View {
    let letter: String
    let text: String
    let state: RowState
    let multiple: Bool
    let enabled: Bool
    var motion = OptionMotion()
    let action: () -> Void

    /// Your right pick pops its checkmark and pulses; your wrong pick shakes.
    /// (The counters only move on a result beat, and not under Reduce Motion.)
    private var pops: Bool { state == .yourCorrectAnswer || state == .partOfAnswer }
    private var shakes: Bool { state == .yourWrongAnswer }

    var body: some View {
        Button(action: action) {
            HStack(alignment: .firstTextBaseline, spacing: BrandSpacing.sm) {
                Image(systemName: icon)
                    .font(BrandFont.bodyEmphasized)
                    .foregroundStyle(tint)
                    .keyframeAnimator(initialValue: CGFloat(1), trigger: motion.popTick) { content, scale in
                        content.scaleEffect(pops ? scale : 1)
                    } keyframes: { _ in
                        MoveKeyframe(FeedbackChoreography.checkmarkStartScale)
                        SpringKeyframe(1, duration: Motion.Duration.standard, spring: Spring(duration: Motion.Duration.standard, bounce: 0.15))
                    }
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(text)
                        .font(BrandFont.body)
                        .foregroundStyle(BrandColor.text)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                    if let word = statusWord {
                        Text(word)
                            .font(BrandFont.caption.weight(.semibold))
                            .foregroundStyle(tint)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.vertical, BrandSpacing.md)
            .padding(.horizontal, BrandSpacing.md)
            .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
            .background(background, in: RoundedRectangle(cornerRadius: BrandRadius.md, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: BrandRadius.md, style: .continuous)
                    .stroke(stroke, lineWidth: state == .idle ? 1 : 2)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .keyframeAnimator(initialValue: CGFloat(1), trigger: motion.pulseTick) { content, scale in
            content.scaleEffect(pops ? scale : 1)
        } keyframes: { _ in
            CubicKeyframe(FeedbackChoreography.pulseScale, duration: 0.14)
            CubicKeyframe(1, duration: 0.2)
        }
        .keyframeAnimator(initialValue: CGFloat(0), trigger: motion.shakeTick) { content, x in
            content.offset(x: shakes ? x : 0)
        } keyframes: { _ in
            let d = FeedbackChoreography.shakeDistance
            let step = FeedbackChoreography.shakeDuration / Double(FeedbackChoreography.shakeOscillations * 2 + 1)
            KeyframeTrack {
                for i in 0..<(FeedbackChoreography.shakeOscillations * 2) {
                    LinearKeyframe(i.isMultiple(of: 2) ? d : -d, duration: step)
                }
                LinearKeyframe(0, duration: step)
            }
        }
        // Not `.disabled`: that dims the text, and an answered row (yours,
        // or the right one) must stay fully readable.
        .allowsHitTesting(enabled)
        .accessibilityRemoveTraits(enabled ? [] : .isButton)
        .accessibilityLabel("\(PlayerCopy.option) \(letter): \(text)")
        .accessibilityValue(state.value ?? "")
        .accessibilityAddTraits(state == .selected ? .isSelected : [])
    }

    private var statusWord: String? {
        switch state {
        case .idle, .selected: return nil
        default: return state.value
        }
    }

    private var icon: String {
        switch state {
        case .idle: return multiple ? "square" : "circle"
        case .selected: return multiple ? "checkmark.square.fill" : "largecircle.fill.circle"
        case .correctAnswer, .yourCorrectAnswer, .partOfAnswer: return "checkmark.circle.fill"
        case .yourWrongAnswer: return "xmark.circle.fill"
        }
    }

    private var tint: Color {
        switch state {
        case .idle: return BrandColor.textSecondary
        case .selected: return BrandColor.accentText
        case .correctAnswer, .yourCorrectAnswer, .partOfAnswer: return BrandColor.successText
        case .yourWrongAnswer: return BrandColor.errorText
        }
    }

    private var stroke: Color {
        switch state {
        case .idle: return BrandColor.border
        case .selected: return BrandColor.accent
        case .correctAnswer, .yourCorrectAnswer, .partOfAnswer: return BrandColor.success
        case .yourWrongAnswer: return BrandColor.error
        }
    }

    private var background: Color {
        switch state {
        case .idle: return BrandColor.surface
        case .selected: return BrandColor.accent.opacity(0.12)
        case .correctAnswer, .yourCorrectAnswer, .partOfAnswer: return BrandColor.success.opacity(0.12)
        case .yourWrongAnswer: return BrandColor.error.opacity(0.12)
        }
    }
}

// MARK: - Claim selection

/// The passage reads as continuous text (claims underlined), and the claims
/// are also listed as rows to choose from: the list is the way to select, so
/// it works the same with VoiceOver, Switch Control and large text.
struct ClaimSelectionView: View {
    let model: LessonPlayerModel
    let selection: ClaimSelectionActivity
    let record: StepRecord
    var motion = OptionMotion()

    var body: some View {
        let draft: Set<String> = { if case .claims(let s)? = record.draft { return s }; return [] }()
        let submitted: Set<String>? = { if case .claims(let s)? = record.lastSubmission?.response { return s }; return nil }()
        VStack(alignment: .leading, spacing: BrandSpacing.sm) {
            Text(PlayerCopy.chooseClaim)
                .font(BrandFont.caption)
                .foregroundStyle(BrandColor.textSecondary)
            ForEach(Array(selection.claims.enumerated()), id: \.offset) { index, segment in
                let id = segment.claimId ?? ""
                OptionRow(
                    letter: PlayerCopy.letter(index),
                    text: "“\(segment.text)”",
                    state: motion.rowState(id: id, draft: draft, submitted: submitted, correct: selection.correct,
                                           phase: record.phase, revealed: record.revealed),
                    multiple: selection.selection == .multiple,
                    enabled: record.phase == .viewing && motion.interactive,
                    motion: motion
                ) { model.send(.toggleClaim(id)) }
                .accessibilityIdentifier("player.claim.\(id)")
            }
        }
    }
}

// MARK: - Hints and feedback

struct HintList: View {
    let hints: [String]
    var body: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.xs) {
            ForEach(Array(hints.enumerated()), id: \.offset) { _, hint in
                Label(hint, systemImage: "lightbulb")
                    .font(BrandFont.body)
                    .foregroundStyle(BrandColor.text)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityLabel("\(PlayerCopy.hint): \(hint)")
            }
        }
        .padding(BrandSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(BrandColor.surface, in: RoundedRectangle(cornerRadius: BrandRadius.md, style: .continuous))
    }
}

struct FeedbackPanel: View {
    let activity: Activity
    let submission: Submission
    let revealed: Bool

    var body: some View {
        let look = FeedbackLook(status: submission.status)
        VStack(alignment: .leading, spacing: BrandSpacing.sm) {
            Label(look.title, systemImage: look.icon)
                .font(BrandFont.bodyEmphasized)
                .foregroundStyle(look.tint)
            ForEach(lines, id: \.self) { line in
                Text(line)
                    .font(BrandFont.body)
                    .foregroundStyle(BrandColor.text)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(BrandSpacing.md + 2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(look.tint.opacity(0.10), in: RoundedRectangle(cornerRadius: BrandRadius.lg, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: BrandRadius.lg, style: .continuous).stroke(look.tint.opacity(0.6), lineWidth: 1))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("player.feedback")
    }

    /// The feedback text: the answer-specific line, then any revealed answer,
    /// misconception correction, hint or fallback guidance. Short by design.
    private var lines: [String] {
        var out: [String] = []
        switch (activity.kind, submission.status) {
        case (.shortResponse, .ungraded(.support)):
            out.append(PlayerCopy.supportShown)
        case (.shortResponse(let sr), .ungraded):
            out.append(sr.fallbackGuidance)
        case (.shortResponse(let sr), .graded(let verdict)):
            if let f = submission.feedback { out.append(f) }
            for id in submission.flags {
                if let flag = sr.rubric.flags.first(where: { $0.id == id }) { out.append(flag.correction) }
            }
            if verdict != .correct, let hint = submission.hint { out.append("\(PlayerCopy.hint): \(hint)") }
            if verdict != .correct, revealed { out.append(PlayerCopy.exemplar(sr.exemplar)) }
        case (.shortResponse, .pending), (.practice, .pending):
            break
        case (.practice(let p), .notGraded):
            if let reply = submission.feedback { out.append(reply) }
            out.append(p.notice)
        case (.practice, .ungraded(.support)):
            out.append(PlayerCopy.supportShown)
        case (.practice(let p), .ungraded):
            out.append(p.fallbackGuidance)
        default:
            if let f = submission.feedback, !f.isEmpty { out.append(f) }
            if revealed, submission.status.verdict != .correct, let answer = revealedAnswer {
                out.append(answer)
            }
        }
        return out
    }

    private var revealedAnswer: String? {
        switch activity.kind {
        case .choice(let c):
            let texts = c.options.filter { c.correct.contains($0.id) }.map(\.text)
            return PlayerCopy.revealed(texts.joined(separator: "; "))
        case .claimSelection(let s):
            let texts = s.claims.filter { s.correct.contains($0.claimId ?? "") }.map { "“\($0.text)”" }
            return PlayerCopy.revealed(texts.joined(separator: "; "))
        case .shortResponse, .practice:
            return nil
        }
    }
}

struct FeedbackLook {
    let title: String
    let icon: String
    let tint: Color

    static func title(for status: GradingStatus) -> String {
        switch status {
        case .graded(.correct): return PlayerCopy.correct
        case .graded(.partial): return PlayerCopy.partly
        case .graded(.incorrect): return PlayerCopy.notQuite
        case .notGraded: return PlayerCopy.mercReplied
        case .pending: return PlayerCopy.checking
        case .ungraded: return PlayerCopy.notGradedYet
        }
    }

    init(status: GradingStatus) {
        switch status {
        case .graded(.correct):
            title = PlayerCopy.correct; icon = "checkmark.circle.fill"; tint = BrandColor.successText
        case .graded(.partial):
            title = PlayerCopy.partly; icon = "circle.lefthalf.filled"; tint = BrandColor.accentText
        case .graded(.incorrect):
            title = PlayerCopy.notQuite; icon = "arrow.uturn.backward.circle.fill"; tint = BrandColor.errorText
        case .notGraded:
            title = PlayerCopy.mercReplied; icon = "bubble.left.fill"; tint = BrandColor.accentText
        case .pending:
            title = PlayerCopy.checking; icon = "hourglass"; tint = BrandColor.textSecondary
        case .ungraded:
            title = PlayerCopy.notGradedYet; icon = "exclamationmark.circle.fill"; tint = BrandColor.textSecondary
        }
    }
}

// MARK: - Optional depth

struct DepthSection: View {
    let model: LessonPlayerModel
    let step: LessonStep
    let record: StepRecord

    private var why: [DepthItem] { step.depth.filter { $0.kind == .why } }
    private var examples: [DepthItem] { step.depth.filter { $0.kind == .example } }
    private var stages: [DepthItem] {
        step.depth.filter { if case .stage = $0.kind { return true } else { return false } }
    }

    var body: some View {
        let opened = record.depthOpened
        VStack(alignment: .leading, spacing: BrandSpacing.sm) {
            // What the learner opened sits first, in the order it was
            // authored (Go deeper stages in sequence), above what's left.
            ForEach(step.depth.filter { opened.contains($0.id) }) { item in
                DepthCard(item: item)
            }
            FlowLayout(spacing: BrandSpacing.sm) { buttons(opened) }
        }
    }

    @ViewBuilder
    private func buttons(_ opened: Set<String>) -> some View {
        ForEach(why + examples) { item in
            if !opened.contains(item.id) {
                DepthButton(title: item.title, icon: item.kind == .why ? "questionmark.circle" : "text.quote") {
                    model.send(.openDepth(item.id))
                }
            }
        }
        if let nextStage = stages.first(where: { !opened.contains($0.id) }) {
            DepthButton(title: opened.isDisjoint(with: stages.map(\.id)) ? PlayerCopy.goDeeper : PlayerCopy.goDeeperMore,
                        icon: "arrow.down.right.circle") {
                model.send(.openDepth(nextStage.id))
            }
        }
        if model.canAskMerc {
            DepthButton(title: PlayerCopy.askMerc, icon: "bubble.left.and.text.bubble.right") { model.askMerc() }
                .accessibilityHint(PlayerCopy.askMercHint)
        }
    }
}

struct DepthButton: View {
    let title: String
    let icon: String
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .font(BrandFont.caption.weight(.semibold))
                .padding(.horizontal, BrandSpacing.md)
                .frame(minHeight: 44)
                .background(BrandColor.surface, in: Capsule())
                .overlay(Capsule().stroke(BrandColor.border, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .foregroundStyle(BrandColor.accentText)
    }
}

struct DepthCard: View {
    let item: DepthItem
    var body: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.xs) {
            Text(item.title)
                .font(BrandFont.bodyEmphasized)
                .foregroundStyle(BrandColor.accentText)
            Text(item.body)
                .font(BrandFont.body)
                .foregroundStyle(BrandColor.text)
                .fixedSize(horizontal: false, vertical: true)
            if let origin = item.origin { OriginLabel(origin: origin) }
        }
        .padding(BrandSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(BrandColor.surface, in: RoundedRectangle(cornerRadius: BrandRadius.md, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

/// Lays its children out in rows, wrapping to the next row when one is full
/// (the optional-depth buttons). Each child keeps its natural size, capped
/// at the row width, so large text wraps inside a button instead of clipping.
struct FlowLayout: Layout {
    var spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(width: proposal.width ?? .infinity, subviews: subviews)
        let width = rows.map(\.width).max() ?? 0
        let height = rows.map(\.height).reduce(0, +) + spacing * CGFloat(max(rows.count - 1, 0))
        return CGSize(width: proposal.width ?? width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in arrange(width: bounds.width, subviews: subviews) {
            var x = bounds.minX
            for item in row.items {
                subviews[item.index].place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(item.size))
                x += item.size.width + spacing
            }
            y += row.height + spacing
        }
    }

    private struct Row {
        var items: [(index: Int, size: CGSize)] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func arrange(width: CGFloat, subviews: Subviews) -> [Row] {
        var rows: [Row] = [Row()]
        for index in subviews.indices {
            var size = subviews[index].sizeThatFits(.unspecified)
            if size.width > width {
                size = subviews[index].sizeThatFits(ProposedViewSize(width: width, height: nil))
            }
            let needed = rows[rows.count - 1].items.isEmpty ? size.width : rows[rows.count - 1].width + spacing + size.width
            if needed > width, !rows[rows.count - 1].items.isEmpty {
                rows.append(Row())
            }
            var row = rows[rows.count - 1]
            row.width = row.items.isEmpty ? size.width : row.width + spacing + size.width
            row.height = max(row.height, size.height)
            row.items.append((index, size))
            rows[rows.count - 1] = row
        }
        return rows.filter { !$0.items.isEmpty }
    }
}
