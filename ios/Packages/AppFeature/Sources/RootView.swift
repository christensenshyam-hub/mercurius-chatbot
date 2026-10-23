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
    /// `-ResetConsent`: forget the persisted consent, first-run and age-block
    /// flags once per process, before `AppEntryView` reads them, so the gate
    /// can be exercised on a simulator that already agreed. Unlike the
    /// argument domain (`-consentVersion 0`), this leaves later writes
    /// observable.
    private static let debugResetConsent: Void = {
        guard ProcessInfo.processInfo.arguments.contains("-ResetConsent") else { return }
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: ConsentGate.storageKey)
        defaults.removeObject(forKey: OnboardingFlow.storageKey)
        defaults.removeObject(forKey: AgeBlock.storageKey)
    }()
    #endif

    public var body: some View {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-LessonPreview") && !Self.shellHostsPreviews {
            lessonPreview
        } else if ProcessInfo.processInfo.arguments.contains("-MercPreview") {
            MercPreviewView()
        } else if ProcessInfo.processInfo.arguments.contains("-ChatPreview") && !Self.shellHostsPreviews {
            chatPreview
        } else if ProcessInfo.processInfo.arguments.contains("-LiveActivityGallery") {
            liveActivityGallery
        } else if ProcessInfo.processInfo.arguments.contains("-ReplyFontGallery") {
            ReplyFontGalleryView()
        } else if ProcessInfo.processInfo.arguments.contains("-UnitTestCrisisPreview") && !Self.shellHostsPreviews {
            unitTestCrisisPreview
        } else if ProcessInfo.processInfo.arguments.contains("-UnitTestPreview") && !Self.shellHostsPreviews {
            unitTestPreview
        } else if let mode = CertificateDebug.mode, !Self.shellHostsPreviews {
            certificatePreview(mode)
        } else if ProcessInfo.processInfo.arguments.contains("-QuizCrisisPreview") {
            QuizView(
                model: QuizViewModel(tools: CrisisPreviewTools(), sessionIdProvider: { "debug-preview" }),
                dismissAction: {}
            )
            .preferredColorScheme(BrandAppearance.colorScheme)
        } else {
            mainBody
        }
        #else
        mainBody
        #endif
    }

    #if DEBUG
    /// On the Mac, `-LessonPreview`, `-ChatPreview`, `-UnitTestPreview` and
    /// `-UnitTestCrisisPreview` open inside the window's shell (past the gate,
    /// sidebar and all — see `MacShellView`) rather than replacing the whole
    /// window as they do on iPhone.
    private static var shellHostsPreviews: Bool {
        #if os(macOS)
        true
        #else
        false
        #endif
    }

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
            .preferredColorScheme(BrandAppearance.colorScheme)
        } else {
            mainBody
        }
    }

    /// DEBUG-only: the certificate shots (`CertificateDebug`): on the Mac
    /// they open inside the shell.
    @ViewBuilder private func certificatePreview(_ mode: CertificateDebug.Mode) -> some View {
        #if os(iOS)
        CertificateDebugHost(mode: mode)
            .preferredColorScheme(env.themeStore.theme.colorScheme)
        #else
        mainBody
        #endif
    }

    /// DEBUG-only: Unit 1's test at a stage (`-UnitTestStage`), for
    /// screenshots (see `UnitTestPreviewHost`).
    @ViewBuilder private var unitTestPreview: some View {
        if let unit = MercuriusCurriculum.units.first,
           let test = MercuriusCurriculum.unitTest(for: unit.id) {
            UnitTestPreviewHost(unit: unit, test: test,
                                stage: UserDefaults.standard.string(forKey: "UnitTestStage"))
                .preferredColorScheme(BrandAppearance.colorScheme)
        } else {
            mainBody
        }
    }

    /// DEBUG-only: Unit 1's test driven through the real view model to the
    /// crisis support view, for screenshots (see `UnitTestCrisisPreviewHost`).
    /// `-CrisisVia503` takes the non-2xx path instead.
    @ViewBuilder private var unitTestCrisisPreview: some View {
        if let unit = MercuriusCurriculum.units.first,
           let test = MercuriusCurriculum.unitTest(for: unit.id) {
            UnitTestCrisisPreviewHost(
                unit: unit,
                test: test,
                via503: ProcessInfo.processInfo.arguments.contains("-CrisisVia503")
            )
            .preferredColorScheme(BrandAppearance.colorScheme)
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
        .preferredColorScheme(BrandAppearance.colorScheme)
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
        .preferredColorScheme(BrandAppearance.colorScheme)
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
    @ViewBuilder private var loadingView: some View {
        #if os(macOS)
        // A Mac app opens straight into its window: no branded hold, so the
        // launch screen would only flash for a frame.
        Color.clear
        #else
        MercLaunchScreen()
        #endif
    }

    private func failureView(reason: String) -> some View {
        #if os(macOS)
        // Night Studio: a line and a way forward on a flat canvas (§5.10).
        MacStartFailure(reason: reason) {
            bootstrapState = .loading
            Task { await bootstrap() }
        }
        #else
        VStack(spacing: BrandSpacing.lg) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 40))
                .foregroundStyle(BrandColor.errorText)
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
        #endif
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
        // the beat only pads the happy-path cold open. So does a resume: the
        // student was here moments ago (iOS evicted the app), and the welcome
        // beat would only stand between them and the tab they left. The shell
        // runs its own streak seed and progress pull.
        #if os(macOS)
        // The Mac skips the welcome hold and the resume: its window keeps its
        // place in the sidebar, and the shell runs the streak seed and the
        // progress pull itself once consent is current.
        _ = start
        #if DEBUG
        // `-NightStartFailure YES` (shots only): the start-up failure screen.
        if ProcessInfo.processInfo.arguments.contains("-NightStartFailure") {
            bootstrapState = .failed(reason: "Could not create a session on this device. Please restart the app.")
            return
        }
        #endif
        bootstrapState = result
        #else
        if case .ready = result {
            let resume = LaunchResume.tab(
                store: env.lastActivityStore,
                gateShows: AppEntryView.gateShowsAtLaunch()
            )
            if resume == nil { await holdLaunchScreen(since: start) }
            resumeTab = resume
        }
        bootstrapState = result
        #endif
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

/// DEBUG host for `-UnitTestPreview`: Unit 1's test, driven to a stage for
/// screenshots with no network call. `-UnitTestStage partial` picks three
/// answers (the submit button's "Answer all 5 · 3/5"); `review` answers
/// every question, the first one wrong, and submits; `mastered` and
/// `almost` reach the result screen through a canned grade. With no stage
/// it opens untouched.
struct UnitTestPreviewHost: View {
    @State private var model: UnitTestViewModel
    private let stage: String?
    private let onMastered: (String) -> Void

    init(unit: CurriculumFeature.Unit, test: UnitTest, stage: String?, onMastered: @escaping (String) -> Void = { _ in }) {
        self.onMastered = onMastered
        let pass = stage == "mastered"
        _model = State(initialValue: UnitTestViewModel(unit: unit, test: test, shuffleSeed: 42) { _ in
            .init(grade: pass ? "A" : "C", pass: pass,
                  feedback: pass ? "Clear, specific and well reasoned." : "Name a concrete example of where it goes wrong.")
        })
        self.stage = stage
    }

    var body: some View {
        UnitTestView(model: model, onMastered: onMastered, onExit: {})
            .task {
                guard model.phase == .quiz, !model.quizSubmitted, let stage else { return }
                switch stage {
                case "partial":
                    for question in model.questions.prefix(3) { model.select(question.answer, for: question.id) }
                case "review":
                    for (i, question) in model.questions.enumerated() {
                        let wrong = question.answer == "A" ? "B" : "A"
                        model.select(i == 0 ? wrong : question.answer, for: question.id)
                    }
                    model.submitQuiz()
                case "mastered", "almost":
                    for question in model.questions { model.select(question.answer, for: question.id) }
                    model.submitQuiz()
                    model.continueAfterQuiz()
                    model.defenseAnswer = "DEBUG preview answer."
                    await model.submitDefense()
                #if os(macOS)
                case "written":
                    // The written question, not yet answered (Mac shots).
                    for question in model.questions { model.select(question.answer, for: question.id) }
                    model.submitQuiz()
                    model.continueAfterQuiz()
                #endif
                default:
                    break
                }
            }
    }
}

/// DEBUG host for `-UnitTestCrisisPreview`: answers every multiple-choice
/// question correctly, then submits a written answer whose grade is the
/// production server's exact crisis payload, run through the real decode
/// (`UnitDefenseResult`) and mapping (`UnitDefenseGrading`). With `via503` the
/// same copy arrives as a helper route's 503 crisis body through
/// `APIClient.validate`. No network call is made.
struct UnitTestCrisisPreviewHost: View {
    @State private var model: UnitTestViewModel

    /// `/api/unit-test/grade`'s crisis answer, byte for byte (server.js
    /// CRISIS_GRADE with lib/safetyCore.js CRISIS_COPY).
    static let grade200 = #"{"grade":"—","pass":false,"feedback":"I'm really glad you told me. I'm an AI, so I can't be your support person, but you deserve real support right now.\n\nCall or text 988 — the Suicide & Crisis Lifeline (US, 24/7).\nText HOME to 741741 — Crisis Text Line.\n\nIf you might be in immediate danger, call 911. Please tell a trusted adult too, like a parent or school counselor. Everything else can wait — come back to it whenever you're ready.","crisis":true}"#
    /// A JSON helper route's crisis answer (server.js CRISIS_RESULT, 503).
    nonisolated static let helper503 = #"{"error":"crisis","message":"I'm really glad you told me. I'm an AI, so I can't be your support person, but you deserve real support right now.\n\nCall or text 988 — the Suicide & Crisis Lifeline (US, 24/7).\nText HOME to 741741 — Crisis Text Line.\n\nIf you might be in immediate danger, call 911. Please tell a trusted adult too, like a parent or school counselor. Everything else can wait — come back to it whenever you're ready.","crisis":true}"#

    init(unit: CurriculumFeature.Unit, test: UnitTest, via503: Bool) {
        _model = State(initialValue: UnitTestViewModel(unit: unit, test: test) { _ in
            try await UnitDefenseGrading.grade {
                if via503 {
                    try APIClient.validate(statusCode: 503, data: Data(Self.helper503.utf8))
                }
                return try JSONDecoder().decode(UnitDefenseResult.self, from: Data(Self.grade200.utf8))
            }
        })
    }

    var body: some View {
        UnitTestView(model: model, onMastered: { _ in }, onExit: {})
            .task {
                guard model.phase == .quiz else { return }
                for question in model.questions { model.select(question.answer, for: question.id) }
                model.submitQuiz()
                model.continueAfterQuiz()
                model.defenseAnswer = "DEBUG crisis preview answer."
                await model.submitDefense()
            }
    }
}

/// DEBUG `-QuizCrisisPreview`: `/api/quiz`'s crisis answer (server.js
/// CRISIS_RESULT, a 503) through the real `APIClient.validate`, so the quiz
/// sheet's support state can be screenshotted. No network call is made.
private struct CrisisPreviewTools: ToolsProviding {
    func generateQuiz(sessionId: String) async throws -> Quiz {
        try APIClient.validate(statusCode: 503, data: Data(UnitTestCrisisPreviewHost.helper503.utf8))
        throw APIError.unknown(underlying: "unreachable")
    }

    func generateReportCard(sessionId: String) async throws -> ReportCard {
        throw APIError.unknown(underlying: "unused")
    }
}
#endif
