import SwiftUI
import DesignSystem

/// The interactive lesson player: one step at a time, one clear task, one
/// primary action (Check answer, then Continue), short feedback, and a way to
/// leave and come back. Text scrolls at every size; nothing essential is
/// clipped to fit one screen.
public struct LessonPlayerView: View {
    @State private var model: LessonPlayerModel
    /// The step on screen trails `model.step` through a two-phase change.
    @State private var transition: StepTransition
    /// The header's progress, which moves when the incoming step starts.
    @State private var shownProgress: Int
    @State private var leaveTask: Task<Void, Never>?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @AccessibilityFocusState private var headingFocused: Bool

    public init(model: LessonPlayerModel) {
        _model = State(initialValue: model)
        _transition = State(initialValue: StepTransition(stepId: model.step.id))
        _shownProgress = State(initialValue: model.machine.requiredProgress.done)
    }

    private var shownStep: LessonStep {
        model.content.step(id: transition.displayedStepId) ?? model.step
    }

    public var body: some View {
        VStack(spacing: 0) {
            PlayerHeader(
                title: model.content.title,
                progress: (shownProgress, model.machine.requiredProgress.total),
                onLeave: model.leave
            )
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: BrandSpacing.lg) {
                        Color.clear.frame(height: 0).id("top")
                        let step = shownStep
                        StepBody(model: model, step: step, record: model.machine.attempt.record(step.id),
                                 headingFocused: $headingFocused,
                                 scrollToFeedback: { scrollToFeedback(proxy) })
                            .opacity(transition.phase == .leaving ? 0 : 1)
                            .offset(x: transition.phase == .leaving ? StepMotion.leaveOffset(reduceMotion) : 0)
                            // The outgoing step's controls would act on the
                            // model's new step.
                            .allowsHitTesting(transition.phase == .shown)
                            // The identity goes OUTSIDE the fade: each step
                            // carries its own opacity, so the outgoing one,
                            // kept briefly while the incoming one animates in,
                            // stays at the zero opacity it left with.
                            .id(step.id)
                            .transition(StepMotion.insertion(reduceMotion))
                        Color.clear.frame(height: 1).id("bottom")
                    }
                    .frame(maxWidth: 640, alignment: .leading)
                    .padding(.horizontal, BrandSpacing.lg)
                    .padding(.vertical, BrandSpacing.lg)
                    .frame(maxWidth: .infinity)
                }
                .scrollDismissesKeyboard(.interactively)
                .onChange(of: model.step.id) { _, id in stepChanged(to: id, proxy: proxy) }
                .onChange(of: model.revealRevision) { _, _ in
                    if let text = model.announcement {
                        AccessibilityNotification.Announcement(text).post()
                    }
                    // A choice or claim step's feedback scrolls as its panel
                    // appears (`FeedbackChoreography`), not before.
                    if model.lastRevealWasFeedback, model.step.activity?.isDeterministic == true { return }
                    scrollToFeedback(proxy)
                }
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            ActionBar(model: model)
                // Unchanged: the button's label change keeps its own timing.
                .animation(Motion.resolved(.easeInOut(duration: Motion.Duration.standard),
                                           reduceMotion: reduceMotion, fallback: .none),
                           value: model.step.id)
        }
        .background(BrandColor.background.ignoresSafeArea())
        .onChange(of: transition.displayedStepId) { _, _ in headingFocused = true }
        .onChange(of: model.machine.requiredProgress.done) { _, done in
            // Progress that moves without a step change shows at once.
            if transition.phase == .shown, transition.displayedStepId == model.step.id { shownProgress = done }
        }
        .sheet(isPresented: Bindable(model).showsCrisisSupport) {
            CrisisSupportView(closeTitle: PlayerCopy.backToLesson) { model.showsCrisisSupport = false }
        }
        .onAppear { model.sceneBecameActive() }
        .onDisappear { model.sceneBecameInactive() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { model.sceneBecameActive() } else { model.sceneBecameInactive() }
        }
    }

    /// Bring the feedback into view without hiding the question.
    private func scrollToFeedback(_ proxy: ScrollViewProxy) {
        withAnimation(Motion.resolved(.easeOut(duration: Motion.Duration.standard),
                                      reduceMotion: reduceMotion, fallback: .none)) {
            proxy.scrollTo("bottom", anchor: .bottom)
        }
    }

    // MARK: Step change

    private func stepChanged(to id: String, proxy: ScrollViewProxy) {
        var next = transition
        switch next.stepChanged(to: id) {
        case .none:
            transition = next
        case .startLeaving(let generation):
            withAnimation(StepMotion.leave(reduceMotion)) { transition = next }
            leaveTask?.cancel()
            leaveTask = Task { @MainActor in
                try? await Task.sleep(for: .seconds(StepMotion.leaveDuration(reduceMotion)))
                guard !Task.isCancelled else { return }
                finishLeave(generation: generation, proxy: proxy)
            }
        case .returnToShown:
            leaveTask?.cancel()
            withAnimation(StepMotion.enter(reduceMotion)) { transition = next }
        }
    }

    /// The outgoing step is fully gone: reset the scroll while nothing is
    /// visible, then insert the incoming step and move the progress with it.
    private func finishLeave(generation: Int, proxy: ScrollViewProxy) {
        var next = transition
        guard next.leaveFinished(generation: generation) != nil else { return }
        proxy.scrollTo("top", anchor: .top)
        withAnimation(StepMotion.enter(reduceMotion)) {
            transition = next
            shownProgress = model.machine.requiredProgress.done
        }
    }
}

/// The step change's timing and distances.
enum StepMotion {
    /// How far a step moves as it leaves (left) and arrives (from the right).
    static let distance: CGFloat = 24

    static func leaveDuration(_ reduceMotion: Bool) -> TimeInterval {
        reduceMotion ? Motion.fadeHalfDuration : Motion.Duration.fast
    }
    static func leave(_ reduceMotion: Bool) -> Animation {
        reduceMotion ? Motion.fadeHalf : .easeIn(duration: Motion.Duration.fast)
    }
    static func enter(_ reduceMotion: Bool) -> Animation {
        reduceMotion ? Motion.fadeHalf : Motion.gentle
    }
    static func leaveOffset(_ reduceMotion: Bool) -> CGFloat {
        reduceMotion ? 0 : -distance
    }
    /// The incoming step arrives; the outgoing one, already invisible, is
    /// removed at once.
    static func insertion(_ reduceMotion: Bool) -> AnyTransition {
        .asymmetric(
            insertion: reduceMotion ? .opacity : .opacity.combined(with: .offset(x: distance)),
            removal: .identity)
    }
}

// MARK: - Header

struct PlayerHeader: View {
    let title: String
    let progress: (done: Int, total: Int)
    let onLeave: () -> Void
    @Environment(\.dynamicTypeSize) private var typeSize

    /// At accessibility text sizes the title and the "n of m done" line step
    /// aside (as the legacy lesson's header does), so the step itself has
    /// room. The progress bar keeps its spoken label, and each step's own
    /// heading is first in reading order.
    private var compact: Bool { typeSize.isAccessibilitySize }

    var body: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.sm) {
            HStack(alignment: .center, spacing: BrandSpacing.md) {
                Button(action: onLeave) {
                    Label(PlayerCopy.finishForNow, systemImage: "xmark")
                        .labelStyle(.iconOnly)
                        .font(BrandFont.bodyEmphasized)
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(BrandColor.textSecondary)
                .accessibilityLabel(PlayerCopy.finishForNow)
                .accessibilityHint(PlayerCopy.finishForNowHint)
                .accessibilityIdentifier("player.leave")

                if compact {
                    Spacer()
                } else {
                    Text(title)
                        .font(BrandFont.subheading)
                        .foregroundStyle(BrandColor.text)
                        .lineLimit(2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityAddTraits(.isHeader)
                }
            }
            ProgressView(value: Double(progress.done), total: Double(max(progress.total, 1)))
                .tint(BrandColor.accent)
                .accessibilityLabel(PlayerCopy.progress(progress.done, progress.total))
                .accessibilityValue("")
            if !compact {
                Text(PlayerCopy.progress(progress.done, progress.total))
                    .font(BrandFont.caption)
                    .foregroundStyle(BrandColor.textSecondary)
                    .accessibilityHidden(true)
            }
        }
        .padding(.horizontal, BrandSpacing.lg)
        .padding(.top, BrandSpacing.sm)
        .padding(.bottom, BrandSpacing.md)
        .background(BrandColor.background)
    }
}

// MARK: - Step body

struct StepBody: View {
    let model: LessonPlayerModel
    /// The step on screen, which during a step change trails `model.step`.
    let step: LessonStep
    let record: StepRecord
    var headingFocused: AccessibilityFocusState<Bool>.Binding
    var scrollToFeedback: () -> Void = {}

    var body: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.lg) {
            switch step.kind {
            case .teach(let teach):
                TeachStepView(teach: teach, headingFocused: headingFocused)
            case .activity(let activity):
                ActivityStepView(model: model, activity: activity, record: record, headingFocused: headingFocused,
                                 scrollToFeedback: scrollToFeedback)
            case .finish(let finish):
                FinishStepView(finish: finish, completion: model.machine.attempt.completion, headingFocused: headingFocused)
            }
            if !step.depth.isEmpty || model.canAskMerc {
                DepthSection(model: model, step: step, record: record)
            }
        }
    }
}

struct TeachStepView: View {
    let teach: TeachContent
    var headingFocused: AccessibilityFocusState<Bool>.Binding

    var body: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.md) {
            Text(teach.heading)
                .font(BrandFont.title)
                .foregroundStyle(BrandColor.text)
                .accessibilityAddTraits(.isHeader)
                .accessibilityFocused(headingFocused)
            Text(teach.body)
                .font(BrandFont.reading)
                .foregroundStyle(BrandColor.text)
                .fixedSize(horizontal: false, vertical: true)
            if let key = teach.keyIdea {
                KeyIdeaBox(text: key)
            }
        }
    }
}

struct KeyIdeaBox: View {
    let text: String
    var body: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.xs) {
            Label(PlayerCopy.keyIdea, systemImage: "lightbulb.fill")
                .font(BrandFont.caption.weight(.heavy))
                .foregroundStyle(BrandColor.accentText)
                .accessibilityHidden(true)
            Text(text)
                .font(BrandFont.reading.weight(.semibold))
                .foregroundStyle(BrandColor.text)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(BrandSpacing.md + 2)
        .background(BrandColor.accent.opacity(0.10), in: RoundedRectangle(cornerRadius: BrandRadius.lg, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(PlayerCopy.keyIdea): \(text)")
    }
}

/// A claim, an excerpt or a scenario, with its real/fictional label printed.
struct MaterialCard: View {
    let material: Material
    var emphasis: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.sm) {
            if let title = material.title {
                Text(title.uppercased())
                    .font(BrandFont.caption.weight(.heavy))
                    .tracking(0.8)
                    .foregroundStyle(BrandColor.textSecondary)
            }
            Text(material.text)
                .font(BrandFont.reading)
                .foregroundStyle(BrandColor.text)
                .fixedSize(horizontal: false, vertical: true)
            OriginLabel(origin: material.origin)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(BrandSpacing.md + 2)
        .background(BrandColor.surfaceElevated, in: RoundedRectangle(cornerRadius: BrandRadius.lg, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: BrandRadius.lg, style: .continuous)
                .stroke(emphasis ? BrandColor.accent : BrandColor.border, lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
    }
}

struct OriginLabel: View {
    let origin: MaterialOrigin
    var body: some View {
        switch origin {
        case .fictional:
            Label(PlayerCopy.fictional, systemImage: "theatermasks")
                .font(BrandFont.caption)
                .foregroundStyle(BrandColor.textSecondary)
        case .real(let source):
            Label(PlayerCopy.realSource(source.citation), systemImage: "checkmark.seal")
                .font(BrandFont.caption)
                .foregroundStyle(BrandColor.textSecondary)
        }
    }
}

// MARK: - Finish

struct FinishStepView: View {
    let finish: FinishContent
    let completion: CompletionRecord?
    var headingFocused: AccessibilityFocusState<Bool>.Binding
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.lg) {
            HStack {
                Spacer()
                MercMascot(.celebrate, size: 120, idleLife: !reduceMotion)
                    .accessibilityHidden(true)
                Spacer()
            }
            Text(finish.heading)
                .font(BrandFont.title)
                .foregroundStyle(BrandColor.text)
                .accessibilityAddTraits(.isHeader)
                .accessibilityFocused(headingFocused)
            VStack(alignment: .leading, spacing: BrandSpacing.xs) {
                Text(PlayerCopy.youPracticed)
                    .font(BrandFont.caption.weight(.heavy))
                    .foregroundStyle(BrandColor.accentText)
                Text(finish.practiced)
                    .font(BrandFont.reading)
                    .foregroundStyle(BrandColor.text)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityElement(children: .combine)
            if let success = completion?.success, let line = PlayerCopy.success(success) {
                Text(line)
                    .font(BrandFont.body)
                    .foregroundStyle(BrandColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            VStack(alignment: .leading, spacing: BrandSpacing.xs) {
                Text(PlayerCopy.upNext)
                    .font(BrandFont.caption.weight(.heavy))
                    .foregroundStyle(BrandColor.accentText)
                Text(finish.next)
                    .font(BrandFont.body)
                    .foregroundStyle(BrandColor.text)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityElement(children: .combine)
        }
    }
}
