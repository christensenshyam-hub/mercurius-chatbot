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

    @Test("-UITests gives lesson progress a private suite that starts empty every launch")
    func uiTestProgressSuiteStartsEmpty() {
        let args = [AppEnvironment.uiTestArgument, "YES"]

        let first = AppEnvironment.makeCurriculumProgressPreferences(arguments: args)
        first.set("u1_l1", for: "probe")
        #expect(first.string(for: "probe") == "u1_l1")

        // A "new launch" wipes what the previous one left behind.
        let second = AppEnvironment.makeCurriculumProgressPreferences(arguments: args)
        #expect(second.string(for: "probe") == nil)
    }
}
