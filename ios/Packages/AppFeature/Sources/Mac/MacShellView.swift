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

    /// The sidebar was folded away because the window got narrow (not by
    /// the student), so it comes back when the window is wide again.
    @State private var collapsedForWidth = false
    /// The window's last width, for re-applying the rule as the gate clears.
    @State private var windowWidth: CGFloat = 0

    /// Standby gamification cache — default-constructed, so the client gate
    /// is off: no network calls and nothing rendered (as on iOS).
    @State private var gamificationStore = GamificationStore()

    /// A saved thread waiting on the delete confirmation.
    @State private var pendingDelete: ConversationSummary?

    /// The DEBUG launch-argument state has been applied (once per window).
    @State private var appliedDebugState = false

    private var isGated: Bool { gate != nil }

    /// The detail column's narrowest: the chat's toolbar (mode picker,
    /// Explain More, New Chat) and a lesson's reading column still fit, and
    /// with the sidebar's minimum it stays under the window's 700 pt.
    static let detailMinWidth: CGFloat = 430

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
            // it and opened the sidebar at 148 pt. The sidebar's minimum
            // plus the detail's (`detailMinWidth`) plus the floating
            // sidebar's insets must stay under the window's 700 pt minimum,
            // or the window's content overflows it and is cut off at both
            // edges (measured at 700 pt with 210 + 480).
            .navigationSplitViewColumnWidth(min: 200, ideal: 240, max: 340)
        } detail: {
            detail
                .frame(minWidth: Self.detailMinWidth, minHeight: 480)
                // The shared views' buttons are drawn by the views
                // themselves; the Mac's default push-button bezel put grey
                // boxes around their icons and labels.
                .buttonStyle(.borderless)
                // Night Studio's toolbar: the system's glass on macOS 26,
                // the canvas colour before it (SPEC.md §2.8).
                .nightToolbarBackground()
        }
        // Night's prominent indigo for the system controls (7.9:1 under
        // white, where `accent` was 4.47:1).
        .tint(Night.prominent)
        // A narrow window (tiled beside a browser) folds the sidebar away,
        // as Mail and Notes do, so the detail keeps its whole toolbar; ⌃⌘S
        // or the toolbar button brings it back. Widening the window again
        // restores a sidebar that was folded this way.
        .background {
            GeometryReader { geo in
                Color.clear
                    .onAppear { resized(to: geo.size.width) }
                    .onChange(of: geo.size.width) { _, width in resized(to: width) }
            }
        }
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
            guard !isGated, Self.debugTodayDemoStreak == nil else { return }
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
            .tint(Night.prominent)
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
                // Each step sizes itself to its content, centred, with its
                // button right under it (`GateStepContainer`); the box keeps
                // lines to a readable length and a tall window from
                // stretching a step that scrolls.
                .frame(maxWidth: MacLayout.gateWidth, maxHeight: 700)
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

    /// Today: an overview of the next stop, the week, a question to think
    /// through and the recent chats (`MacTodayView`), on the same
    /// `HomeState` as the iPhone's Home.
    private var todayView: some View {
        let state = HomeState.build(
            // Only a streak the server confirmed recently (as Home on iOS).
            streak: Self.debugTodayDemoStreak
                ?? (env.streakStore.isCurrentFresh ? env.streakStore.current : 0),
            progress: env.progressStore
        )
        return MacTodayView(
            state: state,
            progress: env.progressStore,
            conversations: shell.conversations,
            // The same one-time weekly-nudge offer as the iPhone's Home: the
            // Mac schedules the same reminders.
            reminders: todayReminders,
            onOpenNext: { shell.open(state.next) },
            onOpenPath: { shell.showPath() },
            onOpenChat: { shell.show(.chat($0)) },
            onNewChat: { shell.newChat() },
            onShowProgress: { shell.showProgress() },
            chatMode: shell.currentChatMode,
            onThinkItThrough: { shell.newChat(draft: $0) }
        )
        .toolbar {
            ToolbarItem(placement: .navigation) {
                MacProgressButton { shell.showProgress() }
            }
        }
    }

    /// A unit's stretch of the path. The iPhone pins its stats bar above the
    /// path (with a Home button); on the Mac Progress is a toolbar button,
    /// as in the chat, and Today is a sidebar row.
    private func unitPath(_ unitId: String) -> some View {
        CurriculumView(
            progress: env.progressStore,
            unitId: unitId,
            onStartLesson: { shell.openLesson($0) },
            onStartUnitTest: { shell.openUnitTest($0) }
        )
        .toolbar {
            ToolbarItem(placement: .navigation) {
                MacProgressButton { shell.showProgress() }
            }
        }
    }

    private var chatView: some View {
        let model = shell.chatModel
        return ChatView(
            model: model,
            apiClient: env.apiClient,
            sessionIdentity: env.sessionIdentity,
            achievementStore: env.achievementStore,
            // No Settings or Home buttons in the chat: Settings is ⌘, and
            // Today is a sidebar row. Progress goes in the toolbar (Night
            // Studio keeps the streak's number off the chrome).
            headerAccessory: { [shell] in
                AnyView(MacProgressButton { shell.showProgress() })
            }
        )
        .macChrome(onNewChat: { shell.newChat() }, modeRequest: $shell.modeRequest)
        // No subtitle: the toolbar's mode picker already says the mode, and
        // the room keeps the picker out of the overflow menu down to the
        // window's 700 pt minimum with the sidebar showing.
        .navigationTitle("Chat")
        .onChange(of: model.phase) { _, phase in
            if phase == .sending { env.lastActivityStore.touch() }
            // A finished turn may have saved a new thread (or renamed one).
            if phase == .idle { shell.refreshConversations() }
        }
        .onChange(of: model.conversationId) { _, id in
            // New Chat, a reset or a delete moved the thread: keep the
            // sidebar's highlight on it. Not while the sidebar's thread opens
            // are queued: an older open landing must not pull the highlight
            // back from the newer pick (`MacShellModel.route`).
            if case .chat = shell.selection, !shell.isOpeningThread { shell.selection = .chat(id) }
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
            nextStop: next.map(AppShellView.celebrationStop),
            // Settings' erasure stops this lesson's reply in flight.
            onRegisterStop: { shell.registerLessonStop($0) }
        )
        // The lesson sets the window's title, subtitle and way back itself.
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
            // The check sets the window's title, subtitle and way back.
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
        collapsedForWidth = false
        if !gated { resized(to: windowWidth) }
    }

    private func resized(to width: CGFloat) {
        windowWidth = width
        guard !isGated, width > 0 else { return }
        let next = Self.sidebarAfterResize(width: width, visibility: columnVisibility,
                                           collapsedForWidth: collapsedForWidth)
        if next.visibility != columnVisibility { columnVisibility = next.visibility }
        collapsedForWidth = next.collapsedForWidth
    }

    /// Below this window width the sidebar folds away by itself: the chat's
    /// toolbar (mode picker, Explain More, New Chat) needs the detail's
    /// whole width there.
    nonisolated static let sidebarFoldWidth: CGFloat = 860

    /// The sidebar after the window changes width: folded below
    /// `sidebarFoldWidth` (remembering that the width did it), and back once
    /// the window is wide again — unless the student folded it.
    nonisolated static func sidebarAfterResize(
        width: CGFloat,
        visibility: NavigationSplitViewVisibility,
        collapsedForWidth: Bool
    ) -> (visibility: NavigationSplitViewVisibility, collapsedForWidth: Bool) {
        if width < sidebarFoldWidth {
            if visibility == .detailOnly { return (visibility, collapsedForWidth) }
            return (.detailOnly, true)
        }
        if collapsedForWidth { return (.all, false) }
        return (visibility, false)
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
                                                     via503: args.contains("-CrisisVia503")))
        }
        if args.contains("-UnitTestPreview") {
            return AnyView(UnitTestPreviewHost(unit: unit, test: test,
                                               stage: UserDefaults.standard.string(forKey: "UnitTestStage")))
        }
        #endif
        return nil
    }

    /// DEBUG `-TodayDemo YES` (screenshots of Today with a week in it): a
    /// 4-day streak shown without touching the streak store, and — in the
    /// `-UITests` progress suite, which is emptied at every launch — Unit 1's
    /// first two lessons finished this week (one on the week's second day,
    /// one today) with Lesson 3 opened. Its progress is never pushed.
    private static var debugTodayDemoStreak: Int? {
        #if DEBUG
        let args = ProcessInfo.processInfo.arguments
        return args.contains("-TodayDemo") && args.contains("-UITests") ? 4 : nil
        #else
        nil
        #endif
    }

    private func seedTodayDemo() {
        #if DEBUG
        guard let unit = MercuriusCurriculum.units.first, unit.lessons.count >= 3 else { return }
        let now = Date()
        let calendar = Calendar.current
        let weekStart = WeeklyPlan.compute(progress: env.progressStore, now: now, calendar: calendar).weekStart
        let secondDay = calendar.date(byAdding: .hour, value: 34, to: weekStart) ?? weekStart
        let first = min(secondDay, now.addingTimeInterval(-2 * 3600))
        let second = now.addingTimeInterval(-30 * 60)
        env.progressStore.merge(
            completed: [unit.lessons[0].id, unit.lessons[1].id],
            mastered: [],
            remoteVersion: MercuriusCurriculum.version,
            remoteUpdatedAt: [unit.lessons[0].id: first, unit.lessons[1].id: second]
        )
        env.progressStore.markOpened(unit.lessons[2].id)
        #endif
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
    ///   one does reach the server). `-ChatPreviewMode debate|discussion`
    ///   then switches modes the way the toolbar picker and ⌥⌘2/⌥⌘3 do: the
    ///   mode's one-time description first, unless seen
    ///   (`-seenAllModeDescriptions YES`), then the server is asked — so a
    ///   screenshot run needs a local server that answers `POST /api/mode`.
    private func applyDebugStateIfNeeded() {
        #if DEBUG
        guard !appliedDebugState else { return }
        appliedDebugState = true
        let args = ProcessInfo.processInfo.arguments
        if Self.debugTodayDemoStreak != nil {
            seedTodayDemo()
        }
        if args.contains("-UnitTestCrisisPreview") || args.contains("-UnitTestPreview"),
           let unit = MercuriusCurriculum.units.first {
            // The previews show Unit 1's check: its row, as the real check's.
            shell.selection = .unit(unit.id)
        } else if args.contains("-LessonPreview"), let lesson = MercuriusCurriculum.units.first?.lessons.first {
            shell.openLesson(lesson)
        } else if args.contains("-ChatPreview") {
            shell.showChat()
            if args.contains("-ChatSeed"), shell.chatModel.messages.isEmpty {
                shell.chatModel.draft = "What is a token in an LLM?"
                shell.chatModel.send()
            }
            if let raw = UserDefaults.standard.string(forKey: "ChatPreviewMode"),
               let mode = ChatMode(rawValue: raw) {
                shell.requestMode(mode)
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
        // The Settings window can erase while a lesson or unit check is open
        // in the main window (on the iPhone Settings can't be reached then):
        // its reply in flight stops before the server delete, and the
        // lesson closes, so nothing of the erased session stays on screen or
        // goes back to the server under the new ID.
        beforeErase: { shell.beforeSettingsErase() },
        afterReset: { shell.afterSettingsReset() }
    )
}
#endif
