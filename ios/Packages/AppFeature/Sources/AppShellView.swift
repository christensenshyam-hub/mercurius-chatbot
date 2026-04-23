import SwiftUI
import DesignSystem
import ChatFeature
import CurriculumFeature
import ClubFeature
import NetworkingKit
import PersistenceKit
import SettingsFeature

/// The TabView host. Owns the selected-tab binding and, crucially, a
/// single shared `ChatViewModel` so switching tabs doesn't wipe the
/// conversation — and so lessons tapped in the Curriculum tab can
/// push a starter message into the existing chat.
///
/// Three tabs: Chat, Curriculum, Club. Settings stays as a sheet
/// accessible from the Chat tab's header.
struct AppShellView: View {

    // MARK: - Dependencies (from AppEnvironment)

    let apiClient: APIClient
    let sessionIdentity: SessionIdentity
    let chatStore: ChatStore?
    let themeStore: ThemePreferenceStore
    let clubClient: ClubDataProviding

    // MARK: - Shared state

    @State private var selectedTab: Tab = .chat
    @State private var chatModel: ChatViewModel
    @State private var progress = CurriculumProgressStore()
    @State private var clubModel: ClubViewModel

    /// Lesson the user asked to start while the chat had existing
    /// messages. Drives a confirmation alert that lets them choose
    /// whether to start fresh or add to the current conversation.
    @State private var pendingLesson: Lesson?

    enum Tab: Hashable { case chat, curriculum, club }

    init(
        apiClient: APIClient,
        sessionIdentity: SessionIdentity,
        chatStore: ChatStore?,
        themeStore: ThemePreferenceStore,
        clubClient: ClubDataProviding
    ) {
        self.apiClient = apiClient
        self.sessionIdentity = sessionIdentity
        self.chatStore = chatStore
        self.themeStore = themeStore
        self.clubClient = clubClient
        _chatModel = State(
            initialValue: ChatViewModel(
                apiClient: apiClient,
                sessionIdentity: sessionIdentity,
                store: chatStore
            )
        )
        _clubModel = State(
            initialValue: ClubViewModel(client: clubClient)
        )
    }

    // MARK: - Body

    var body: some View {
        TabView(selection: $selectedTab) {
            chatTab
                .tabItem { Label("Chat", systemImage: "bubble.left.and.bubble.right") }
                .tag(Tab.chat)

            curriculumTab
                .tabItem { Label("Curriculum", systemImage: "book") }
                .tag(Tab.curriculum)

            clubTab
                .tabItem { Label("Club", systemImage: "person.3") }
                .tag(Tab.club)
        }
        .tint(BrandColor.accent)
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
    }

    // MARK: - Tabs

    private var chatTab: some View {
        ChatView(
            model: chatModel,
            apiClient: apiClient,
            sessionIdentity: sessionIdentity,
            settingsPresenter: { [sessionIdentity, themeStore, chatStore] in
                AnyView(
                    SettingsSheet(
                        sessionIdentity: sessionIdentity,
                        themeStore: themeStore,
                        chatStore: chatStore
                    )
                )
            }
        )
    }

    private var curriculumTab: some View {
        CurriculumView(
            progress: progress,
            onStartLesson: handleStartLesson
        )
    }

    private var clubTab: some View {
        ClubView(model: clubModel)
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
