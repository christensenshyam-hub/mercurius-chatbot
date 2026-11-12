import SwiftUI
import DesignSystem

/// The interactive lesson player: one step at a time, one clear task, one
/// primary action (Check answer, then Continue), short feedback, and a way to
/// leave and come back. Text scrolls at every size; nothing essential is
/// clipped to fit one screen.
public struct LessonPlayerView: View {
    @State private var model: LessonPlayerModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @AccessibilityFocusState private var headingFocused: Bool

    public init(model: LessonPlayerModel) {
        _model = State(initialValue: model)
    }

    public var body: some View {
        VStack(spacing: 0) {
            PlayerHeader(
                title: model.content.title,
                progress: model.machine.requiredProgress,
                onLeave: model.leave
            )
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: BrandSpacing.lg) {
                        Color.clear.frame(height: 0).id("top")
                        StepBody(model: model, headingFocused: $headingFocused)
                            .id(model.step.id)
                            .transition(reduceMotion ? .opacity : .asymmetric(
                                insertion: .move(edge: .trailing).combined(with: .opacity),
                                removal: .opacity))
                        Color.clear.frame(height: 1).id("bottom")
                    }
                    .frame(maxWidth: 640, alignment: .leading)
                    .padding(.horizontal, BrandSpacing.lg)
                    .padding(.vertical, BrandSpacing.lg)
                    .frame(maxWidth: .infinity)
                }
                .scrollDismissesKeyboard(.interactively)
                // A new step starts at its top, not where the last one was
                // scrolled to.
                .onChange(of: model.step.id) { _, _ in proxy.scrollTo("top", anchor: .top) }
                .onChange(of: model.revealRevision) { _, _ in
                    if let text = model.announcement {
                        AccessibilityNotification.Announcement(text).post()
                    }
                    // Bring the feedback into view without hiding the question.
                    withAnimation(reduceMotion ? nil : .easeOut(duration: 0.25)) {
                        proxy.scrollTo("bottom", anchor: .bottom)
                    }
                }
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            ActionBar(model: model)
        }
        .background(BrandColor.background.ignoresSafeArea())
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.25), value: model.step.id)
        .onChange(of: model.step.id) { _, _ in headingFocused = true }
        .sheet(isPresented: Bindable(model).showsCrisisSupport) {
            CrisisSupportView(closeTitle: PlayerCopy.backToLesson) { model.showsCrisisSupport = false }
        }
        .onAppear { model.sceneBecameActive() }
        .onDisappear { model.sceneBecameInactive() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { model.sceneBecameActive() } else { model.sceneBecameInactive() }
        }
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
    var headingFocused: AccessibilityFocusState<Bool>.Binding

    var body: some View {
        let step = model.step
        VStack(alignment: .leading, spacing: BrandSpacing.lg) {
            switch step.kind {
            case .teach(let teach):
                TeachStepView(teach: teach, headingFocused: headingFocused)
            case .activity(let activity):
                ActivityStepView(model: model, activity: activity, headingFocused: headingFocused)
            case .finish(let finish):
                FinishStepView(finish: finish, completion: model.machine.attempt.completion, headingFocused: headingFocused)
            }
            if !step.depth.isEmpty || model.canAskMerc {
                DepthSection(model: model, step: step)
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
