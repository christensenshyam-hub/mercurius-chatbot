import Testing
@testable import AppFeature
import PersistenceKit

@Suite("AppEnvironment")
@MainActor
struct AppEnvironmentTests {

    @Test("Creates without throwing and exposes required collaborators")
    func construction() {
        // Explicitly inject an in-memory chat store. The disk-backed
        // SwiftData default calls through to `Bundle.main.bundleIdentifier`
        // which is nil in SPM test contexts on CI — SwiftData responds
        // with a `fatalError`, which can't be caught. Production callers
        // still get the disk-backed default via the no-arg init.
        let env = AppEnvironment(environment: .local, chatStore: InMemoryChatStore())
        _ = env.apiClient
        _ = env.sessionIdentity
        _ = env.chatStore
    }
}
