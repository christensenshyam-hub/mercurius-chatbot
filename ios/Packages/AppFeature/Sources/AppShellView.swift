import SwiftUI
import DesignSystem
import ChatFeature
import CurriculumFeature
import NetworkingKit
import PersistenceKit
import SettingsFeature

/// The TabView host. Owns the selected-tab binding and, crucially, a
/// single shared `ChatViewModel` so switching tabs doesn't wipe the
/// conversation — and so lessons tapped in the Curriculum tab can
/// push a starter message into the existing chat.
///
/// Four tab-bar items:
/// - **Chat** and **Curriculum** are real navigation destinations.
/// - **New Chat** and **History** are *action* tab items: tapping
///   them fires a side effect (start a fresh conversation; present
///   the history sheet) and immediately reverts selection to the
///   previous tab. Pattern matches Instagram-style "+" buttons in
///   the tab bar — non-destinations rendered alongside destinations
///   because the user model is "common actions live in the bottom
///   bar."
/// - Settings stays as a sheet accessible from the Chat tab's
///   header; a leading Home button in the chat header returns the
///   user to the branded `HomeView`.
struct AppShellView: View {

    // MARK: - Dependencies (from AppEnvironment)

    let apiClient: APIClient
    let sessionIdentity: SessionIdentity
    let chatStore: ChatStore?
    let themeStore: ThemePreferenceStore

    /// Called when the user taps the Home button in the chat header.
    /// `AppEntryView` wires this to flip `hasEnteredApp` back to
    /// false, which returns the user to `HomeView`.
    let onGoHome: @MainActor () -> Void

    // MARK: - Shared state

    @State private var selectedTab: Tab = .chat
    @State private var chatModel: ChatViewModel
    @State private var progress = CurriculumProgressStore()

    /// Drives presentation of the Chat History sheet. Set to true by
    /// the `.history` tab-action; cleared by the row tap or the
    /// Close toolbar button.
    @State private var showChatHistory: Bool = false

    /// Lesson the user asked to start while the chat had existing
    /// messages. Drives a confirmation alert that lets them choose
    /// whether to start fresh or add to the current conversation.
    @State private var pendingLesson: Lesson?

    enum Tab: Hashable {
        case chat
        case history       // action: present chat-history sheet
        case newChat       // action: startNewConversation()
        case curriculum
    }

    init(
        apiClient: APIClient,
        sessionIdentity: SessionIdentity,
        chatStore: ChatStore?,
        themeStore: ThemePreferenceStore,
        onGoHome: @escaping @MainActor () -> Void
    ) {
        self.apiClient = apiClient
        self.sessionIdentity = sessionIdentity
        self.chatStore = chatStore
        self.themeStore = themeStore
        self.onGoHome = onGoHome
        _chatModel = State(
            initialValue: ChatViewModel(
                apiClient: apiClient,
                sessionIdentity: sessionIdentity,
                store: chatStore
            )
        )
    }

    // MARK: - Body

    var body: some View {
        TabView(selection: $selectedTab) {
            chatTab
                .tabItem { Label("Chat", systemImage: "bubble.left.and.bubble.right") }
                .tag(Tab.chat)

            // The History tab is an action — the body just mirrors
            // the chat tab's content so the visual transition during
            // tap-then-revert doesn't flash empty. The sheet
            // attached below the TabView is what the user actually
            // sees once `showChatHistory` flips on.
            chatTab
                .tabItem { Label("History", systemImage: "clock.arrow.circlepath") }
                .tag(Tab.history)

            // Same pattern: action tab. `square.and.pencil` is the
            // standard iOS "compose / new" symbol — recognizable.
            chatTab
                .tabItem { Label("New Chat", systemImage: "square.and.pencil") }
                .tag(Tab.newChat)

            curriculumTab
                .tabItem { Label("Curriculum", systemImage: "book") }
                .tag(Tab.curriculum)
        }
        .tint(BrandColor.accent)
        .onChange(of: selectedTab) { oldValue, newValue in
            handleSelection(from: oldValue, to: newValue)
        }
        // Confirmation alert for starting a lesson on top of an existing
        // conversation. The `.alert(presenting:)` form binds to an optional
        // so the alert only shows while `pendingLesson` is non-nil.
        .alert(
            "Start this lesson?",
            isPresented: Binding(
                get: { pendingLesson != nil },
                set: { if !$0 { pendingLesson = nil } }
            ),
            presenting: pendingLesson
        ) { lesson in
            Button("New chat") { startLesson(lesson, inNewChat: true) }
            Button("Add to current") { startLesson(lesson, inNewChat: false) }
            Button("Cancel", role: .cancel) { pendingLesson = nil }
        } message: { lesson in
            Text("\"\(lesson.title)\" — would you like a clean slate for this lesson, or add it to your current conversation?")
        }
        .sheet(isPresented: $showChatHistory) {
            // Wrapped in NavigationStack so ChatHistoryView gets
            // its title bar + filter pill chrome.
            NavigationStack {
                ChatHistoryView(
                    load: { chatModel.archivedConversations() },
                    onSelect: { id in
                        showChatHistory = false
                        // Defer the open slightly so the sheet
                        // dismissal animation runs cleanly before
                        // the chat thread re-renders behind it.
                        Task { @MainActor in
                            try? await Task.sleep(for: .milliseconds(200))
                            await chatModel.openConversation(id: id)
                        }
                    },
                    onDelete: { id in
                        chatModel.deleteConversation(id: id)
                    }
                )
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Close") { showChatHistory = false }
                            .accessibilityHint("Closes the chat history list")
                    }
                }
            }
            .tint(BrandColor.accent)
        }
    }

    // MARK: - Tab selection

    /// Tab-bar tap handler. Real navigation tabs (`.chat`,
    /// `.curriculum`) just pass through. Action tabs (`.history`,
    /// `.newChat`) fire their side effect and revert `selectedTab`
    /// to wherever the user was before — so the action tab never
    /// stays "selected." Reverting triggers another `onChange` whose
    /// `newValue` is one of the real tabs, which falls through the
    /// switch with no further action — no infinite loop.
    private func handleSelection(from oldValue: Tab, to newValue: Tab) {
        switch newValue {
        case .history:
            showChatHistory = true
            selectedTab = oldValue == .history ? .chat : oldValue
        case .newChat:
            chatModel.startNewConversation()
            selectedTab = oldValue == .newChat ? .chat : oldValue
        case .chat, .curriculum:
            break
        }
    }

    // MARK: - Tabs

    private var chatTab: some View {
        ChatView(
            model: chatModel,
            apiClient: apiClient,
            sessionIdentity: sessionIdentity,
            settingsPresenter: { [sessionIdentity, themeStore, chatStore, chatModel] in
                AnyView(
                    SettingsSheet(
                        sessionIdentity: sessionIdentity,
                        themeStore: themeStore,
                        chatStore: chatStore,
                        chatModel: chatModel
                    )
                )
            },
            onGoHome: onGoHome
        )
    }

    private var curriculumTab: some View {
        CurriculumView(
            progress: progress,
            onStartLesson: handleStartLesson
        )
    }

    // MARK: - Lesson launch

    /// Curriculum tapped a lesson. If the chat has existing messages we
    /// ask the user whether to keep that conversation or start fresh;
    /// otherwise we just kick the lesson off immediately.
    private func handleStartLesson(_ lesson: Lesson) {
        if chatModel.messages.isEmpty {
            startLesson(lesson, inNewChat: false)
        } else {
            pendingLesson = lesson
        }
    }

    /// Run the lesson's starter. If `inNewChat` is true, the existing
    /// conversation is archived (preserved in the store) and a fresh
    /// one is opened before the starter is sent.
    private func startLesson(_ lesson: Lesson, inNewChat: Bool) {
        pendingLesson = nil
        if inNewChat {
            chatModel.startNewConversation()
        }
        chatModel.draft = lesson.starter
        progress.markCompleted(lesson.id)
        selectedTab = .chat
        // Defer send slightly so the tab swap animates first.
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(300))
            chatModel.send()
        }
    }
}
