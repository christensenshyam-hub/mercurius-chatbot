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

    public init(environment: APIEnvironment = .production) {
        let identity = SessionIdentity()
        self.sessionIdentity = identity
        self.apiClient = APIClient(
            environment: environment,
            sessionIdentity: identity
        )
        self.clubClient = ClubDataClient()
        self.themeStore = ThemePreferenceStore()

        // SwiftData container construction can throw; we degrade
        // gracefully rather than crash. A failed persistence layer
        // is worse UX than a non-persistent chat, not the other way
        // around.
        do {
            self.chatStore = try SwiftDataChatStore()
        } catch {
            // Surface to the console so the issue is visible in logs,
            // but keep the app running.
            print("[Mercurius] SwiftData init failed — falling back to in-memory store. Error: \(error)")
            self.chatStore = InMemoryChatStore()
        }
    }
}
