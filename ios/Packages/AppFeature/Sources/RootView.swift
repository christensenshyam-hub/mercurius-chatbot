import SwiftUI
import DesignSystem
#if DEBUG
import ChatFeature
import CurriculumFeature
import EngagementFeature
import MercFlowFeature
import NetworkingKit
import PersistenceKit
#endif

/// Root view of the app. Focused on **bootstrap** only:
///
/// - `.loading`  — session identity is being resolved (+ SwiftData
///                 container spinning up via `AppEnvironment`).
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

    private enum BootstrapState: Equatable {
        case loading
        case ready(sessionId: String)
        case failed(reason: String)
    }

    public init() {}

    public var body: some View {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-MercFlow") {
            MercFlowFeature.LessonView()
        } else if ProcessInfo.processInfo.arguments.contains("-LessonPreview") {
            lessonPreview
        } else if ProcessInfo.processInfo.arguments.contains("-MercPreview") {
            MercPreviewView()
        } else if ProcessInfo.processInfo.arguments.contains("-ChatPreview") {
            chatPreview
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
            let next = unit.lessons.dropFirst().first
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
                nextLessonNumber: next?.number,
                nextLessonTitle: next?.title,
                onAdvanceToNext: {},
                completedInUnit: 3,
                totalInUnit: unit.lessons.count
            )
            .preferredColorScheme(env.themeStore.theme.colorScheme)
        } else {
            mainBody
        }
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
                AppEntryView()
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
            // / wave / celebrate) seconds from now so the Merc pose art can be
            // seen without waiting for a real reminder time. Fires from the
            // always-mounted root (the AppShell hook never runs from Home).
            if ProcessInfo.processInfo.arguments.contains("-NotifPreview") {
                EngagementFeature.NotificationScheduler().scheduleDemo()
            }
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
    /// finishes instantly — the Duolingo beat. Long enough to register as a
    /// welcome, short enough to never feel like waiting.
    private static let minimumLaunchHold: Duration = .seconds(2.2)

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
        // Hold the launch screen for its minimum beat before revealing Home.
        // Failures skip the hold — an error should surface immediately, and
        // the beat only pads the happy-path cold open.
        let elapsed = start.duration(to: .now)
        if case .ready = result, elapsed < Self.minimumLaunchHold {
            try? await Task.sleep(for: Self.minimumLaunchHold - elapsed)
        }
        bootstrapState = result
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

    init(apiClient: APIClient, sessionIdentity: SessionIdentity, chatStore: ChatStore?, autoSend: Bool) {
        self.apiClient = apiClient
        self.sessionIdentity = sessionIdentity
        self.autoSend = autoSend
        _model = State(initialValue: ChatViewModel(
            apiClient: apiClient, sessionIdentity: sessionIdentity, store: chatStore))
    }

    var body: some View {
        ChatView(model: model, apiClient: apiClient, sessionIdentity: sessionIdentity)
            .task {
                guard autoSend, model.messages.isEmpty else { return }
                model.draft = "What is a token in an LLM?"
                model.send()
            }
    }
}
#endif
