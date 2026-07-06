import SwiftUI
import DesignSystem
import NetworkingKit
import PersistenceKit

/// A curriculum lesson in its OWN window — distinct from the four chat modes,
/// and not a tab. It owns a **persisted but non-hydrating** `ChatViewModel`
/// (built via `ChatViewModel.makeLesson`): the thread is saved under a
/// curriculum-tagged conversation so the lesson can be **resumed**, but it never
/// hydrates from — nor surfaces in — the main chat history.
///
/// On appear it either **resumes** a saved conversation (`resumeConversationId`)
/// or sends the lesson's `[CURRICULUM: …]` starter BEHIND THE SCENES — the user
/// never sees the raw prompt, only Mercurius teaching. Completion is **not**
/// "opened": it's reported by the server when the student demonstrates
/// proficiency (`[LESSON_COMPLETE]` → `model.onLessonComplete`), surfaced here
/// via the `onLessonComplete` callback.
public struct CurriculumLessonView: View {
    private let lessonId: String
    private let unitLabel: String
    private let lessonNumber: Int
    private let title: String
    private let objective: String
    private let starter: String
    /// Non-nil → resume this saved conversation instead of starting fresh.
    private let resumeConversationId: UUID?
    /// Fired once when a NEW lesson conversation is created (lessonId, convoId),
    /// so the host can record the in-progress → resume mapping.
    private let onStarted: (String, UUID) -> Void
    /// Fired when the server reports proficiency this turn (lessonId).
    private let onLessonComplete: (String) -> Void
    private let onExit: () -> Void
    /// The next lesson in this unit (drives the celebration's "Next lesson"
    /// CTA). Nil = this is the unit's last lesson.
    private let nextLessonNumber: Int?
    private let nextLessonTitle: String?
    /// Advance to the next lesson — the host swaps the presented lesson.
    private let onAdvanceToNext: () -> Void
    /// Unit progress for the header bar (lessons completed / total in this unit).
    private let completedInUnit: Int
    private let totalInUnit: Int

    @State private var model: ChatViewModel
    @State private var didBegin = false
    @State private var showReportConfirmation = false
    @State private var showCelebration = false
    @State private var didCelebrate = false
    /// Speech-bubble intro shown before a FRESH lesson starts (skipped on resume).
    @State private var showIntro = false
    /// Transient lesson-progress reaction shown in the coach card (non-modal).
    @State private var coachReaction: CoachReaction?
    /// Highest progress value already reacted to (persisted per unit), so the same
    /// value never re-triggers a reaction on re-render / re-entry.
    @State private var lastReactedProgress: Int
    @State private var reactionClearTask: Task<Void, Never>?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(
        lessonId: String,
        unitLabel: String,
        lessonNumber: Int,
        title: String,
        objective: String,
        starter: String,
        resumeConversationId: UUID?,
        apiClient: APIClient,
        sessionIdentity: SessionIdentity,
        chatStore: ChatStore?,
        streakStore: StreakStore? = nil,
        achievementStore: AchievementStore? = nil,
        onStarted: @escaping (String, UUID) -> Void,
        onLessonComplete: @escaping (String) -> Void,
        onExit: @escaping () -> Void,
        nextLessonNumber: Int? = nil,
        nextLessonTitle: String? = nil,
        onAdvanceToNext: @escaping () -> Void = {},
        completedInUnit: Int = 0,
        totalInUnit: Int = 0
    ) {
        self.lessonId = lessonId
        self.unitLabel = unitLabel
        self.lessonNumber = lessonNumber
        self.title = title
        self.objective = objective
        self.starter = starter
        self.resumeConversationId = resumeConversationId
        self.onStarted = onStarted
        self.onLessonComplete = onLessonComplete
        self.onExit = onExit
        self.nextLessonNumber = nextLessonNumber
        self.nextLessonTitle = nextLessonTitle
        self.onAdvanceToNext = onAdvanceToNext
        self.completedInUnit = completedInUnit
        self.totalInUnit = totalInUnit
        // Fresh lessons open on the speech-bubble intro; resumed ones skip it.
        _showIntro = State(initialValue: resumeConversationId == nil)
        // Seed the de-dupe high-water mark, CLAMPED to the current count. This
        // means progress earned before this feature shipped (no key yet) — or
        // before a progress reset (count now below the stored mark) — is treated
        // as already-acknowledged, so it never fires a stale reaction. Only NEW
        // progress, first seen on a later lesson, reacts. Re-persisting the
        // clamped value also self-heals a stale mark after a reset.
        let unit = lessonId.split(separator: "_").first.map(String.init) ?? lessonId
        let progressKey = "merc.coach.progress." + unit
        let storedProgress = UserDefaults.standard.object(forKey: progressKey) as? Int
        let baseline = min(storedProgress ?? completedInUnit, completedInUnit)
        UserDefaults.standard.set(baseline, forKey: progressKey)
        _lastReactedProgress = State(initialValue: baseline)
        // Persisted (for resume) but non-hydrating + invisible to chat history.
        _model = State(initialValue: ChatViewModel.makeLesson(
            apiClient: apiClient,
            sessionIdentity: sessionIdentity,
            store: chatStore,
            streakStore: streakStore,
            achievementStore: achievementStore
        ))
    }

    public var body: some View {
        ZStack(alignment: .top) {
            BrandColor.background.ignoresSafeArea()

            VStack(spacing: 0) {
                header
                Divider().overlay(BrandColor.border)

                // Merc as the lesson's coach — large, fully visible, and out of
                // the composer's way (replaces the old peek behind the input bar).
                // Live activity keeps the coach in sync with the conversation
                // (thinking pulse while a reply streams; antics only at rest).
                MercCoachCard(line: coachLine, reaction: coachReaction,
                              liveActivity: coachActivity)

                MessageListView(
                    messages: model.messages,
                    phase: model.phase,
                    onRetry: { model.retry() },
                    onExplainMore: { model.explainMore() },
                    onReport: { message in
                        model.reportMessage(message)
                        showReportConfirmation = true
                    },
                    lessonStyle: true
                )

                // Clean, fixed composer — nothing tucked behind it.
                ChatInputBar(
                    text: Binding(get: { model.draft }, set: { model.draft = $0 }),
                    isSending: isSending,
                    attachedImageData: model.pendingImageData,
                    onSend: { model.send() },
                    onCancel: { model.cancel() },
                    onAttachImage: { model.attachImage(data: $0) },
                    onRemoveAttachment: { model.clearAttachment() },
                    useBrandSend: true,
                    backgroundFade: true
                )
            }

            if showCelebration {
                LessonCompleteOverlay(
                    lessonTitle: title,
                    nextLessonNumber: nextLessonNumber,
                    nextLessonTitle: nextLessonTitle,
                    reduceMotion: reduceMotion,
                    onNext: { onAdvanceToNext() },
                    onBackToLessons: {
                        model.cancel()
                        onExit()
                    },
                    onDismiss: {
                        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) { showCelebration = false }
                    }
                )
                .transition(.opacity)
                .zIndex(1)
            }

            if showIntro {
                lessonIntro
                    .transition(.opacity)
                    .zIndex(2)
            }
        }
        // Resume a saved thread immediately; a FRESH lesson waits behind the
        // speech-bubble intro and starts when the student taps Continue.
        .task { if resumeConversationId != nil { await beginOrResume() } }
        #if DEBUG
        .onAppear {
            if ProcessInfo.processInfo.arguments.contains("-ForceCelebrate") {
                showIntro = false
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { showCelebration = true }
            }
        }
        #endif
        // The lesson was passed (server flag or a pass marker) → celebrate ONCE.
        // Not again if the student dismissed it to re-read feedback and then
        // re-demonstrates proficiency in the same thread (a fresh lesson gets a
        // fresh view via `.id`, so `didCelebrate` resets there).
        .onChange(of: model.lessonCompletionEvents) { _, count in
            guard count > 0, !showCelebration, !didCelebrate else { return }
            didCelebrate = true
            withAnimation(reduceMotion ? nil : .spring(response: 0.5, dampingFraction: 0.8)) {
                showCelebration = true
            }
        }
        // INTERMEDIATE progress reacts cleanly on lesson ENTRY (when the learner
        // opens the next lesson) — never buried under the completion overlay. Only
        // the FINAL completion reacts live, as a celebratory echo of the
        // LessonCompleteOverlay that fires at the same moment.
        .onChange(of: completedInUnit) { _, new in
            if totalInUnit > 0, new >= totalInUnit { maybeReactToProgress(new) }
        }
        .onAppear {
            // Resumed lessons reveal content immediately, so react on entry. Fresh
            // lessons react from `startFromIntro` once the intro is dismissed.
            if !showIntro { reactToProgressOnEntry() }
        }
        .alert("Reported", isPresented: $showReportConfirmation) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("Thanks — we'll review this response.")
        }
    }

    /// Start the lesson the first time the view appears: resume the saved
    /// conversation if we have one (and it still exists), otherwise begin a fresh
    /// curriculum conversation and report it for the in-progress mapping.
    private func beginOrResume() async {
        guard !didBegin else { return }
        didBegin = true
        model.onLessonComplete = { onLessonComplete(lessonId) }

        if let resumeId = resumeConversationId {
            let resumed = await model.resumeLesson(conversationId: resumeId, starter: starter)
            if resumed { return }
            // Saved conversation is gone (history reset / pruned) — start fresh.
        }
        if let convoId = model.beginLessonConversation(starter: starter) {
            onStarted(lessonId, convoId)
        }
    }

    /// A short, contextual coaching line — Merc framing the lesson's objective in
    /// the first person ("I'll help you …"). Falls back to a generic line.
    private var coachLine: String {
        let goal = objective.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !goal.isEmpty else {
            return "I'll guide you through this — then check what landed."
        }
        let lowered = goal.prefix(1).lowercased() + goal.dropFirst()
        return "I'll help you " + lowered
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text("\(unitLabel) · Lesson \(lessonNumber)".uppercased())
                    .font(.system(size: 11, weight: .heavy, design: .rounded))
                    .tracking(0.4)
                    .foregroundStyle(BrandColor.accent)
                Spacer(minLength: BrandSpacing.sm)
                Button("Done") {
                    model.cancel()
                    onExit()
                }
                .font(.system(size: 15, weight: .heavy, design: .rounded))
                .foregroundStyle(BrandColor.accent)
                .accessibilityLabel("Done. Exit lesson.")
            }
            Text(title)
                .font(.system(size: 22, weight: .black, design: .rounded))
                .foregroundStyle(BrandColor.text)
                .fixedSize(horizontal: false, vertical: true)
            if totalInUnit > 0 { progressBar.padding(.top, 2) }
        }
        .padding(.horizontal, 22)
        .padding(.top, BrandSpacing.md)
        .padding(.bottom, BrandSpacing.md)
    }

    private var progressBar: some View {
        HStack(spacing: 9) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(BrandColor.accent.opacity(0.16))
                    Capsule()
                        .fill(BrandGradient.mercHorizontal)
                        .frame(width: max(0, min(geo.size.width, geo.size.width * progressFraction)))
                }
            }
            .frame(height: 8)
            Text("\(completedInUnit)/\(totalInUnit)")
                .font(.system(size: 12, weight: .heavy, design: .rounded))
                .foregroundStyle(BrandColor.accent)
                .monospacedDigit()
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Unit progress: \(completedInUnit) of \(totalInUnit) lessons complete")
    }

    private var progressFraction: CGFloat {
        guard totalInUnit > 0 else { return 0 }
        return min(1, CGFloat(completedInUnit) / CGFloat(totalInUnit))
    }

    // MARK: - Speech-bubble intro

    private var lessonIntro: some View {
        ZStack {
            BrandColor.background.ignoresSafeArea()
            VStack(alignment: .leading, spacing: 0) {
                Text("\(unitLabel) · Lesson \(lessonNumber)".uppercased())
                    .font(.system(size: 11, weight: .heavy, design: .rounded))
                    .tracking(0.4)
                    .foregroundStyle(BrandColor.accent)
                    .padding(.horizontal, 24)
                    .padding(.top, 24)

                Spacer()

                introSpeechBubble
                    .padding(.horizontal, 24)
                    .padding(.bottom, 14)

                ZStack(alignment: .bottomTrailing) {
                    HStack {
                        MercMascot(.wave, size: 150).accessibilityHidden(true)
                        Spacer()
                    }
                    Button(action: startFromIntro) {
                        Text("Continue")
                            .font(.system(size: 15, weight: .heavy, design: .rounded))
                            .foregroundStyle(.white)
                            .padding(.vertical, 14)
                            .padding(.horizontal, 28)
                            .background(BrandGradient.merc, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                            .shadow(color: BrandColor.accent.opacity(0.5), radius: 12, y: 7)
                    }
                    .padding(.bottom, 16)
                    .accessibilityLabel("Continue. Start the lesson.")
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 20)
            }
        }
    }

    private var introSpeechBubble: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 17, weight: .black, design: .rounded))
                .foregroundStyle(BrandColor.text)
                .fixedSize(horizontal: false, vertical: true)
            Text("Ready to dig in? I'll walk you through it — then check what landed.")
                .font(.system(size: 13.5, weight: .bold, design: .rounded))
                .foregroundStyle(BrandColor.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(BrandColor.surface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(alignment: .bottomLeading) {
            Rectangle()
                .fill(BrandColor.surface)
                .frame(width: 16, height: 16)
                .rotationEffect(.degrees(45))
                .offset(x: 42, y: 8)
        }
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(BrandColor.accent.opacity(0.16), lineWidth: 2)
        )
        .shadow(color: .black.opacity(0.12), radius: 18, y: 12)
    }

    private func startFromIntro() {
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.25)) { showIntro = false }
        reactToProgressOnEntry()   // now that the lesson content is visible
        Task { await beginOrResume() }
    }

    // MARK: - Lesson-progress reaction

    /// Per-unit key for the persisted de-dupe high-water mark.
    private var progressDefaultsKey: String {
        let unit = lessonId.split(separator: "_").first.map(String.init) ?? lessonId
        return "merc.coach.progress." + unit
    }

    /// On entering a lesson, acknowledge INTERMEDIATE progress only — the
    /// completion case is owned by the live `onChange` + the LessonCompleteOverlay,
    /// so we never double-fire it here.
    private func reactToProgressOnEntry() {
        guard !(totalInUnit > 0 && completedInUnit >= totalInUnit) else { return }
        maybeReactToProgress(completedInUnit)
    }

    /// Fire a coach reaction only when the visible progress counter reaches a NEW
    /// high (≥ 1). De-dupes via the persisted `lastReactedProgress`, so the same
    /// value never re-triggers — on re-render, re-entry, or relaunch.
    private func maybeReactToProgress(_ value: Int) {
        guard value >= 1, value > lastReactedProgress else { return }
        lastReactedProgress = value
        UserDefaults.standard.set(value, forKey: progressDefaultsKey)
        presentReaction(completed: value, total: totalInUnit)
    }

    /// Show the reaction briefly, then clear it — mood/activity come from the
    /// centralized helper; the copy is lesson-specific.
    private func presentReaction(completed: Int, total: Int) {
        let resolved = MercMascotState.lessonProgress(completed: completed, total: total)
        let next = CoachReaction(
            copy: progressCopy(completed: completed, total: total),
            mood: resolved.mood,
            activity: resolved.activity
        )
        reactionClearTask?.cancel()
        coachReaction = next   // copy snaps; Merc's pop carries the motion

        let hold = resolved.duration ?? 2.2
        reactionClearTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(hold))
            guard !Task.isCancelled else { return }
            coachReaction = nil
        }
    }

    /// Short reaction copy keyed to the step reached (completion gets its own line).
    private func progressCopy(completed: Int, total: Int) -> String {
        if total > 0 && completed >= total {
            return "Lesson complete. You can explain this now."
        }
        switch completed {
        case 1:  return "Nice start. You've got the core idea."
        case 2:  return "Good — now connect it to a real-world example."
        case 3:  return "Halfway there. Watch for the safety angle."
        case 4:  return "Almost done. One more concept to lock in."
        default: return "Nice progress — keep it going."
        }
    }

    private var isSending: Bool {
        switch model.phase {
        case .sending, .streaming: return true
        case .idle, .failed: return false
        }
    }

    /// Live activity for the coach card: thinking while a reply is being
    /// produced, speaking while it streams, at rest otherwise.
    private var coachActivity: MercActivity {
        switch model.phase {
        case .sending:   return .aiThinking
        case .streaming: return .aiSpeaking
        case .idle, .failed: return .idle
        }
    }
}
