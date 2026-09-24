import SwiftUI
import DesignSystem
import NetworkingKit
import ChatFeature
import CurriculumFeature
import EngagementFeature
import SettingsFeature

/// Post-bootstrap entry flow. Owns the consent gate / first-run flow and
/// the Home → AppShell handoff so that `RootView` can stay focused on
/// bootstrap concerns (session resolve, container readiness). Always
/// mounted once bootstrap is ready, so it also owns the reminder re-plan
/// and the routing of tapped reminders.
///
/// Three mutually exclusive states:
///
/// 1. **Gate** — the stored `consentVersion` is older than
///    `ConsentGate.currentVersion`, or `!hasSeenOnboarding`. `OnboardingFlow`
///    runs in `.full` mode on a first run and `.gateOnly` for an existing
///    install (a version bump or a consent withdrawal in Settings). It
///    writes both flags through `@AppStorage`; the shared UserDefaults
///    values propagate here automatically. This branch is evaluated FIRST
///    so no network call can happen before consent: the launch hold only
///    fetches when consent is already current, and everything else that
///    talks to the server waits for the gate to clear.
///
/// 2. **Home** — gate cleared, `!hasEnteredApp`. The branded entry screen
///    with the next-stop and Chat with Merc CTAs.
///
/// 3. **App shell** — `hasEnteredApp`. The main `TabView`. Shown once the
///    user taps a CTA (or finishes the full first-run flow, which routes
///    straight in), or on a cold launch within `LaunchResume.window` of the
///    student's last activity. The chat header carries a Home button that
///    flips `hasEnteredApp` back to false so the user always has a way back.
///
/// The animations are declared once at this view's root so the
/// child views can each use a bare `.transition(.opacity)` and
/// get a consistent crossfade.
struct AppEntryView: View {
    @EnvironmentObject private var env: AppEnvironment

    @AppStorage(OnboardingFlow.storageKey) private var hasSeenOnboarding: Bool = false
    @AppStorage(ConsentGate.storageKey) private var consentVersion: Int = 0

    /// The flow completed in this launch. The persisted flags decide at
    /// launch; this covers the same launch, because a value pinned through
    /// the UserDefaults argument domain (`-consentVersion 0` in the UI
    /// tests) shadows the flow's own writes for the whole process.
    @State private var gateClearedThisLaunch = false

    private var showsGate: Bool {
        Self.showsGate(
            consentVersion: consentVersion,
            hasSeenOnboarding: hasSeenOnboarding,
            clearedThisLaunch: gateClearedThisLaunch
        )
    }

    /// Pure gate decision (covered by AppEntryGateTests).
    static func showsGate(consentVersion: Int, hasSeenOnboarding: Bool, clearedThisLaunch: Bool) -> Bool {
        !clearedThisLaunch
            && (ConsentGate.needsGate(storedVersion: consentVersion) || !hasSeenOnboarding)
    }

    /// The gate decision for a launch, read from the same defaults
    /// `@AppStorage` reads (argument domain included).
    static func gateShowsAtLaunch(defaults: UserDefaults = .standard) -> Bool {
        showsGate(
            consentVersion: defaults.integer(forKey: ConsentGate.storageKey),
            hasSeenOnboarding: defaults.bool(forKey: OnboardingFlow.storageKey),
            clearedThisLaunch: false
        )
    }

    /// Flips true when the user taps a CTA on HomeView. In-memory only: a
    /// cold launch starts at Home — Merc greets the learner rather than
    /// dropping them mid-conversation — unless they were active moments ago
    /// (`resumeTab`), in which case it picks up where they were.
    /// DEBUG `-EnterShell` / `-EnterShellCurriculum` skip the Home doorman
    /// so screenshot tooling can reach the shell (no CLI way to tap CTAs).
    @State private var hasEnteredApp: Bool

    /// Which tab the shell should open on — set by the Home CTA the user
    /// chose ("Chat with Merc" → .chat, the next stop → .curriculum).
    @State private var entryTab: AppShellView.Tab

    /// The stop the shell should open on arrival — the first-run flow's
    /// "Start Lesson 1" or Home's next-stop CTA. Cleared when the user goes
    /// Home so a later "Chat with Merc" doesn't re-open it.
    @State private var entryLesson: Lesson?
    @State private var entryUnitTest: CurriculumFeature.Unit?

    /// Re-plans the reminders; shared with the shell's Progress hub.
    @State private var scheduler = NotificationScheduler()
    @Environment(\.scenePhase) private var scenePhase

    /// Whether iOS would still show its notification prompt (the reminder
    /// card is only offered then). Nil until checked.
    @State private var canAskForNotifications: Bool?

    /// - Parameter resumeTab: the tab to reopen on this cold launch
    ///   (`LaunchResume`), or nil to start at Home.
    init(resumeTab: AppShellView.Tab? = nil) {
        let debugShell = Self.debugEntersShell
        _hasEnteredApp = State(initialValue: debugShell || resumeTab != nil)
        _entryTab = State(initialValue: Self.debugEntersCurriculum ? .curriculum : (resumeTab ?? .chat))
    }

    private static var debugEntersShell: Bool {
        #if DEBUG
        let args = ProcessInfo.processInfo.arguments
        return args.contains("-EnterShell") || args.contains("-EnterShellCurriculum")
        #else
        return false
        #endif
    }

    private static var debugEntersCurriculum: Bool {
        #if DEBUG
        return ProcessInfo.processInfo.arguments.contains("-EnterShellCurriculum")
        #else
        return false
        #endif
    }

    var body: some View {
        content
            .animation(.easeInOut(duration: 0.25), value: hasSeenOnboarding)
            .animation(.easeInOut(duration: 0.25), value: consentVersion)
            .animation(.easeInOut(duration: 0.25), value: gateClearedThisLaunch)
            .animation(.easeInOut(duration: 0.25), value: hasEnteredApp)
            // `mercurius://lesson/<id>` (a reminder's link) opens that lesson;
            // `mercurius://session` (the Live Activity's tap target) skips the
            // Home doorman and lands on the learning path, where the
            // in-progress lesson is the highlighted node. Neither shortcuts
            // the gate: the `content` order below checks it first.
            .onOpenURL { url in
                if let lessonId = LessonDeepLink.lessonId(from: url) {
                    env.pendingLessonId = lessonId
                    return
                }
                guard url.scheme == "mercurius", url.host == "session" else { return }
                entryTab = .curriculum
                hasEnteredApp = true
            }
            .onChange(of: env.pendingLessonId) { _, _ in routePendingLesson() }
            .onAppear {
                #if os(iOS)
                // Before this, a reminder tapped at cold launch is held by
                // the router; setting the handler delivers it.
                NotificationRouter.shared.onOpenLesson = { [env] lessonId in
                    env.pendingLessonId = lessonId
                }
                #endif
                routePendingLesson()
                refreshReminders()
            }
            // Keep the reminders current (rotating Merc copy, streak defense,
            // the lesson a tap opens): re-plan on every foreground change,
            // after every chat that touches the streak, and whenever the next
            // stop may have moved.
            .onChange(of: scenePhase) { _, phase in
                refreshReminders()
                // Leaving the app from inside the shell counts as activity,
                // so reopening it shortly after resumes there.
                if phase == .background, hasEnteredApp, !showsGate {
                    env.lastActivityStore.touch()
                }
                // Permission may have changed in the iOS Settings app.
                if phase == .active { Task { await refreshNotificationAsk() } }
            }
            .onChange(of: env.streakStore.lastUpdatedAt) { _, _ in refreshReminders() }
            .onChange(of: env.progressStore.revision) { _, _ in refreshReminders() }
            // Consent given in this launch: the launch hold skipped the
            // streak seed (it never fetches before consent), so run it now.
            // Entering the shell retries one that failed.
            .task(id: showsGate) {
                guard !showsGate else { return }
                await refreshNotificationAsk()
                await env.seedStreakIfNeeded()
            }
            .onChange(of: hasEnteredApp) { _, entered in
                guard !showsGate else { return }
                Task {
                    if entered {
                        await env.seedStreakIfNeeded()
                    } else {
                        // Back on Home: the Progress hub may have asked already.
                        await refreshNotificationAsk()
                    }
                }
            }
    }

    @ViewBuilder
    private var content: some View {
        if showsGate {
            OnboardingFlow(
                mode: hasSeenOnboarding ? .gateOnly : .full,
                reminderStore: env.reminderStore,
                streakStore: env.streakStore,
                reminderCardStore: env.reminderCardStore,
                onStartLesson1: {
                    entryTab = .curriculum
                    entryLesson = MercuriusCurriculum.units.first?.lessons.first
                    hasEnteredApp = true
                    gateClearedThisLaunch = true
                },
                onJustChat: {
                    entryTab = .chat
                    hasEnteredApp = true
                    gateClearedThisLaunch = true
                },
                onGateCleared: { gateClearedThisLaunch = true }
            )
            .transition(.opacity)
        } else if hasEnteredApp {
            AppShellView(
                apiClient: env.apiClient,
                sessionIdentity: env.sessionIdentity,
                chatStore: env.chatStore,
                themeStore: env.themeStore,
                streakStore: env.streakStore,
                achievementStore: env.achievementStore,
                reminderStore: env.reminderStore,
                progress: env.progressStore,
                progressSync: env.progressSync,
                lastActivityStore: env.lastActivityStore,
                reviewPromptStore: env.reviewPromptStore,
                scheduler: scheduler,
                pendingLessonId: $env.pendingLessonId,
                initialTab: entryTab,
                initialLesson: entryLesson,
                initialUnitTest: entryUnitTest,
                onGoHome: {
                    hasEnteredApp = false
                    entryLesson = nil
                    entryUnitTest = nil
                    // Going Home on purpose isn't activity, and the next cold
                    // launch should honour it rather than resume the shell.
                    env.lastActivityStore.lastTab = nil
                },
                // Withdrawing consent in Settings drops the user back onto the
                // gate (gate-only mode, since the first run already happened).
                // The entry stop/tab are cleared too — otherwise a first-run
                // "Start Lesson 1" would re-open Lesson 1 from "Chat with Merc"
                // after re-consenting.
                onConsentWithdrawn: {
                    consentVersion = 0
                    gateClearedThisLaunch = false
                    hasEnteredApp = false
                    entryLesson = nil
                    entryUnitTest = nil
                    entryTab = .chat
                    env.lastActivityStore.lastTab = nil
                }
            )
            .transition(.opacity)
        } else {
            let state = homeState
            HomeView(
                state: state,
                onStartNext: { startNext(state.next) },
                onStartChat: {
                    entryTab = .chat
                    hasEnteredApp = true
                },
                showsReminderCard: ReminderCardStore.shows(
                    handled: env.reminderCardStore.isHandled,
                    canAskPermission: canAskForNotifications == true
                ),
                onAcceptReminders: acceptReminders,
                onDismissReminderCard: { env.reminderCardStore.markHandled() }
            )
            .transition(.opacity)
        }
    }

    // MARK: - Home

    private var homeState: HomeState {
        HomeState.build(
            // Only a streak the server confirmed recently — a weeks-old cache
            // would make Merc claim a streak that has already died.
            streak: env.streakStore.isCurrentFresh ? env.streakStore.current : 0,
            progress: env.progressStore
        )
    }

    private func startNext(_ stop: MercuriusCurriculum.PathStop?) {
        entryTab = .curriculum
        switch stop {
        case .lesson(let lesson):
            entryLesson = lesson
            entryUnitTest = nil
        case .unitTest(let unit):
            entryLesson = nil
            entryUnitTest = unit
        case nil:
            entryLesson = nil
            entryUnitTest = nil
        }
        hasEnteredApp = true
    }

    private func acceptReminders() {
        env.reminderCardStore.markHandled()
        Task {
            // Weekly only — the card promises twice a week, not a daily ping.
            _ = await ReminderEnabler.enable(
                [.weekly],
                store: env.reminderStore,
                scheduler: scheduler,
                streakStore: env.streakStore,
                nextLessonId: env.progressStore.frontierLessonId
            )
        }
    }

    // MARK: - Reminders + routing

    private func refreshNotificationAsk() async {
        canAskForNotifications = await ReminderCardStore.canAskForNotifications()
    }

    private func refreshReminders() {
        ReminderEnabler.refresh(
            store: env.reminderStore,
            scheduler: scheduler,
            streakStore: env.streakStore,
            nextLessonId: env.progressStore.frontierLessonId
        )
    }

    /// A lesson was asked for while the shell isn't up: go in on the
    /// curriculum tab and let the shell present it (and clear it) on mount.
    /// The gate still comes first when it's showing.
    private func routePendingLesson() {
        guard env.pendingLessonId != nil, !hasEnteredApp else { return }
        entryLesson = nil
        entryUnitTest = nil
        entryTab = .curriculum
        hasEnteredApp = true
    }
}
