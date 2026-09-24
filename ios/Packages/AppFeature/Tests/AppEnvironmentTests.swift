import Foundation
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
        _ = env.progressStore
        _ = env.progressSync
        _ = env.lastActivityStore
        _ = env.reviewPromptStore
        _ = env.reminderCardStore
        #expect(env.pendingLessonId == nil)
    }

    @Test("-UITests gives last activity, the review counter and the reminder card private suites wiped per launch")
    func uiTestDefaultsAreIsolated() {
        let args = [AppEnvironment.uiTestArgument, "YES"]
        let suite = AppEnvironment.uiTestLastActivitySuite

        let first = AppEnvironment.makeDefaults(suite: suite, arguments: args)
        first.set("curriculum", forKey: "probe")
        #expect(first !== UserDefaults.standard)

        let second = AppEnvironment.makeDefaults(suite: suite, arguments: args)
        #expect(second.string(forKey: "probe") == nil)

        #expect(Set([
            AppEnvironment.uiTestProgressSuite,
            AppEnvironment.uiTestLastActivitySuite,
            AppEnvironment.uiTestReviewPromptSuite,
            AppEnvironment.uiTestReminderCardSuite,
        ]).count == 4)
    }

    @Test("Outside UI tests the stores use the standard defaults")
    func standardDefaultsOutsideUITests() {
        #expect(AppEnvironment.makeDefaults(suite: AppEnvironment.uiTestLastActivitySuite, arguments: []) === UserDefaults.standard)
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
