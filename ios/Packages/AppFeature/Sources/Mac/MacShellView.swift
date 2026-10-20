#if os(macOS)
import SwiftUI
import DesignSystem
import ChatFeature
import CurriculumFeature
import EngagementFeature
import NetworkingKit
import PersistenceKit
import SettingsFeature

/// The Mac window: a `NavigationSplitView` whose sidebar is Today, the path
/// by unit and the chats, and whose detail column hosts the same views the
/// iPhone shows — Merc's welcome (`HomeView`), a unit's stretch of the path
/// (`CurriculumView`), the chat (`ChatView`), a lesson
/// (`CurriculumLessonView`), a unit check (`UnitTestView`) — and, before
/// anything else, the consent gate / first run (`OnboardingFlow`).
///
/// The Mac counterpart of `AppShellView`. `AppEntryView` mounts it for the
/// whole post-bootstrap life of the window and hands it the gate while the
/// gate shows, so the gate decision, the reminder re-plan and the consent
/// withdrawal stay the one shared implementation.
///
/// **No network before consent.** While `gate` is non-nil the detail column
/// is the gate, the sidebar is collapsed with its toggle removed (and
/// disabled, should it be revealed), the menu commands are off
/// (`MacShellModel.isGated`), and the tasks that reach the server — the
/// progress pull, the Progress hub's refresh — only run once it is nil.
struct MacShellView: View {
    @EnvironmentObject private var env: AppEnvironment
    @Bindable var shell: MacShellModel

    /// The consent gate / first-run flow while it shows; nil once consent is
    /// current.
    let gate: AnyView?

    /// The entry view's reminder scheduler (it owns the re-plan), shared with
    /// the Progress hub and Settings.
    let scheduler: NotificationScheduler

    /// Settings' "withdraw consent": the entry view puts the gate back.
    let onConsentWithdrawn: @MainActor () -> Void

    /// Today's one-time weekly-nudge offer (the iPhone Home's card), decided
    /// by the entry view as on iOS.
    var todayReminders = MacTodayReminders.hidden

    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    /// Standby gamification cache — default-constructed, so the client gate
    /// is off: no network calls and nothing rendered (as on iOS).
    @State private var gamificationStore = GamificationStore()

    /// A saved thread waiting on the delete confirmation.
    @State private var pendingDelete: ConversationSummary?

    /// The DEBUG launch-argument state has been applied (once per window).
    @State private var appliedDebugState = false

    private var isGated: Bool { gate != nil }

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            MacSidebar(
                shell: shell,
                progress: env.progressStore,
                onDelete: { pendingDelete = $0 }
            )
            .disabled(isGated)
            // On the sidebar column, where the split view reads it: no way
            // to reveal the (empty, disabled) sidebar while the gate shows.
            .toolbar(removing: isGated ? .sidebarToggle : nil)
            // Outermost: under `.toolbar(removing:)` the split view ignored
            // it and opened the sidebar at 148 pt.
            .navigationSplitViewColumnWidth(min: 210, ideal: 250, max: 340)
        } detail: {
            detail
                .frame(minWidth: 520, minHeight: 480)
                // The shared views' buttons are drawn by the views
                // themselves; the Mac's default push-button bezel put grey
                // boxes around their icons and labels.
                .buttonStyle(.borderless)
        }
        .tint(BrandColor.accent)
        // While Settings erases this student's data nothing here may start
        // a request: it would go out under the old ID.
        .disabled(shell.isErasing)
        .onAppear {
            shell.onConsentWithdrawn = onConsentWithdrawn
            applyGate(isGated)
        }
        .onChange(of: isGated) { _, gated in applyGate(gated) }
        // Past the gate: the same launch work the iOS shell runs. The launch
        // hold never fetches before consent, and neither does this.
        .task(id: isGated) {
            guard !isGated else { return }
            shell.refreshConversations()
            shell.chatModel.configureGamification(store: gamificationStore, provider: env.apiClient)
            applyDebugStateIfNeeded()
            presentPendingLesson()
            await env.progressSync.pullOnLaunch()
        }
        .onChange(of: env.pendingLessonId) { _, _ in presentPendingLesson() }
        // Completion, mastery and merges move `revision`; the sync debounces
        // them into one PUT.
        .onChange(of: env.progressStore.revision) { _, _ in
            guard !isGated else { return }
            env.progressSync.pushSoon()
        }
        .sheet(isPresented: $shell.showsProgress) {
            ProgressHubView(
                streakStore: env.streakStore,
                achievementStore: env.achievementStore,
                reminderStore: env.reminderStore,
                scheduler: scheduler,
                gamificationStore: gamificationStore,
                nextLessonId: env.progressStore.frontierLessonId,
                onDone: { shell.showsProgress = false }
            )
            .frame(minWidth: 460, idealWidth: 520, minHeight: 560, idealHeight: 680)
            .tint(BrandColor.accent)
        }
        .confirmationDialog(
            "Delete this chat?",
            isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
            presenting: pendingDelete
        ) { conversation in
            Button("Delete Chat", role: .destructive) { shell.deleteConversation(conversation.id) }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text("It's removed from this Mac. This can't be undone.")
        }
        .achievementToasts(env.achievementStore)
        .progressNudge(gamificationStore)
    }

    // MARK: - Detail

    @ViewBuilder private var detail: some View {
        if let gate {
            // The flow is laid out for a phone: on a wide window its lines
            // and buttons stay at a readable width, centred.
            gate
                .frame(maxWidth: 720)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(BrandColor.background)
                .navigationTitle("Welcome to Mercurius")
        } else if let debugPreview = debugDetailPreview {
            debugPreview
        } else if let lesson = shell.activeLesson {
            lessonView(lesson)
                // A new lesson (the celebration's "Next lesson") is a fresh
                // view: a new lesson chat and a re-run of its start.
                .id(lesson.id)
        } else if let unit = shell.activeUnitTest {
            unitTestView(unit)
                .id(unit.id)
        } else {
            switch shell.selection ?? .today {
            case .today:
                todayView
            case .unit(let unitId):
                unitPath(unitId)
                    .id(unitId)
            case .chat:
                chatView
            }
        }
    }

    private var todayView: some View {
        let state = HomeState.build(
            // Only a streak the server confirmed recently (as Home on iOS).
            streak: env.streakStore.isCurrentFresh ? env.streakStore.current : 0,
            progress: env.progressStore
        )
        return HomeView(
            state: state,
            onStartNext: { shell.open(state.next) },
            onStartChat: { shell.showChat() },
            // The same one-time weekly-nudge offer as the iPhone's Home: the
            // Mac schedules the same reminders.
            showsReminderCard: todayReminders.shows,
            onAcceptReminders: todayReminders.onAccept,
            onDismissReminderCard: todayReminders.onDismiss
        )
        .navigationTitle("Today")
    }

    private func unitPath(_ unitId: String) -> some View {
        CurriculumView(
            progress: env.progressStore,
            unitId: unitId,
            onStartLesson: { shell.openLesson($0) },
            onStartUnitTest: { shell.openUnitTest($0) },
            topBar: {
                GamifiedTopBar(
                    streakStore: env.streakStore,
                    gamificationStore: gamificationStore,
                    onOpenProfile: { shell.showsProgress = true },
                    onGoHome: { shell.show(.today) }
                )
            }
        )
    }

    private var chatView: some View {
        let model = shell.chatModel
        return ChatView(
            model: model,
            apiClient: env.apiClient,
            sessionIdentity: env.sessionIdentity,
            achievementStore: env.achievementStore,
            // No Settings or Home buttons in the chat: Settings is ⌘, and
            // Today is a sidebar row. The streak chip goes in the toolbar.
            headerAccessory: { [env, shell] in
                AnyView(StreakChip(streakStore: env.streakStore, action: { shell.showsProgress = true }))
            }
        )
        .macChrome(onNewChat: { shell.newChat() }, modeRequest: $shell.modeRequest)
        .navigationTitle("Chat")
        .navigationSubtitle("\(model.currentMode.displayName) mode")
        .onChange(of: model.phase) { _, phase in
            if phase == .sending { env.lastActivityStore.touch() }
            // A finished turn may have saved a new thread (or renamed one).
            if phase == .idle { shell.refreshConversations() }
        }
        .onChange(of: model.conversationId) { _, id in
            // New Chat, a reset or a delete moved the thread: keep the
            // sidebar's highlight on it.
            if case .chat = shell.selection { shell.selection = .chat(id) }
            shell.refreshConversations()
        }
    }

    // MARK: - Lesson

    private func lessonView(_ lesson: Lesson) -> some View {
        let progress = env.progressStore
        let next = AppShellView.resolvedNextStop(after: lesson.id, progress: progress)
        let unit = MercuriusCurriculum.unit(containingLesson: lesson.id)
        return CurriculumLessonView(
            lessonId: lesson.id,
            unitLabel: unit.map { "UNIT \($0.number)" } ?? "CURRICULUM",
            lessonNumber: lesson.number,
            title: lesson.title,
            objective: lesson.objective,
            starter: lesson.starter,
            resumeConversationId: Self.debugResumeOverride ?? progress.resumeConversationId(for: lesson.id),
            apiClient: env.apiClient,
            sessionIdentity: env.sessionIdentity,
            chatStore: env.chatStore,
            streakStore: env.streakStore,
            achievementStore: env.achievementStore,
            onStarted: { lessonId, conversationId in
                progress.markInProgress(lessonId, conversationId: conversationId)
                // "Started a structured curriculum lesson" — at start, as on
                // iOS. Idempotent.
                env.achievementStore.award(AchievementCatalog.explorer)
            },
            onLessonComplete: { handleLessonComplete($0) },
            onExit: { shell.closeActivity() },
            onAdvanceToNext: { advance(to: next) },
            completedInUnit: unit.map { progress.completedCount(in: $0) } ?? 0,
            totalInUnit: unit?.lessons.count ?? 0,
            nextStop: next.map(AppShellView.celebrationStop)
        )
        .navigationTitle("Lesson \(lesson.number) · \(lesson.title)")
    }

    /// The celebration's primary button: the next lesson replaces this one;
    /// an unlocked unit check opens; otherwise back to the unit's page.
    private func advance(to stop: MercuriusCurriculum.PathStop?) {
        switch stop {
        case .lesson(let lesson):
            shell.openLesson(lesson)
        case .unitTest(let unit) where env.progressStore.isUnitTestUnlocked(unit):
            shell.openUnitTest(unit)
        case .unitTest, nil:
            shell.closeActivity()
        }
    }

    /// The server reported proficiency (`[LESSON_COMPLETE]`): the same
    /// bookkeeping as `AppShellView.handleLessonComplete`, minus the Live
    /// Activity (iOS only) and the App Store review prompt (not wired on the
    /// Mac yet). All idempotent.
    private func handleLessonComplete(_ lessonId: String) {
        env.progressStore.markCompleted(lessonId)
        env.lastActivityStore.touch()
        env.achievementStore.award(AchievementCatalog.explorer)
        recordModuleCompleted(sourceType: "lesson", sourceId: lessonId)
    }

    // MARK: - Unit check

    @ViewBuilder
    private func unitTestView(_ unit: CurriculumFeature.Unit) -> some View {
        if let test = MercuriusCurriculum.unitTest(for: unit.id) {
            UnitTestView(
                unit: unit,
                test: test,
                gradeDefense: { [env] answer in
                    let sid = try env.sessionIdentity.current()
                    // Crisis → support, 404 → unavailable, other API errors →
                    // their own copy (shared with iOS).
                    return try await UnitDefenseGrading.grade {
                        try await env.apiClient.gradeUnitDefense(
                            sessionId: sid,
                            unitId: unit.id,
                            unitTitle: unit.title,
                            defensePrompt: test.defensePrompt,
                            answer: answer
                        )
                    }
                },
                onMastered: { handleUnitMastered($0) },
                onExit: { shell.closeActivity() }
            )
            .navigationTitle("Unit \(Int(unit.number) ?? 0) check")
        } else {
            VStack(spacing: BrandSpacing.md) {
                Text("This unit test isn't available right now.")
                    .font(BrandFont.body)
                    .foregroundStyle(BrandColor.text)
                Button("Done") { shell.closeActivity() }
                    .font(BrandFont.bodyEmphasized)
                    .foregroundStyle(BrandColor.accentText)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(BrandColor.background)
        }
    }

    /// The student passed a unit check (as `AppShellView.handleUnitMastered`).
    private func handleUnitMastered(_ unitId: String) {
        env.progressStore.markUnitMastered(unitId)
        env.lastActivityStore.touch()
        env.achievementStore.award(AchievementCatalog.unitMaster)
        recordModuleCompleted(sourceType: "unit_test", sourceId: unitId)
    }

    /// Credit a finished module. A no-op unless gamification is on.
    private func recordModuleCompleted(sourceType: String, sourceId: String) {
        guard let sid = try? env.sessionIdentity.current() else { return }
        let store = gamificationStore
        let client = env.apiClient
        Task {
            await store.recordEvent(using: client, sessionId: sid,
                                    reason: .moduleCompleted, sourceType: sourceType, sourceId: sourceId)
        }
    }

    // MARK: - Gate, reminders' lessons

    private func applyGate(_ gated: Bool) {
        shell.setGated(gated)
        columnVisibility = gated ? .detailOnly : .all
    }

    /// A lesson a reminder or a `mercurius://lesson/<id>` link asked for.
    /// Unknown or still-locked ids land on their unit's page (or Today).
    private func presentPendingLesson() {
        guard !isGated, let lessonId = env.pendingLessonId else { return }
        env.pendingLessonId = nil
        guard let unit = MercuriusCurriculum.unit(containingLesson: lessonId),
              let lesson = unit.lessons.first(where: { $0.id == lessonId })
        else {
            shell.show(.today)
            return
        }
        guard env.progressStore.isLessonUnlocked(lesson, in: unit) else {
            shell.show(.unit(unit.id))
            return
        }
        if shell.activeLesson?.id != lessonId {
            shell.openLesson(lesson)
        }
    }

    // MARK: - DEBUG launch arguments

    /// DEBUG: the unit test's whole-screen previews, in the detail column
    /// (`-UnitTestCrisisPreview`: the crisis support view, reached through
    /// the real grading path with no network; `-UnitTestPreview` with
    /// `-UnitTestStage <stage>`).
    private var debugDetailPreview: AnyView? {
        #if DEBUG
        let args = ProcessInfo.processInfo.arguments
        guard let unit = MercuriusCurriculum.units.first,
              let test = MercuriusCurriculum.unitTest(for: unit.id) else { return nil }
        if args.contains("-UnitTestCrisisPreview") {
            return AnyView(UnitTestCrisisPreviewHost(unit: unit, test: test,
                                                     via503: args.contains("-CrisisVia503"))
                .navigationTitle("Unit 1 check"))
        }
        if args.contains("-UnitTestPreview") {
            return AnyView(UnitTestPreviewHost(unit: unit, test: test,
                                               stage: UserDefaults.standard.string(forKey: "UnitTestStage"))
                .navigationTitle("Unit 1 check"))
        }
        #endif
        return nil
    }

    /// DEBUG: a fake resume id skips a fresh lesson's speech-bubble intro
    /// (`-LessonSkipIntro`, as iOS's `-LessonPreview`); it falls through to a
    /// fresh start, so with `-LessonReplay` the recorded replies stream in.
    private static var debugResumeOverride: UUID? {
        #if DEBUG
        ProcessInfo.processInfo.arguments.contains("-LessonSkipIntro") ? UUID() : nil
        #else
        nil
        #endif
    }

    /// DEBUG: the states iOS reaches with launch arguments, inside the Mac
    /// shell (the gate still comes first, as on iOS):
    /// - `-EnterShell` → Today (the Mac has no Home doorman; Today is it).
    /// - `-EnterShellCurriculum` → the next stop's unit page.
    /// - `-LessonPreview` → Unit 1, Lesson 1 in the detail column. Add
    ///   `-LessonReplay` for the recorded replies (no network) and
    ///   `-LessonSkipIntro` to start it straight away.
    /// - `-ChatPreview` → the chat; `-ChatSeed` also sends a starter (this
    ///   one does reach the server).
    private func applyDebugStateIfNeeded() {
        #if DEBUG
        guard !appliedDebugState else { return }
        appliedDebugState = true
        let args = ProcessInfo.processInfo.arguments
        if args.contains("-LessonPreview"), let lesson = MercuriusCurriculum.units.first?.lessons.first {
            shell.openLesson(lesson)
        } else if args.contains("-ChatPreview") {
            shell.showChat()
            if args.contains("-ChatSeed"), shell.chatModel.messages.isEmpty {
                shell.chatModel.draft = "What is a token in an LLM?"
                shell.chatModel.send()
            }
        } else if args.contains("-EnterShellCurriculum") {
            shell.showPath()
        } else if args.contains("-EnterShell") {
            shell.show(.today)
        }
        #endif
    }
}

/// Today's weekly-nudge card: whether it shows and what its buttons do —
/// the iPhone Home's card, decided the same way (`ReminderCardStore.shows`).
struct MacTodayReminders {
    let shows: Bool
    let onAccept: () -> Void
    let onDismiss: () -> Void

    static let hidden = MacTodayReminders(shows: false, onAccept: {}, onDismiss: {})
}

/// Settings with the Mac shell's wiring, for the Settings window
/// (`MacSettingsView`).
@MainActor
func settingsSheet(
    env: AppEnvironment,
    shell: MacShellModel,
    scheduler: NotificationScheduler,
    onConsentWithdrawn: (@MainActor () -> Void)?
) -> SettingsSheet {
    SettingsSheet(
        sessionIdentity: env.sessionIdentity,
        themeStore: env.themeStore,
        chatStore: env.chatStore,
        chatModel: shell.chatModel,
        streakStore: env.streakStore,
        achievementStore: env.achievementStore,
        progress: env.progressStore,
        progressSync: env.progressSync,
        reminderStore: env.reminderStore,
        scheduler: scheduler,
        sessionDeleter: env.apiClient,
        onConsentWithdrawn: onConsentWithdrawn,
        afterReset: { shell.refreshConversations() }
    )
}
#endif
