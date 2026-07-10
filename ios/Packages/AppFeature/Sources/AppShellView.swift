import SwiftUI
import DesignSystem
import ChatFeature
import CurriculumFeature
import MercuriusActivity
import NetworkingKit
import PersistenceKit
import SettingsFeature
import EngagementFeature

/// The TabView host. Owns the selected-tab binding and, crucially, a
/// single shared `ChatViewModel` so switching tabs doesn't wipe the
/// conversation — and so lessons tapped in the Curriculum tab can
/// push a starter message into the existing chat.
///
/// Four tab-bar items:
/// - **Chat** and **Curriculum** are real navigation destinations.
/// - **New Chat** and **History** are *action* tab items: tapping
///   them fires a side effect (start a fresh conversation; present
///   the history sheet) and immediately reverts selection to the
///   previous tab. Pattern matches Instagram-style "+" buttons in
///   the tab bar — non-destinations rendered alongside destinations
///   because the user model is "common actions live in the bottom
///   bar."
/// - Settings stays as a sheet accessible from the Chat tab's
///   header; a leading Home button in the chat header returns the
///   user to the branded `HomeView`.
struct AppShellView: View {

    // MARK: - Dependencies (from AppEnvironment)

    let apiClient: APIClient
    let sessionIdentity: SessionIdentity
    let chatStore: ChatStore?
    let themeStore: ThemePreferenceStore
    let streakStore: StreakStore
    let achievementStore: AchievementStore
    let reminderStore: ReminderStore

    /// Called when the user taps the Home button in the chat header.
    /// `AppEntryView` wires this to flip `hasEnteredApp` back to
    /// false, which returns the user to `HomeView`.
    let onGoHome: @MainActor () -> Void

    // MARK: - Shared state

    @State private var selectedTab: Tab
    @State private var chatModel: ChatViewModel
    @State private var progress = CurriculumProgressStore()

    /// Drives presentation of the Chat History sheet. Set to true by
    /// the `.history` tab-action; cleared by the row tap or the
    /// Close toolbar button.
    @State private var showChatHistory: Bool = false

    /// Drives the Progress hub sheet (streak / achievements),
    /// opened from the streak chip in the chat header.
    @State private var showProgress: Bool = false

    /// Wraps UNUserNotificationCenter for the daily reminder.
    @State private var scheduler = NotificationScheduler()

    @Environment(\.scenePhase) private var scenePhase

    /// Standby gamification (quiet progress) cache. Default-constructed, so
    /// `clientEnabled` is false — it makes no network calls and renders nothing
    /// unless the feature is explicitly turned on (client + server flags).
    @State private var gamificationStore = GamificationStore()

    /// The lesson currently presented in its own full-screen curriculum window
    /// (separate from the chat tab and the four modes). nil when none is open.
    @State private var activeLesson: Lesson?

    /// The unit whose cumulative unit test is presented full-screen. nil when
    /// none is open. Qualified because Foundation also exports a `Unit` type.
    @State private var activeUnitTest: CurriculumFeature.Unit?

    enum Tab: Hashable {
        case chat
        case history       // action: present chat-history sheet
        case newChat       // action: startNewConversation()
        case curriculum
    }

    /// Re-plan the outside-app reminder window from current state. The
    /// scheduler no-ops when the toggle is off or permission is missing.
    private func refreshReminders() {
        scheduler.refresh(
            enabled: reminderStore.enabled,
            hour: reminderStore.hour,
            minute: reminderStore.minute,
            streak: streakStore.isCurrentFresh ? streakStore.current : nil,
            chattedToday: streakStore.confirmedToday
        )
    }

    init(
        apiClient: APIClient,
        sessionIdentity: SessionIdentity,
        chatStore: ChatStore?,
        themeStore: ThemePreferenceStore,
        streakStore: StreakStore,
        achievementStore: AchievementStore,
        reminderStore: ReminderStore,
        initialTab: Tab = .chat,
        onGoHome: @escaping @MainActor () -> Void
    ) {
        self.apiClient = apiClient
        self.sessionIdentity = sessionIdentity
        self.chatStore = chatStore
        self.themeStore = themeStore
        self.streakStore = streakStore
        self.achievementStore = achievementStore
        self.reminderStore = reminderStore
        self.onGoHome = onGoHome
        // The Home screen's CTAs route here: "Chat with Merc" → .chat,
        // "Start learning" → .curriculum. Fresh @State each entry (the shell
        // leaves the tree when the user goes Home), so this always applies.
        _selectedTab = State(initialValue: initialTab)
        _chatModel = State(
            initialValue: ChatViewModel(
                apiClient: apiClient,
                sessionIdentity: sessionIdentity,
                store: chatStore,
                streakStore: streakStore,
                achievementStore: achievementStore
            )
        )
    }

    // MARK: - Body

    var body: some View {
        TabView(selection: $selectedTab) {
            chatTab
                .tabItem { Label("Chat", systemImage: "bubble.left.and.bubble.right") }
                .tag(Tab.chat)

            // The History tab is an action — the body just mirrors
            // the chat tab's content so the visual transition during
            // tap-then-revert doesn't flash empty. The sheet
            // attached below the TabView is what the user actually
            // sees once `showChatHistory` flips on.
            chatTab
                .tabItem { Label("History", systemImage: "clock.arrow.circlepath") }
                .tag(Tab.history)

            // Same pattern: action tab. `square.and.pencil` is the
            // standard iOS "compose / new" symbol — recognizable.
            chatTab
                .tabItem { Label("New Chat", systemImage: "square.and.pencil") }
                .tag(Tab.newChat)

            curriculumTab
                .tabItem { Label("Curriculum", systemImage: "book") }
                .tag(Tab.curriculum)
        }
        .tint(BrandColor.accent)
        .onChange(of: selectedTab) { oldValue, newValue in
            handleSelection(from: oldValue, to: newValue)
        }
        // Keep the reminder window current (rotating Merc copy + streak
        // defense): re-plan when the app changes foreground state and after
        // every chat that touches the streak — chatting today replaces the
        // pending "streak on the line" alert, and a streak change re-stamps
        // the number before it could go stale.
        .onChange(of: scenePhase) { _, _ in refreshReminders() }
        .onChange(of: streakStore.lastUpdatedAt) { _, _ in refreshReminders() }
        // (`-NotifPreview` fires from RootView's always-mounted root, since the
        // app opens on Home and this shell isn't in the tree until a CTA tap.)
        // A started lesson opens in its OWN full-screen curriculum window — not
        // the chat tab, not a new mode. The starter prompt is sent behind the
        // scenes (see CurriculumLessonView / ChatViewModel.beginLesson).
        // `fullScreenCover` is iOS-only; the app ships for iOS, and macOS is
        // just the SPM test host (where the lesson window isn't presented).
#if os(iOS)
        .fullScreenCover(item: $activeLesson) { lesson in
            let next = MercuriusCurriculum.lesson(after: lesson.id)
            let parentUnit = MercuriusCurriculum.units.first(where: { $0.lessons.contains(lesson) })
            CurriculumLessonView(
                lessonId: lesson.id,
                unitLabel: unitLabel(for: lesson),
                lessonNumber: lesson.number,
                title: lesson.title,
                objective: lesson.objective,
                starter: lesson.starter,
                resumeConversationId: progress.resumeConversationId(for: lesson.id),
                apiClient: apiClient,
                sessionIdentity: sessionIdentity,
                chatStore: chatStore,
                streakStore: streakStore,
                achievementStore: achievementStore,
                onStarted: { lessonId, convoId in
                    progress.markInProgress(lessonId, conversationId: convoId)
                    // Explorer is "Started a structured curriculum lesson"
                    // (Achievement.swift) — award it at start, matching the
                    // copy and the web widget's semantics. Idempotent.
                    achievementStore.award(AchievementCatalog.explorer)
                    // Surface the session on the Lock Screen / Dynamic Island.
                    // Started here (not on open) so it only appears once a
                    // conversation actually exists; re-starting on a later
                    // lesson simply replaces the running activity.
                    startLearningActivity(for: lessonId)
                },
                onLessonComplete: { lessonId in
                    handleLessonComplete(lessonId)
                },
                onExit: { activeLesson = nil },
                nextLessonNumber: next?.number,
                nextLessonTitle: next?.title,
                onAdvanceToNext: { if let next { activeLesson = next } },
                completedInUnit: parentUnit.map { progress.completedCount(in: $0) } ?? 0,
                totalInUnit: parentUnit?.lessons.count ?? 0
            )
            // Swapping `activeLesson` to the next lesson must give a FRESH view
            // (new ChatViewModel + re-run of `beginOrResume`), not reuse this
            // one's @State. Keying on the lesson id forces that re-identity.
            .id(lesson.id)
            // Toasts need a presenter in THIS layer too: the cover renders
            // above the shell's presenter, so awards fired while the lesson
            // window is up (Explorer, streak milestones) would otherwise
            // auto-clear unseen behind it.
            .achievementToasts(achievementStore)
        }
#endif
        .sheet(isPresented: $showChatHistory) {
            // Wrapped in NavigationStack so ChatHistoryView gets
            // its title bar + filter pill chrome.
            NavigationStack {
                ChatHistoryView(
                    load: { chatModel.archivedConversations() },
                    onSelect: { id in
                        showChatHistory = false
                        // The thread opens in the Chat tab — land the user
                        // there even if they browsed history from another
                        // tab (otherwise the open is invisible).
                        selectedTab = .chat
                        // Defer the open slightly so the sheet
                        // dismissal animation runs cleanly before
                        // the chat thread re-renders behind it.
                        Task { @MainActor in
                            try? await Task.sleep(for: .milliseconds(200))
                            await chatModel.openConversation(id: id)
                        }
                    },
                    onDelete: { id in
                        chatModel.deleteConversation(id: id)
                    }
                )
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Close") { showChatHistory = false }
                            .accessibilityHint("Closes the chat history list")
                    }
                }
            }
            .tint(BrandColor.accent)
        }
        .sheet(isPresented: $showProgress) {
            ProgressHubView(
                streakStore: streakStore,
                achievementStore: achievementStore,
                reminderStore: reminderStore,
                scheduler: scheduler,
                gamificationStore: gamificationStore,
                onDone: { showProgress = false }
            )
            .tint(BrandColor.accent)
        }
        // Achievement-unlocked toasts surface over the whole shell.
        .achievementToasts(achievementStore)
        // Brief, factual progress nudges (standby; inert unless the feature is on).
        .progressNudge(gamificationStore)
        // Seed the streak from the server so it shows before the first chat.
        .task {
            chatModel.configureGamification(store: gamificationStore, provider: apiClient)
            await seedStreakOnLaunch()
            await refreshGamificationOnLaunch()
        }
    }

    /// Fetch the server's authoritative streak once on launch to seed the cache.
    private func seedStreakOnLaunch() async {
        guard let sid = try? sessionIdentity.current() else { return }
        if let snapshot = try? await apiClient.sessionStreak(sessionId: sid) {
            // `seed`, not `update`: the session row's streak is only recomputed
            // when the user chats, so a lapsed user's row can be weeks stale —
            // freshness must come from the row's own `last_session_date`, not
            // from when we happened to fetch it, or the Home greeting would
            // claim a dead streak is alive.
            streakStore.seed(streak: snapshot.streak, lastSessionDate: snapshot.lastSessionDate)
        }
    }

    /// Refresh the standby gamification cache on launch. A no-op — and no
    /// network call — unless the client gate is on (see `GamificationStore`),
    /// so the default build's launch behavior is unchanged.
    private func refreshGamificationOnLaunch() async {
        guard let sid = try? sessionIdentity.current() else { return }
        await gamificationStore.refresh(using: apiClient, sessionId: sid)
        // Credit the daily return (idempotent per UTC day; server caps at 1/day).
        // No-op unless the feature is on — recordEvent is gated in the store.
        let today = String(ISO8601DateFormatter().string(from: Date()).prefix(10))
        await gamificationStore.recordEvent(
            using: apiClient, sessionId: sid,
            reason: .dailyReturn, sourceType: "daily", sourceId: today
        )
    }

    // MARK: - Tab selection

    /// Tab-bar tap handler. Real navigation tabs (`.chat`,
    /// `.curriculum`) just pass through. Action tabs (`.history`,
    /// `.newChat`) fire their side effect and revert `selectedTab`
    /// to wherever the user was before — so the action tab never
    /// stays "selected." Reverting triggers another `onChange` whose
    /// `newValue` is one of the real tabs, which falls through the
    /// switch with no further action — no infinite loop.
    private func handleSelection(from oldValue: Tab, to newValue: Tab) {
        switch newValue {
        case .history:
            showChatHistory = true
            selectedTab = oldValue == .history ? .chat : oldValue
        case .newChat:
            chatModel.startNewConversation()
            selectedTab = oldValue == .newChat ? .chat : oldValue
        case .chat, .curriculum:
            break
        }
    }

    // MARK: - Tabs

    private var chatTab: some View {
        ChatView(
            model: chatModel,
            apiClient: apiClient,
            sessionIdentity: sessionIdentity,
            achievementStore: achievementStore,
            settingsPresenter: { [sessionIdentity, themeStore, chatStore, chatModel,
                                  streakStore, achievementStore, progress] in
                AnyView(
                    SettingsSheet(
                        sessionIdentity: sessionIdentity,
                        themeStore: themeStore,
                        chatStore: chatStore,
                        chatModel: chatModel,
                        // "Start Over" must also clear the on-device engagement
                        // + curriculum caches — they describe the OLD identity
                        // (streak, badges, resume pointers into deleted
                        // conversations) and would otherwise survive the reset.
                        streakStore: streakStore,
                        achievementStore: achievementStore,
                        progress: progress
                    )
                )
            },
            headerAccessory: {
                AnyView(StreakChip(streakStore: streakStore, action: { showProgress = true }))
            },
            onGoHome: onGoHome
        )
    }

    private var curriculumTab: some View {
        CurriculumView(
            progress: progress,
            onStartLesson: handleStartLesson,
            onStartUnitTest: handleStartUnitTest,
            // The gamified stats bar is composed here at the app root — the
            // curriculum feature can't depend on EngagementFeature (layering),
            // so it's injected through the path's top-bar slot. Streak is always
            // live; XP/level appear only when the gamification feature is on.
            topBar: {
                GamifiedTopBar(
                    streakStore: streakStore,
                    gamificationStore: gamificationStore,
                    onOpenProfile: { showProgress = true }
                )
            }
        )
#if os(iOS)
        .fullScreenCover(item: $activeUnitTest) { unit in
            unitTestCover(for: unit)
                // Same as the lesson cover: Unit Master is awarded while this
                // cover is up, so its toast needs a presenter in this layer.
                .achievementToasts(achievementStore)
        }
#endif
    }

    // MARK: - Unit test

    /// Curriculum tapped a unit's test → present it full-screen (separate from
    /// the lesson cover). All four lessons are already complete — the row is
    /// locked otherwise.
    private func handleStartUnitTest(_ unit: CurriculumFeature.Unit) {
        activeUnitTest = unit
    }

    /// The student passed a unit test → mark the unit mastered + award the
    /// badge. Idempotent, so a duplicate callback is harmless. The curriculum
    /// stays fully open — mastery is a checkpoint, not a gate.
    private func handleUnitMastered(_ unitId: String) {
        progress.markUnitMastered(unitId)
        achievementStore.award(AchievementCatalog.unitMaster)
        // Credit module completion (idempotent per unit). Gated/no-op when off.
        if let sid = try? sessionIdentity.current() {
            Task {
                await gamificationStore.recordEvent(
                    using: apiClient, sessionId: sid,
                    reason: .moduleCompleted, sourceType: "unit_test", sourceId: unitId
                )
            }
        }
    }

#if os(iOS)
    /// Builds the unit-test cover: looks up the unit's authored test and wires
    /// the server-backed defense grader. Falls back to a dismissable message if
    /// the test is somehow missing (every unit ships one, so this is defensive).
    @ViewBuilder
    private func unitTestCover(for unit: CurriculumFeature.Unit) -> some View {
        if let test = MercuriusCurriculum.unitTest(for: unit.id) {
            UnitTestView(
                unit: unit,
                test: test,
                gradeDefense: { answer in
                    let sid = try sessionIdentity.current()
                    let dto: UnitDefenseResult
                    do {
                        dto = try await apiClient.gradeUnitDefense(
                            sessionId: sid,
                            unitId: unit.id,
                            unitTitle: unit.title,
                            defensePrompt: test.defensePrompt,
                            answer: answer
                        )
                    } catch APIError.unknown(let underlying) where underlying == "HTTP 404" {
                        // The deployed server can predate `/api/unit-test/grade`
                        // (the client ships ahead of backend deploys). Translate
                        // the 404 into the typed "grading unavailable" error so
                        // the student sees an honest message instead of a
                        // connection error that no amount of retrying can fix.
                        throw DefenseGradingError.unavailable
                    }
                    // Derive pass from the letter grade on-device too, so a
                    // malformed server `pass` flag can't mark a C/D as passed.
                    let g = dto.grade.uppercased()
                    return UnitTestViewModel.DefenseResult(
                        grade: dto.grade,
                        pass: g == "A" || g == "B",
                        feedback: dto.feedback
                    )
                },
                onMastered: { unitId in handleUnitMastered(unitId) },
                onExit: { activeUnitTest = nil }
            )
        } else {
            VStack(spacing: BrandSpacing.md) {
                Text("This unit test isn't available right now.")
                    .font(BrandFont.body)
                    .foregroundStyle(BrandColor.text)
                Button("Done") { activeUnitTest = nil }
                    .font(BrandFont.bodyEmphasized)
                    .foregroundStyle(BrandColor.accent)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(BrandColor.background.ignoresSafeArea())
        }
    }
#endif

    // MARK: - Lesson launch

    /// Curriculum tapped a lesson → open it in its own full-screen window
    /// (`.fullScreenCover` on `activeLesson`). The starter prompt is sent behind
    /// the scenes by `CurriculumLessonView`; the main chat tab is untouched.
    private func handleStartLesson(_ lesson: Lesson) {
        // Open-only. The lesson is NOT complete on open — it becomes "in
        // progress" once its conversation is created (the lesson view's
        // `onStarted` callback records the resume mapping), and only flips to
        // complete when the server reports demonstrated proficiency
        // (`handleLessonComplete`, below).
        activeLesson = lesson
    }

    /// The server signalled demonstrated proficiency (`[LESSON_COMPLETE]`).
    /// Mark the lesson complete + award the milestones. All idempotent, so a
    /// duplicate marker (or a later re-review) is harmless. We deliberately do
    /// NOT auto-dismiss the lesson window — the student reads the final feedback
    /// and taps Done; the curriculum row updates underneath them.
    private func handleLessonComplete(_ lessonId: String) {
        progress.markCompleted(lessonId)
        achievementStore.award(AchievementCatalog.explorer)
        // Push the fresh count into the Live Activity (after markCompleted so
        // it reads the new state). The unit's last lesson completes the
        // activity — the win lingers on the Lock Screen.
        refreshLearningActivity(afterCompleting: lessonId)
        // Credit module completion (idempotent per lesson id). Gated/no-op off.
        if let sid = try? sessionIdentity.current() {
            Task {
                await gamificationStore.recordEvent(
                    using: apiClient, sessionId: sid,
                    reason: .moduleCompleted, sourceType: "lesson", sourceId: lessonId
                )
            }
        }
    }

    // MARK: - Live Activity

    /// Start the learning Live Activity for the lesson's unit. Framed as
    /// streak defense: the ring tracks lessons-in-unit and the countdown runs
    /// to the end of the local day — the same window the reminders defend.
    /// No-ops when the parent unit can't be resolved or the user has Live
    /// Activities off (the controller checks authorization).
    private func startLearningActivity(for lessonId: String) {
#if os(iOS)
        guard let unit = parentUnit(of: lessonId) else { return }
        LearningActivityController.shared.startSession(
            title: "Unit \(unit.number) · \(unit.title)",
            state: learningState(in: unit)
        )
#endif
    }

    /// After a completion lands: last lesson in the unit → `complete`
    /// (lingering win); otherwise `update` with the new counts. Both no-op
    /// when no activity is running.
    private func refreshLearningActivity(afterCompleting lessonId: String) {
#if os(iOS)
        guard let unit = parentUnit(of: lessonId) else { return }
        let state = learningState(in: unit)
        if state.lessonsDone >= state.lessonsTotal {
            LearningActivityController.shared.complete(state: state)
        } else {
            LearningActivityController.shared.update(state: state)
        }
#endif
    }

    private func parentUnit(of lessonId: String) -> CurriculumFeature.Unit? {
        MercuriusCurriculum.units.first { $0.lessons.contains(where: { $0.id == lessonId }) }
    }

#if os(iOS)
    /// Snapshot the unit's progress into the activity's content state.
    /// "Level" is the gamified framing of units: finishing unit N unlocks
    /// level N+1, so `lessonsToLevel` is simply the lessons left in the unit.
    private func learningState(in unit: CurriculumFeature.Unit) -> LearningActivityAttributes.ContentState {
        let total = unit.lessons.count
        let done = progress.completedCount(in: unit)
        let endOfDay = Calendar.current.date(
            byAdding: .day, value: 1,
            to: Calendar.current.startOfDay(for: Date())
        ) ?? Date().addingTimeInterval(3600)
        return .init(
            phase: .active,
            lessonsDone: done,
            lessonsTotal: total,
            progress: total > 0 ? Double(done) / Double(total) : 0,
            streakCount: streakStore.current,
            level: (Int(unit.number) ?? 0) + 1,
            lessonsToLevel: max(total - done, 0),
            deadline: endOfDay,
            lastUpdated: Date()
        )
    }
#endif

    /// "UNIT 0X" label for the lesson's parent unit, for the lesson header.
    private func unitLabel(for lesson: Lesson) -> String {
        if let unit = MercuriusCurriculum.units.first(where: { $0.lessons.contains(lesson) }) {
            return "UNIT \(unit.number)"
        }
        return "CURRICULUM"
    }
}
