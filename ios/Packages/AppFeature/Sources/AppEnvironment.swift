import Foundation
import NetworkingKit
import PersistenceKit
import SettingsFeature
import ClubFeature

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
        self.init(environment: environment, chatStore: Self.makeDefaultChatStore())
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
            print("[Mercurius] SwiftData init failed — falling back to in-memory store. Error: \(error)")
            return InMemoryChatStore()
        }
    }
}
