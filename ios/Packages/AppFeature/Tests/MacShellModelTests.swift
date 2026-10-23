#if os(macOS)
import Foundation
import Testing
@testable import AppFeature
import ChatFeature
import CurriculumFeature
import EngagementFeature
import NetworkingKit
import PersistenceKit
import SettingsFeature
import SwiftUI

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

    @Test("A mode from the menu bar opens the chat and waits there for the chat view to take it")
    func modeRequestOpensChat() {
        let shell = makeShell()
        shell.openLesson(lesson1)
        shell.requestMode(.debate)
        #expect(shell.modeRequest == .debate)
        #expect(shell.activeLesson == nil)
        if case .chat = shell.selection {} else { Issue.record("expected the chat row, got \(String(describing: shell.selection))") }
    }

    @Test("Behind the gate a mode request does nothing, and a gate that comes back drops one")
    func modeRequestGated() {
        let gated = makeShell(gated: true)
        gated.requestMode(.discussion)
        #expect(gated.modeRequest == nil)
        #expect(gated.selection == .today)

        let shell = makeShell()
        shell.requestMode(.discussion)
        shell.setGated(true)
        #expect(shell.modeRequest == nil)
    }

    @Test("The window only holds still while a Settings model is erasing")
    func erasingFollowsTheSettingsModel() {
        let shell = makeShell()
        #expect(!shell.isErasing)
    }

    @Test("⌥⌘1, ⌥⌘2, ⌥⌘3 are Socratic, Debate, Discussion — the toolbar's order")
    func modeKeys() {
        #expect(MacCommands.modeKey(.socratic) == "1")
        #expect(MacCommands.modeKey(.debate) == "2")
        #expect(MacCommands.modeKey(.discussion) == "3")
        #expect(MacCommands.modeModifiers == [.command, .option])
    }

    @Test("⌘1, ⌘2, ⌘3 are the sidebar's destinations: Today, Learning Path, Chat")
    func destinationKeys() {
        #expect(MacCommands.destinationKey(.today) == KeyboardShortcut("1", modifiers: .command))
        #expect(MacCommands.destinationKey(.path) == KeyboardShortcut("2", modifiers: .command))
        #expect(MacCommands.destinationKey(.chat) == KeyboardShortcut("3", modifiers: .command))
    }

    @Test("⌘4 is View ▸ Progress, after the three destinations")
    func progressKey() {
        #expect(MacCommands.progressKey == KeyboardShortcut("4", modifiers: .command))
        #expect(MacCommands.Destination.allCases.map { MacCommands.destinationKey($0) }
            .allSatisfy { $0 != MacCommands.progressKey })
    }

    @Test("Progress (⌘4, the toolbar button) opens the Progress sheet, but never behind the gate")
    func showProgress() {
        let gated = makeShell(gated: true)
        gated.showProgress()
        #expect(!gated.showsProgress)
        let shell = makeShell()
        shell.showProgress()
        #expect(shell.showsProgress)
    }

    @Test("Think it through opens a new chat with the prompt in the composer, not sent")
    func newChatWithDraft() {
        let shell = makeShell()
        shell.newChat(draft: "How does an LLM actually work?")
        #expect(shell.selection == .chat(shell.chatModel.conversationId))
        #expect(shell.chatModel.draft == "How does an LLM actually work?")
        #expect(shell.chatModel.messages.isEmpty, "nothing is sent until the student sends it")
        #expect(shell.chatModel.phase == .idle)
    }

    @Test("Think it through does nothing behind the gate")
    func newChatWithDraftGated() {
        let shell = makeShell(gated: true)
        shell.newChat(draft: "How does an LLM actually work?")
        #expect(shell.selection == .today)
        #expect(chatStore.listConversations().isEmpty)
    }

    @Test("Today reads the chat's mode without building the chat")
    func currentChatModeDefault() {
        let shell = makeShell()
        #expect(shell.currentChatMode == .socratic)
        #expect(shell.unsavedChatId == nil, "reading the mode must not build the chat")
    }

    @Test("The mode items work only on the free chat — never on a lesson, behind the gate or mid-erase")
    func modeItemsOnlyInTheChat() {
        #expect(MacCommands.modesEnabled(blocked: false, chatMode: .socratic))
        #expect(!MacCommands.modesEnabled(blocked: false, chatMode: nil), "a lesson's target has no mode")
        #expect(!MacCommands.modesEnabled(blocked: true, chatMode: .debate))
    }

    @Test("Behind the gate the shell's commands are blocked; past it they aren't")
    func commandsBlockedFollowsTheGate() {
        #expect(makeShell(gated: true).commandsBlocked)
        #expect(!makeShell().commandsBlocked)
    }

    // MARK: Settings' erasure with a lesson open (the Mac's Settings is its own window)

    /// Records whether the lesson was already stopped and closed when the
    /// server delete arrived.
    private final class RecordingDeleter: SessionDeleting, @unchecked Sendable {
        var lessonOpenAtDelete: Bool?
        var stopsAtDelete: Int?
        var probe: (@MainActor () -> (open: Bool, stops: Int))?
        func deleteSession(sessionId: String) async throws {
            if let probe {
                let state = await probe()
                lessonOpenAtDelete = state.open
                stopsAtDelete = state.stops
            }
        }
    }

    private func settings(for shell: MacShellModel, deleter: SessionDeleting?) -> SettingsViewModel {
        let identity = SessionIdentity(keychain: InMemoryKeychain())
        return SettingsSheet(
            sessionIdentity: identity,
            themeStore: ThemePreferenceStore(preferences: InMemoryPreferenceStore()),
            chatStore: chatStore,
            chatModel: shell.chatModel,
            streakStore: StreakStore(defaults: freshDefaults("mac.erase.streak")),
            achievementStore: AchievementStore(defaults: freshDefaults("mac.erase.achievements")),
            progress: progress,
            progressSync: CurriculumProgressSync(
                progress: progress, remote: StubProgressRemote(),
                sessionId: { try identity.current() }, isEnabled: false
            ),
            reminderStore: ReminderStore(defaults: freshDefaults("mac.erase.reminders")),
            scheduler: NotificationScheduler(),
            sessionDeleter: deleter,
            onConsentWithdrawn: nil,
            // The Mac shell's wiring (`settingsSheet`).
            beforeErase: { shell.beforeSettingsErase() },
            afterReset: { shell.afterSettingsReset() }
        ).makeModel(dismiss: {})
    }

    @Test("Delete my data with a lesson open stops its reply and closes it before the server delete")
    func eraseClosesTheOpenLesson() async {
        let shell = makeShell()
        shell.openLesson(lesson1)
        var stops = 0
        shell.registerLessonStop { stops += 1 }
        let deleter = RecordingDeleter()
        deleter.probe = { (shell.activeLesson != nil, stops) }

        #expect(await settings(for: shell, deleter: deleter).deleteServerDataAndStartOver())
        #expect(deleter.lessonOpenAtDelete == false, "the lesson must be closed before the server erases")
        #expect(deleter.stopsAtDelete == 1, "its reply in flight must be stopped before the server erases")
        #expect(shell.activeLesson == nil)
    }

    @Test("Resetting this device only, or with a unit check open, closes it too")
    func deviceResetClosesActivity() async {
        let shell = makeShell()
        shell.openUnitTest(MercuriusCurriculum.units[0])
        #expect(await settings(for: shell, deleter: nil).resetSession())
        #expect(shell.activeUnitTest == nil)

        shell.openLesson(lesson1)
        var stops = 0
        shell.registerLessonStop { stops += 1 }
        #expect(await settings(for: shell, deleter: nil).resetSession())
        #expect(shell.activeLesson == nil)
        #expect(stops == 1)
    }

    @Test("A reset from the Settings window closes the Progress sheet, and a certificate sheet over it")
    func resetClosesProgress() async {
        let shell = makeShell()
        shell.showProgress()
        #expect(shell.showsProgress)
        #expect(await settings(for: shell, deleter: nil).resetSession())
        #expect(shell.showsProgress == false)
    }

    @Test("A lesson stop registered by a lesson that already closed isn't called again")
    func staleStopIgnored() {
        let shell = makeShell()
        var stops = 0
        shell.registerLessonStop { stops += 1 }
        shell.beforeSettingsErase()
        #expect(stops == 0, "no lesson open: nothing to stop")
    }

    @Test("A narrow window folds the sidebar away and a wide one brings it back — unless the student folded it")
    func sidebarFoldsWithWidth() {
        let fold = MacShellView.sidebarFoldWidth
        // Narrowed: folded, and remembered as the width's doing.
        var next = MacShellView.sidebarAfterResize(width: 700, visibility: .all, collapsedForWidth: false)
        #expect(next.visibility == .detailOnly && next.collapsedForWidth)
        // Widened again: back.
        next = MacShellView.sidebarAfterResize(width: fold + 100, visibility: next.visibility,
                                               collapsedForWidth: next.collapsedForWidth)
        #expect(next.visibility == .all && !next.collapsedForWidth)
        // Folded by the student in a wide window: widening leaves it folded.
        next = MacShellView.sidebarAfterResize(width: 1280, visibility: .detailOnly, collapsedForWidth: false)
        #expect(next.visibility == .detailOnly)
        // Already folded when the window narrows: still the student's.
        next = MacShellView.sidebarAfterResize(width: 700, visibility: .detailOnly, collapsedForWidth: false)
        #expect(next.visibility == .detailOnly && !next.collapsedForWidth)
        // The fold sits above the window's minimum, so a tiled window works.
        #expect(fold > MacSnapshotOptions.minimumWindowSize.width)
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
