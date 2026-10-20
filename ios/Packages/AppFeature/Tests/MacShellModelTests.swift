#if os(macOS)
import Foundation
import Testing
@testable import AppFeature
import ChatFeature
import CurriculumFeature
import NetworkingKit
import PersistenceKit

/// The Mac window's navigation model: what the sidebar, the menu commands
/// and the first-run flow can open, and that nothing opens while the consent
/// gate shows.
@Suite("Mac shell navigation")
@MainActor
struct MacShellModelTests {

    private let chatStore = InMemoryChatStore()
    private let progress = CurriculumProgressStore(preferences: InMemoryPreferenceStore())

    private func makeShell(gated: Bool = false) -> MacShellModel {
        let identity = SessionIdentity(keychain: InMemoryKeychain())
        let store = chatStore
        let shell = MacShellModel(
            progress: progress,
            lastActivityStore: LastActivityStore(defaults: freshDefaults("mac.shell.activity")),
            chatStore: store,
            makeChatModel: {
                ChatViewModel(
                    apiClient: APIClient(environment: .local, sessionIdentity: identity),
                    sessionIdentity: identity,
                    store: store
                )
            }
        )
        shell.setGated(gated)
        return shell
    }

    private var lesson1: Lesson { MercuriusCurriculum.units[0].lessons[0] }

    @Test("While the gate shows, the menu commands and sidebar clicks do nothing")
    func gatedIgnoresUserActions() {
        let shell = makeShell(gated: true)
        #expect(shell.isGated)
        shell.show(.unit(MercuriusCurriculum.units[1].id))
        shell.showPath()
        shell.showChat()
        shell.newChat()
        #expect(shell.selection == .today)
        #expect(shell.activeLesson == nil)
        #expect(chatStore.listConversations().isEmpty, "New Chat behind the gate must not build or save a thread")
    }

    @Test("A gate that comes back closes what was open and returns to Today")
    func regatingResets() {
        let shell = makeShell()
        shell.openLesson(lesson1)
        shell.showsProgress = true
        shell.setGated(true)
        #expect(shell.activeLesson == nil)
        #expect(!shell.showsProgress)
        #expect(shell.selection == .today)
        #expect(shell.conversations.isEmpty)
    }

    @Test("A lesson opens under its unit's row, and is marked opened (not completed)")
    func openLessonSelectsItsUnit() {
        let shell = makeShell()
        shell.openLesson(lesson1)
        #expect(shell.selection == .unit(MercuriusCurriculum.units[0].id))
        #expect(shell.activeLesson == lesson1)
        #expect(progress.lastOpenedLessonId == lesson1.id)
        #expect(!progress.isCompleted(lesson1.id))
    }

    @Test("The first-run flow can route as the gate clears (before the shell hears of it)")
    func firstRunRoutesWhileGated() {
        let shell = makeShell(gated: true)
        shell.openLesson(lesson1)
        #expect(shell.activeLesson == lesson1)
        let other = makeShell(gated: true)
        other.openChat()
        #expect(other.selection == .chat(other.chatModel.conversationId))
    }

    @Test("Clicking a row closes the open lesson or check")
    func showClosesActivity() {
        let shell = makeShell()
        shell.openLesson(lesson1)
        shell.show(.today)
        #expect(shell.activeLesson == nil)
        #expect(shell.selection == .today)

        shell.openUnitTest(MercuriusCurriculum.units[0])
        #expect(shell.activeUnitTest == MercuriusCurriculum.units[0])
        shell.show(.unit(MercuriusCurriculum.units[0].id))
        #expect(shell.activeUnitTest == nil)
    }

    @Test("New Chat selects the fresh thread, which has no sidebar row until its first message")
    func newChatSelectsFreshThread() {
        let shell = makeShell()
        shell.newChat()
        let id = shell.chatModel.conversationId
        #expect(id != nil)
        #expect(shell.selection == .chat(id))
        shell.refreshConversations()
        #expect(shell.conversations.isEmpty)
    }

    @Test("The sidebar lists only threads with messages")
    func sidebarSkipsEmptyThreads() {
        let now = Date()
        func summary(_ count: Int) -> ConversationSummary {
            ConversationSummary(id: UUID(), mode: "socratic", title: "t", preview: "p",
                                messageCount: count, createdAt: now, updatedAt: now)
        }
        let listed = MacShellModel.sidebarConversations([summary(0), summary(2), summary(0), summary(1)])
        #expect(listed.map(\.messageCount) == [2, 1])
    }

    @Test("Learning Path opens the unit holding the next stop")
    func pathOpensFrontierUnit() {
        let units = MercuriusCurriculum.units
        #expect(MacShellModel.pathUnitId(frontier: nil) == units[0].id)
        #expect(MacShellModel.pathUnitId(frontier: .lesson(units[2].lessons[1])) == units[2].id)
        #expect(MacShellModel.pathUnitId(frontier: .unitTest(units[3])) == units[3].id)

        let shell = makeShell()
        shell.openLesson(lesson1)
        shell.showPath()
        #expect(shell.activeLesson == nil)
        #expect(shell.selection == .unit(MacShellModel.pathUnitId(frontier: progress.frontier())))
    }

    @Test("Today's primary button with the whole path done shows the first unit")
    func openNilStopShowsFirstUnit() {
        let shell = makeShell()
        shell.open(nil)
        #expect(shell.selection == .unit(MercuriusCurriculum.units[0].id))
        #expect(shell.activeLesson == nil && shell.activeUnitTest == nil)
    }
}
#endif
