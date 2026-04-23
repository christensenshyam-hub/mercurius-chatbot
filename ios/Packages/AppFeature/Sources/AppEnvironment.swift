import Foundation
import OSLog
import NetworkingKit
import PersistenceKit
import SettingsFeature
import ClubFeature

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

    /// Fetches the club's public JSON (events + blog). Independent of
    /// `apiClient` because these assets live on `mayoailiteracy.com`,
    /// not on the Mercurius server.
    public let clubClient: ClubDataProviding

    /// App-wide theme preference. Observed by `RootView` so the chosen
    /// color scheme propagates everywhere the moment the user changes
    /// it in Settings.
    public let themeStore: ThemePreferenceStore

    /// Disk-backed chat history. `nil` only if SwiftData fails to
    /// initialize its container — in that case the app still runs,
    /// just without persistent conversations.
    public let chatStore: ChatStore?

    public convenience init(environment: APIEnvironment = .production) {
        // Default production init: disk-backed SwiftData, fall back to
        // in-memory on throw. The init below has `chatStore: nil` fall
        // through to this default.
        //
        // Performance-test hook: `-SeedDemoChat` on the launch args
        // swaps in an in-memory store preloaded with ~50 messages so
        // `MercuriusUITests/PerformanceTests` can measure scroll time
        // and memory in a non-trivial chat state. Safe to leave
        // unconditional — launch args are settable only by the
        // launcher (Xcode / XCUITest / Instruments), never by users
        // via the home screen.
        let store = Self.shouldSeedDemoChat()
            ? Self.makeDemoSeededChatStore()
            : Self.makeDefaultChatStore()
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
        self.clubClient = ClubDataClient()
        self.themeStore = ThemePreferenceStore()
        self.chatStore = chatStore
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

    private static func shouldSeedDemoChat() -> Bool {
        ProcessInfo.processInfo.arguments.contains(seedDemoChatArgument)
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
        let convoId = store.createConversation()
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
