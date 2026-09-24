import SwiftUI
import DesignSystem
#if DEBUG
import ChatFeature
import CurriculumFeature
import EngagementFeature
import MercuriusActivity
import NetworkingKit
import PersistenceKit
#endif

/// Root view of the app. Focused on **bootstrap** only:
///
/// - `.loading`  — session identity is being resolved (+ SwiftData
///                 container spinning up via `AppEnvironment`), and — when
///                 consent is already current — the streak seed and the
///                 progress pull run under the launch screen, so Home opens
///                 on fresh numbers.
/// - `.ready`    — hand off to `AppEntryView`, which owns the user-
///                 facing entry flow (Onboarding → Home → AppShell).
/// - `.failed`   — show a recoverable error with a Try-again CTA.
///                 Never crashes.
///
/// Intentionally does **not** know about onboarding, HomeView, or
/// the TabView. Those concerns live in `AppEntryView`, which keeps
/// this file small and keeps the bootstrap state machine readable.
public struct RootView: View {
    @EnvironmentObject private var env: AppEnvironment

    @State private var bootstrapState: BootstrapState = .loading
    /// Decided once, as bootstrap finishes: the tab this cold launch resumes
    /// (`LaunchResume`), or nil for Home.
    @State private var resumeTab: AppShellView.Tab?

    private enum BootstrapState: Equatable {
        case loading
        case ready(sessionId: String)
        case failed(reason: String)
    }

    public init() {
        #if DEBUG
        _ = Self.debugResetConsent
        #endif
    }

    #if DEBUG
    /// `-ResetConsent`: forget the persisted consent + first-run flags once
    /// per process, before `AppEntryView` reads them, so the gate can be
    /// exercised on a simulator that already agreed. Unlike the argument
    /// domain (`-consentVersion 0`), this leaves later writes observable.
    private static let debugResetConsent: Void = {
        guard ProcessInfo.processInfo.arguments.contains("-ResetConsent") else { return }
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: ConsentGate.storageKey)
        defaults.removeObject(forKey: OnboardingFlow.storageKey)
    }()
    #endif

    public var body: some View {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-LessonPreview") {
            lessonPreview
        } else if ProcessInfo.processInfo.arguments.contains("-MercPreview") {
            MercPreviewView()
        } else if ProcessInfo.processInfo.arguments.contains("-ChatPreview") {
            chatPreview
        } else if ProcessInfo.processInfo.arguments.contains("-LiveActivityGallery") {
            liveActivityGallery
        } else if ProcessInfo.processInfo.arguments.contains("-ReplyFontGallery") {
            ReplyFontGalleryView()
        } else {
            mainBody
        }
        #else
        mainBody
        #endif
    }

    #if DEBUG
    /// DEBUG-only: launch straight into the redesigned lesson screen for the
    /// first lesson, wired to the live environment, so the Playful redesign can
    /// be screenshotted without navigating the whole app.
    @ViewBuilder private var lessonPreview: some View {
        if let unit = MercuriusCurriculum.units.first, let lesson = unit.lessons.first {
            let next = MercuriusCurriculum.nextStop(after: lesson.id)
            // A fake resume id skips the speech-bubble intro (and harmlessly
            // falls through to a fresh start) so the chat can be previewed.
            let fakeResume: UUID? = ProcessInfo.processInfo.arguments.contains("-LessonSkipIntro") ? UUID() : nil
            CurriculumLessonView(
                lessonId: lesson.id,
                unitLabel: "UNIT \(unit.number)",
                lessonNumber: lesson.number,
                title: lesson.title,
                objective: lesson.objective,
                starter: lesson.starter,
                resumeConversationId: fakeResume,
                apiClient: env.apiClient,
                sessionIdentity: env.sessionIdentity,
                chatStore: env.chatStore,
                streakStore: env.streakStore,
                achievementStore: env.achievementStore,
                onStarted: { _, _ in },
                onLessonComplete: { _ in },
                onExit: {},
                onAdvanceToNext: {},
                completedInUnit: 3,
                totalInUnit: unit.lessons.count,
                nextStop: next.map(AppShellView.celebrationStop)
            )
            .preferredColorScheme(env.themeStore.theme.colorScheme)
        } else {
            mainBody
        }
    }

    /// DEBUG-only: every Live Activity phase (lock card + DI expanded) as an
    /// in-app gallery — the sim can't fake stale/error on a real activity.
    /// (ActivityKit types are iOS-only; the macOS test host compiles this too.)
    @ViewBuilder private var liveActivityGallery: some View {
        #if os(iOS)
        LiveActivityGalleryView()
        #else
        mainBody
        #endif
    }

    /// DEBUG-only: land directly on the free Chat screen to view the branded
    /// Merc intro + assistant-avatar treatment. Pass `-ChatSeed` to also auto-send
    /// a starter so the thinking → speaking states can be seen.
    @ViewBuilder private var chatPreview: some View {
        ChatPreviewHost(
            apiClient: env.apiClient,
            sessionIdentity: env.sessionIdentity,
            chatStore: env.chatStore,
            autoSend: ProcessInfo.processInfo.arguments.contains("-ChatSeed")
        )
        .preferredColorScheme(env.themeStore.theme.colorScheme)
    }
    #endif

    @ViewBuilder private var mainBody: some View {
        ZStack {
            BrandColor.background.ignoresSafeArea()

            switch bootstrapState {
            case .loading:
                loadingView
            case .ready:
                AppEntryView(resumeTab: resumeTab)
                    .transition(.opacity)
            case .failed(let reason):
                failureView(reason: reason)
            }
        }
        .animation(.easeOut(duration: 0.2), value: bootstrapState)
        .preferredColorScheme(env.themeStore.theme.colorScheme)
        .task { await bootstrap() }
        .task {
            #if DEBUG
            // `-NotifPreview`: fire one of each reminder banner flavor (defense
            // / weekly / celebrate) seconds from now so the Merc pose art can
            // be seen without waiting for a real reminder time; tapping one
            // opens the next lesson. Fires from the always-mounted root.
            if ProcessInfo.processInfo.arguments.contains("-NotifPreview") {
                EngagementFeature.NotificationScheduler().scheduleDemo(
                    nextLessonId: env.progressStore.frontierLessonId
                )
            }
            // `-LiveActivityPreview`: start the learning Live Activity with
            // the design handoff's exact sample data (streak 24, lesson 3/5,
            // 2 to Level 7, 2h 40m left) for lock-screen / Dynamic Island
            // eyeballing without running a real session. (ActivityKit types
            // are iOS-only; the macOS test host compiles this file too.)
            #if os(iOS)
            if ProcessInfo.processInfo.arguments.contains("-LiveActivityPreview") {
                LearningActivityController.shared.startDemo()
            }
            #endif
            #endif
        }
    }

    // MARK: - States

    /// The Duolingo-style branded launch moment (Merc hovering under the
    /// wordmark + sweep + rotating tip). Held for a minimum beat by
    /// `bootstrap()` so it never flashes.
    private var loadingView: some View {
        MercLaunchScreen()
    }

    private func failureView(reason: String) -> some View {
        VStack(spacing: BrandSpacing.lg) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 40))
                .foregroundStyle(BrandColor.error)
            Text("Couldn't start")
                .font(BrandFont.title)
                .foregroundStyle(BrandColor.text)
            Text(reason)
                .font(BrandFont.caption)
                .foregroundStyle(BrandColor.textSecondary)
                .multilineTextAlignment(.center)
            BrandButton("Try again", style: .primary) {
                bootstrapState = .loading
                Task { await bootstrap() }
            }
            .frame(maxWidth: 200)
        }
        .padding(BrandSpacing.xl)
    }

    // MARK: - Bootstrap

    /// How long the branded launch screen stays up even when bootstrap
    /// finishes instantly — a beat that registers as a welcome without ever
    /// feeling like waiting.
    private static let minimumLaunchHold: Duration = .seconds(1.2)

    /// The most the launch screen waits on each server read. A slower reply
    /// still lands, just after Home is up.
    private static let launchFetchLimit: Duration = .seconds(2.5)

    private func bootstrap() async {
        let start = ContinuousClock.now
        let identity = env.sessionIdentity
        let result: BootstrapState
        do {
            let id = try await Task.detached(priority: .userInitiated) {
                try identity.current()
            }.value
            result = .ready(sessionId: id)
        } catch {
            result = .failed(reason: "Could not create a session on this device. Please restart the app.")
        }
        // Failures skip the hold — an error should surface immediately, and
        // the beat only pads the happy-path cold open.
        if case .ready = result {
            await holdLaunchScreen(since: start)
            resumeTab = LaunchResume.tab(
                store: env.lastActivityStore,
                gateShows: AppEntryView.gateShowsAtLaunch()
            )
        }
        bootstrapState = result
    }

    /// The minimum beat, overlapped with the streak seed and the progress
    /// pull (each bounded) so Home opens on current numbers. The fetches run
    /// only when consent is already current — before the data-use agreement
    /// nothing may reach the server; the entry view seeds after the gate.
    private func holdLaunchScreen(since start: ContinuousClock.Instant) async {
        let fetches = !AppEntryView.gateShowsAtLaunch()
        let hold = Self.minimumLaunchHold
        await withTaskGroup(of: Void.self) { group in
            group.addTask {
                let elapsed = start.duration(to: .now)
                if elapsed < hold {
                    try? await Task.sleep(for: hold - elapsed)
                }
            }
            guard fetches else { return }
            group.addTask { @MainActor [env] in
                await LaunchWork.waitAtMost(Self.launchFetchLimit) { await env.seedStreakIfNeeded() }
            }
            group.addTask { @MainActor [env] in
                await LaunchWork.waitAtMost(Self.launchFetchLimit) { await env.progressSync.pullOnLaunch() }
            }
        }
    }
}

#if DEBUG
/// DEBUG host for `-ChatPreview`: owns a `ChatViewModel` so it can optionally
/// auto-send a starter (`-ChatSeed`) to exercise the thinking → speaking states.
private struct ChatPreviewHost: View {
    @State private var model: ChatViewModel
    private let apiClient: APIClient
    private let sessionIdentity: SessionIdentity
    private let autoSend: Bool

    /// A demo streak so the preview shows the real slimmed header (streak chip
    /// leading, Settings + Home trailing) the way `AppShellView` wires it.
    private let demoStreak = StreakStore(defaults: UserDefaults(suiteName: "chat-preview") ?? .standard)

    init(apiClient: APIClient, sessionIdentity: SessionIdentity, chatStore: ChatStore?, autoSend: Bool) {
        self.apiClient = apiClient
        self.sessionIdentity = sessionIdentity
        self.autoSend = autoSend
        _model = State(initialValue: ChatViewModel(
            apiClient: apiClient, sessionIdentity: sessionIdentity, store: chatStore))
        demoStreak.update(streak: 3)
    }

    var body: some View {
        ChatView(
            model: model,
            apiClient: apiClient,
            sessionIdentity: sessionIdentity,
            settingsPresenter: { AnyView(Text("Settings").padding()) },
            headerAccessory: { AnyView(StreakChip(streakStore: demoStreak, action: {})) },
            onGoHome: {}
        )
        .task {
            guard autoSend, model.messages.isEmpty else { return }
            model.draft = "What is a token in an LLM?"
            model.send()
        }
    }
}
#endif
