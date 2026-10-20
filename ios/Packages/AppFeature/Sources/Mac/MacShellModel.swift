#if os(macOS)
import Foundation
import Observation
import ChatFeature
import CurriculumFeature
import EngagementFeature
import NetworkingKit
import PersistenceKit
import SettingsFeature

/// The Mac window's navigation state and its one shared `ChatViewModel`.
///
/// iOS keeps this state inside `AppShellView`; on the Mac it has to outlive
/// any one view, because three places act on it: the window's
/// `NavigationSplitView` (`MacShellView`), the menu bar (`MacCommands`: New
/// Chat, Today, …) and the Settings window (whose resets must clear the same
/// chat the window shows). `AppEnvironment` owns the single instance.
///
/// Nothing here talks to the network on its own. The chat model is built on
/// first use, and the first use comes after the consent gate: while it
/// shows, the window's detail column is the gate, the sidebar is hidden, the
/// menu commands do nothing (`isGated`), and the Settings window shows a
/// placeholder until consent is on record.
@MainActor
@Observable
public final class MacShellModel {

    /// A sidebar row.
    public enum Destination: Hashable, Sendable {
        /// Merc's welcome: the next stop, this week, Chat with Merc
        /// (`HomeView`, the iOS doorman, as a page).
        case today
        /// One unit's stretch of the learning path.
        case unit(String)
        /// The free chat, on this thread. Saved threads are sidebar rows
        /// tagged with their id. A new thread that has no saved message yet
        /// is the sidebar's New Chat row (`unsavedChatId`); `.chat(nil)` is
        /// that row when it stands for no thread, and selecting it starts
        /// one.
        case chat(UUID?)
    }

    /// The selected sidebar row. Set directly only by code that already
    /// decided what the detail shows; a click goes through `show(_:)`.
    public internal(set) var selection: Destination? = .today

    /// The lesson filling the detail column, under its unit's row. nil when
    /// none is open.
    var activeLesson: Lesson?

    /// The unit check filling the detail column. Qualified because Foundation
    /// also exports a `Unit` type.
    var activeUnitTest: CurriculumFeature.Unit?

    /// The consent gate is showing in the window. Set by the shell; the menu
    /// commands do nothing while it is true.
    public private(set) var isGated = true

    /// The Progress hub (streak, achievements), from the streak chip.
    var showsProgress = false

    /// The Settings window's model, kept past the window's life: an erasure
    /// it started runs on after the window closes.
    var settingsModel: SettingsViewModel?

    /// Settings is deleting the student's data or resetting the session.
    /// The window holds still meanwhile: a message sent now would go out
    /// under the old ID (on the iPhone the Settings sheet can't be left
    /// then; the Mac's Settings window can).
    public var isErasing: Bool {
        guard let settingsModel else { return false }
        return settingsModel.isDeleteInProgress || settingsModel.isResetInProgress
    }

    /// The menu bar's shell commands are off: the gate shows, or Settings
    /// is erasing (a mode switch, a send or an opened thread would reach the
    /// server under the old ID).
    public var commandsBlocked: Bool { isGated || isErasing }

    /// A chat mode the menu bar asked for (Chat ▸ Socratic / Debate /
    /// Discussion). The chat view takes it — the explainer the first time,
    /// then the switch — and clears it.
    var modeRequest: ChatMode?

    /// Saved free-chat threads with at least one message, newest first, for
    /// the sidebar. Re-read on demand (`refreshConversations`).
    private(set) var conversations: [ConversationSummary] = []

    /// Set by the entry view: withdrawing consent in the Settings window
    /// drops the main window back to the gate.
    @ObservationIgnored var onConsentWithdrawn: (@MainActor () -> Void)?

    /// The entry view's reminder scheduler (it owns the re-plan), for the
    /// Settings window's resets. Replaced by the entry view's own on appear.
    @ObservationIgnored var scheduler = NotificationScheduler()

    @ObservationIgnored private let progress: CurriculumProgressStore
    @ObservationIgnored private let lastActivityStore: LastActivityStore
    @ObservationIgnored private let chatStore: ChatStore?
    @ObservationIgnored private let makeChatModel: @MainActor () -> ChatViewModel
    /// Observed, so the sidebar's New Chat row follows the chat's thread.
    private var builtChatModel: ChatViewModel?

    /// The thread open the sidebar or a menu asked for last. Opens run one
    /// at a time, newest last (`route`).
    @ObservationIgnored private var openTask: Task<Void, Never>?
    /// Thread opens queued or running. While any is, the chat's thread
    /// changing is an open landing, not a reason to move the sidebar's
    /// highlight (`MacShellView.chatView`).
    @ObservationIgnored private(set) var queuedOpens = 0
    var isOpeningThread: Bool { queuedOpens > 0 }

    /// Stops a reply the open lesson is still receiving. Registered by the
    /// lesson as it appears (`CurriculumLessonView(onRegisterStop:)`).
    @ObservationIgnored private var lessonStop: (@MainActor () -> Void)?

    init(
        progress: CurriculumProgressStore,
        lastActivityStore: LastActivityStore,
        chatStore: ChatStore?,
        makeChatModel: @escaping @MainActor () -> ChatViewModel
    ) {
        self.progress = progress
        self.lastActivityStore = lastActivityStore
        self.chatStore = chatStore
        self.makeChatModel = makeChatModel
    }

    /// The free chat's view model, built on first use and kept for the
    /// process (like `AppShellView`'s), so leaving the chat row keeps the
    /// thread and any reply still streaming into it.
    var chatModel: ChatViewModel {
        if let builtChatModel { return builtChatModel }
        let made = makeChatModel()
        builtChatModel = made
        return made
    }

    // MARK: - Menu and sidebar (user actions)

    /// A sidebar click or a menu command: show that row, closing any open
    /// lesson or check. A saved thread's row opens that thread.
    public func show(_ destination: Destination) {
        guard !isGated else { return }
        route(to: destination)
    }

    /// The sidebar list's selection changed. A row routes like `show(_:)`;
    /// nil (the list deselecting, e.g. a click on empty space below the
    /// rows) keeps what the detail shows, so its row stays selected. The
    /// New Chat row, when it stands for no thread (`.chat(nil)`), starts one.
    public func select(_ destination: Destination?) {
        guard let destination else { return }
        if destination == .chat(nil) {
            newChat()
        } else {
            show(destination)
        }
    }

    /// The chat's current thread while no sidebar row lists it — a new
    /// thread before its first saved message, which the sidebar's New Chat
    /// row stands for. nil before the chat exists (behind the gate it is
    /// never built here) or once the thread has its own row.
    var unsavedChatId: UUID? {
        guard let id = builtChatModel?.conversationId else { return nil }
        return conversations.contains { $0.id == id } ? nil : id
    }

    /// View ▸ Chat (⌘3), Today's "Chat with Merc": the current thread.
    public func showChat() {
        guard !isGated else { return }
        openChat()
    }

    /// View ▸ Learning Path (⌘2): the unit holding the next stop.
    public func showPath() {
        guard !isGated else { return }
        activeLesson = nil
        activeUnitTest = nil
        selection = .unit(Self.pathUnitId(frontier: progress.frontier()))
    }

    /// Chat ▸ Socratic / Debate / Discussion (⌥⌘1–⌥⌘3): the chat, in that
    /// mode. The switch itself is the chat view's (`ChatView.macChrome`), so
    /// a menu command and the toolbar picker behave alike.
    public func requestMode(_ mode: ChatMode) {
        guard !isGated else { return }
        modeRequest = mode
        openChat()
    }

    /// File ▸ New Chat (⌘N) and the sidebar's New Chat row: a fresh thread
    /// in the current mode, in the detail column.
    public func newChat() {
        guard !isGated else { return }
        chatModel.startNewConversation()
        openChat()
    }

    // MARK: - Routing

    private func route(to destination: Destination) {
        activeLesson = nil
        activeUnitTest = nil
        selection = destination
        guard case .chat(let id?) = destination, id != chatModel.conversationId || isOpeningThread else { return }
        // Opens run one at a time, and only the newest selection's runs. A
        // thread in another mode switches the server's mode first
        // (`openConversation`), and two of those racing could land out of
        // order, leaving the chat — and the highlight — on an older pick.
        // So each open waits for the one before it, then a moment more (a
        // key held on ↓ skims past threads without opening each, or
        // switching the server's mode for each), and goes ahead only if
        // its thread is still the one selected.
        let previous = openTask
        queuedOpens += 1
        openTask = Task { @MainActor [weak self] in
            await previous?.value
            try? await Task.sleep(for: Self.openSettle)
            guard let self else { return }
            defer { self.queuedOpens -= 1 }
            guard self.selection == .chat(id) else { return }
            guard id != self.chatModel.conversationId else {
                self.refreshConversations()
                return
            }
            // Only past the gate: the mode switch reaches the server.
            let opened = await self.chatModel.openConversation(id: id)
            // A thread that can't open (deleted meanwhile, or saved in a
            // mode this build no longer has, like the betas' "direct")
            // leaves the chat on its current thread: select that one, so
            // the sidebar never highlights a thread the detail isn't
            // showing.
            if !opened, self.selection == .chat(id) {
                self.selection = .chat(self.chatModel.conversationId)
            }
            self.refreshConversations()
        }
    }

    /// How long a selected thread waits before it opens, so arrowing
    /// through the sidebar opens only where the student stops.
    static let openSettle: Duration = .milliseconds(150)

    /// Wait for the queued thread opens (tests).
    func settleOpens() async {
        await openTask?.value
    }

    /// The chat detail on the current thread (unguarded: the first-run
    /// flow's "Just chat" calls it as the gate clears).
    func openChat() {
        route(to: .chat(chatModel.conversationId))
    }

    /// Open a lesson in the detail column, under its unit's row. Open-only,
    /// as on iOS (`AppShellView.handleStartLesson`): the lesson turns "in
    /// progress" once its conversation exists and complete only when the
    /// server reports proficiency.
    func openLesson(_ lesson: Lesson) {
        progress.markOpened(lesson.id)
        lastActivityStore.touch()
        activeUnitTest = nil
        if let unit = MercuriusCurriculum.unit(containingLesson: lesson.id) {
            selection = .unit(unit.id)
        }
        activeLesson = lesson
    }

    /// Open a unit's check in the detail column, under its unit's row.
    func openUnitTest(_ unit: CurriculumFeature.Unit) {
        lastActivityStore.touch()
        activeLesson = nil
        selection = .unit(unit.id)
        activeUnitTest = unit
    }

    /// Open a path stop (Today's primary button). nil — the whole path is
    /// done — shows the first unit's page.
    func open(_ stop: MercuriusCurriculum.PathStop?) {
        switch stop {
        case .lesson(let lesson): openLesson(lesson)
        case .unitTest(let unit): openUnitTest(unit)
        case nil:
            activeLesson = nil
            activeUnitTest = nil
            selection = .unit(Self.pathUnitId(frontier: nil))
        }
    }

    /// Close the lesson or check, back to its unit's page.
    func closeActivity() {
        activeLesson = nil
        activeUnitTest = nil
    }

    /// The open lesson hands over how to stop its reply in flight.
    func registerLessonStop(_ stop: @escaping @MainActor () -> Void) {
        lessonStop = stop
    }

    /// Settings' hook before an erasure reaches the server
    /// (`settingsSheet`'s `beforeErase`).
    func beforeSettingsErase() {
        stopActivityForErase()
    }

    /// Settings' hook after a reset cleared the on-device state: nothing of
    /// the old session stays open, and the sidebar re-reads its chats.
    func afterSettingsReset() {
        stopActivityForErase()
        refreshConversations()
    }

    /// Settings is about to erase (or has reset) this student's data: stop a
    /// lesson reply still coming in under the old ID — before the server
    /// delete, or its completion would re-create the session — and close the
    /// lesson or check, so nothing from the erased session stays on screen
    /// or is replayed to the server under the new ID by a later send.
    func stopActivityForErase() {
        if activeLesson != nil { lessonStop?() }
        lessonStop = nil
        closeActivity()
    }

    /// The unit page "Learning Path" opens: the next stop's unit, else the
    /// first unit.
    static func pathUnitId(frontier: MercuriusCurriculum.PathStop?) -> String {
        switch frontier {
        case .lesson(let lesson):
            if let unit = MercuriusCurriculum.unit(containingLesson: lesson.id) { return unit.id }
        case .unitTest(let unit):
            return unit.id
        case nil:
            break
        }
        return MercuriusCurriculum.units.first?.id ?? ""
    }

    // MARK: - Saved threads

    /// Delete a saved thread (sidebar context menu, after confirming).
    func deleteConversation(_ id: UUID) {
        chatModel.deleteConversation(id: id)
        if case .chat(id) = selection { selection = .chat(chatModel.conversationId) }
        refreshConversations()
    }

    /// Re-read the saved threads from the on-device store (no network).
    func refreshConversations() {
        conversations = Self.sidebarConversations(chatStore?.listConversations() ?? [])
    }

    /// The threads the sidebar lists: only ones with messages. A fresh
    /// "New chat" record stays empty until the first send.
    nonisolated static func sidebarConversations(_ all: [ConversationSummary]) -> [ConversationSummary] {
        all.filter { $0.messageCount > 0 }
    }

    // MARK: - Gate

    /// The shell reports the gate. While it shows, nothing in the shell is
    /// reachable; a gate that comes back (consent withdrawn) also closes
    /// whatever was open and returns to Today.
    func setGated(_ gated: Bool) {
        guard gated != isGated else { return }
        isGated = gated
        if gated {
            activeLesson = nil
            activeUnitTest = nil
            showsProgress = false
            modeRequest = nil
            selection = .today
            conversations = []
        }
    }
}
#endif
