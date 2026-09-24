import Foundation
import OSLog
import CurriculumFeature
import NetworkingKit
import PersistenceKit
import SettingsFeature

/// Shared logger for app-level diagnostics. Surfaces in Console.app
/// under the `com.mayoailiteracy.mercurius` subsystem when filtered
/// by subsystem.
private let log = Logger(
    subsystem: "com.mayoailiteracy.mercurius",
    category: "AppEnvironment"
)

/// The app's composition root — a single place where singletons are
/// constructed and injected into feature modules. Features never reach
/// for a singleton directly; they take their dependencies as inputs.
@MainActor
public final class AppEnvironment: ObservableObject {
    public let apiClient: APIClient
    public let sessionIdentity: SessionIdentity

    /// App-wide theme preference. Observed by `RootView` so the chosen
    /// color scheme propagates everywhere the moment the user changes
    /// it in Settings.
    public let themeStore: ThemePreferenceStore

    /// Disk-backed chat history. `nil` only if SwiftData fails to
    /// initialize its container — in that case the app still runs,
    /// just without persistent conversations.
    public let chatStore: ChatStore?

    /// Engagement stores — streak cache + achievements. Shared singletons so the
    /// chat view model (which writes them), the Progress hub, and the toast
    /// presenter all observe the same state.
    public let streakStore: StreakStore
    public let achievementStore: AchievementStore
    public let reminderStore: ReminderStore

    /// Lesson completion + unit mastery. One instance for the process, so
    /// Home, the shell, the reset path and the server sync all see the same
    /// state.
    public let progressStore: CurriculumProgressStore
    /// Keeps `progressStore` in step with `/api/progress`.
    let progressSync: CurriculumProgressSync
    /// When the student last did something, for the cold-launch resume.
    public let lastActivityStore: LastActivityStore
    /// The per-device App Store review prompt budget. Never reset.
    public let reviewPromptStore: ReviewPromptStore
    /// Whether the Home card offering weekly nudges has been answered.
    let reminderCardStore: ReminderCardStore

    /// A lesson a tapped reminder (or a `mercurius://lesson/<id>` link) asked
    /// to open. The shell presents it and clears it.
    @Published public var pendingLessonId: String?

    /// The streak seed has succeeded this process.
    private var didSeedStreak = false

    public convenience init(environment: APIEnvironment = .production) {
        // DEBUG-only dev hook: launch with `-UseLocalServer` (Xcode / simctl)
        // to point the app at the local dev server (http://localhost:3000)
        // instead of production. Never settable by users — only the launcher.
        var environment = environment
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-UseLocalServer") {
            environment = .local
        }
        #endif

        // Default production init: disk-backed SwiftData, fall back to
        // in-memory on throw. The init below has `chatStore: nil` fall
        // through to this default.
        //
        // Launch-arg hooks — all settable only by the launcher (Xcode /
        // XCUITest / Instruments), never by users from the home screen:
        //   -SeedDemoChat  → InMemoryChatStore preloaded with ~50 msgs
        //                    (used by PerformanceTests for realistic
        //                    scroll / memory measurements).
        //   -UITests YES   → empty InMemoryChatStore. MercuriusUITests
        //                    assumes a clean slate each run — without
        //                    this the disk-backed SwiftData store from a
        //                    prior simulator session makes EmptyChatView
        //                    skip, which breaks the starter-prompts test.
        //
        // Order matters: -SeedDemoChat wins over -UITests so the perf
        // suite can still pass both flags if it ever wants the clean-
        // simulator guarantee without losing its seeded history.
        let store: ChatStore?
        if Self.shouldSeedDemoChat() {
            store = Self.makeDemoSeededChatStore()
        } else if Self.shouldUseCleanInMemoryStore() {
            store = InMemoryChatStore()
        } else {
            store = Self.makeDefaultChatStore()
        }
        self.init(environment: environment, chatStore: store)
    }

    /// Inject a pre-built `ChatStore` — used by tests that run in
    /// contexts without a resolvable `Bundle.main.bundleIdentifier`
    /// (e.g. `swift test` on a CI runner), where SwiftData's default
    /// disk-backed container crashes with a fatal error inside Apple's
    /// framework rather than throwing — we can't catch a `fatalError`,
    /// so we have to avoid calling into SwiftData at all in those
    /// contexts.
    public init(environment: APIEnvironment = .production, chatStore: ChatStore?) {
        let identity = SessionIdentity()
        self.sessionIdentity = identity
        self.apiClient = APIClient(
            environment: environment,
            sessionIdentity: identity
        )
        self.themeStore = ThemePreferenceStore()
        self.chatStore = chatStore
        self.streakStore = StreakStore()
        self.achievementStore = AchievementStore()
        self.reminderStore = ReminderStore()

        let arguments = ProcessInfo.processInfo.arguments
        let isUITesting = arguments.contains(Self.uiTestArgument)
        let progress = CurriculumProgressStore(preferences: Self.curriculumProgressPreferences)
        self.progressStore = progress
        self.progressSync = CurriculumProgressSync(
            progress: progress,
            remote: apiClient,
            sessionId: { try identity.current() },
            // UI tests are network-free, and a real pull could mark Lesson 1
            // complete from the simulator's Keychain session.
            isEnabled: !isUITesting
        )
        self.lastActivityStore = LastActivityStore(
            defaults: Self.makeDefaults(suite: Self.uiTestLastActivitySuite, arguments: arguments))
        self.reviewPromptStore = ReviewPromptStore(
            defaults: Self.makeDefaults(suite: Self.uiTestReviewPromptSuite, arguments: arguments))
        self.reminderCardStore = ReminderCardStore(
            defaults: Self.makeDefaults(suite: Self.uiTestReminderCardSuite, arguments: arguments))
        if isUITesting {
            // Every UI test anchors on Home's CTAs; the card would push them
            // down. Its logic is covered by the AppFeature unit tests.
            reminderCardStore.markHandled()
        }
    }

    /// Seed the streak cache from the server's session row. Runs at most once
    /// successfully per process: the launch hold runs it when consent is
    /// already current, and the entry view retries after the gate clears.
    /// Callers must only invoke it once the data-use agreement is current.
    func seedStreakIfNeeded() async {
        guard !didSeedStreak, let sid = try? sessionIdentity.current() else { return }
        guard let snapshot = try? await apiClient.sessionStreak(sessionId: sid) else { return }
        // `seed`, not `update`: the session row's streak is only recomputed
        // when the user chats, so a lapsed user's row can be weeks stale —
        // freshness must come from the row's own `last_session_date`, not
        // from when we happened to fetch it, or the Home greeting would
        // claim a dead streak is alive.
        streakStore.seed(streak: snapshot.streak, lastSessionDate: snapshot.lastSessionDate)
        didSeedStreak = true
    }

    /// Constructs the production default `ChatStore` — disk-backed
    /// SwiftData, falling through to `InMemoryChatStore` if SwiftData's
    /// `ModelContainer` init throws. Logs the failure to the console so
    /// the reason is still visible.
    private static func makeDefaultChatStore() -> ChatStore? {
        do {
            return try SwiftDataChatStore()
        } catch {
            // Surface to os_log rather than stdout so Console.app / `log
            // stream` picks it up with structured metadata. The user
            // still gets a working app via the InMemoryChatStore
            // fallback; they just lose chat persistence across kills.
            log.error("SwiftData init failed — falling back to in-memory store. \(error.localizedDescription, privacy: .public)")
            return InMemoryChatStore()
        }
    }

    // MARK: - Demo-chat seeding (perf-test hook)

    /// Launch-argument flag that tells `AppEnvironment` to use an
    /// in-memory ChatStore pre-populated with a long conversation.
    /// Toggled by `MercuriusUITests/PerformanceTests` when measuring
    /// scroll perf + memory in a realistic state.
    static let seedDemoChatArgument = "-SeedDemoChat"

    /// Launch-argument flag the UITest harness passes (`-UITests YES`) to
    /// force a clean, in-memory ChatStore. Without this, a persisted
    /// SwiftData store from a prior simulator session bleeds through
    /// into the test run — EmptyChatView doesn't render and assertions
    /// against starter-prompt buttons fail non-deterministically
    /// depending on the simulator's history.
    static let uiTestArgument = "-UITests"

    private static func shouldSeedDemoChat() -> Bool {
        ProcessInfo.processInfo.arguments.contains(seedDemoChatArgument)
    }

    private static func shouldUseCleanInMemoryStore() -> Bool {
        ProcessInfo.processInfo.arguments.contains(uiTestArgument)
    }

    /// Where `CurriculumProgressStore` persists. Under `-UITests` this is a
    /// private, emptied defaults suite: the chat store is in-memory then, so
    /// resume pointers left by an earlier simulator run would dangle — and
    /// hide the lesson intro the first-run UI test anchors on. Evaluated once
    /// per process, so the wipe happens once per launch.
    public static let curriculumProgressPreferences: PreferenceStore =
        makeCurriculumProgressPreferences(arguments: ProcessInfo.processInfo.arguments)

    static let uiTestProgressSuite = "com.mayoailiteracy.mercurius.uitests.curriculumProgress"
    static let uiTestLastActivitySuite = "com.mayoailiteracy.mercurius.uitests.lastActivity"
    static let uiTestReviewPromptSuite = "com.mayoailiteracy.mercurius.uitests.reviewPrompt"
    static let uiTestReminderCardSuite = "com.mayoailiteracy.mercurius.uitests.reminderCard"

    static func makeCurriculumProgressPreferences(arguments: [String]) -> PreferenceStore {
        guard arguments.contains(uiTestArgument) else { return UserDefaultsPreferenceStore() }
        return UserDefaultsPreferenceStore(defaults: makeDefaults(suite: uiTestProgressSuite, arguments: arguments))
    }

    /// `.standard`, or under `-UITests` the named private suite, emptied —
    /// so what one UI test leaves behind (a recent-activity stamp that would
    /// skip Home, a dismissed card) never reaches the next launch.
    static func makeDefaults(suite: String, arguments: [String]) -> UserDefaults {
        guard arguments.contains(uiTestArgument),
              let defaults = UserDefaults(suiteName: suite) else {
            return .standard
        }
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    /// Build an `InMemoryChatStore` preloaded with a 50-message
    /// conversation. Not representative of real Claude output —
    /// just long enough that a LazyVStack has to lazily create cells
    /// and scroll perf has signal.
    ///
    /// Deterministic (same content every run) so scroll-time
    /// measurements are comparable across invocations.
    private static func makeDemoSeededChatStore() -> ChatStore {
        let store = InMemoryChatStore()
        // Seeded conversation is tagged Socratic — the default mode the
        // performance tests exercise. If perf tests ever care about
        // other modes, seed one per mode here.
        let convoId = store.createConversation(mode: .socratic)
        let start = Date().addingTimeInterval(-60 * 60)  // 1 hour ago

        let userPrompts = [
            "What's the alignment problem?",
            "Can you give me an example of a hallucination?",
            "How does RLHF differ from supervised fine-tuning?",
            "Why is 'fluency' not the same as 'accuracy'?",
            "What counts as 'training data', exactly?",
        ]
        let assistantReplies = [
            "The alignment problem is about getting AI behavior to match human intent, especially at scale. It gets harder as capability grows.",
            "A hallucination is when a model produces a confident-sounding statement that isn't grounded in fact. Classic example: citing a paper that doesn't exist.",
            "RLHF tunes the model based on human preference comparisons between outputs. Supervised fine-tuning just trains on labeled examples.",
            "Fluency is about producing plausible-looking text. Accuracy is about whether the text is correct. LLMs optimize for the first.",
            "The text corpus the model trained on — typically a huge mix of web pages, books, and code.",
        ]

        for i in 0..<50 {
            let role = i % 2 == 0 ? "user" : "assistant"
            let content: String
            if role == "user" {
                content = userPrompts[(i / 2) % userPrompts.count]
            } else {
                content = assistantReplies[(i / 2) % assistantReplies.count]
            }
            let message = StoredMessage(
                id: UUID(),
                role: role,
                content: content,
                createdAt: start.addingTimeInterval(TimeInterval(i * 30))
            )
            store.append(message, to: convoId)
        }

        log.info("Seeded demo chat with 50 messages (\(seedDemoChatArgument))")
        return store
    }
}
