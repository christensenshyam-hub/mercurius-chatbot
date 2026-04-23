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
/// Two tabs for now: Chat and Curriculum. Settings stays as a sheet
/// accessible from the Chat tab's header; promoting Settings to a
/// tab would be warranted if we added Club/Profile later.
struct AppShellView: View {

    // MARK: - Dependencies (from AppEnvironment)

    let apiClient: APIClient
    let sessionIdentity: SessionIdentity
    let chatStore: ChatStore?
    let themeStore: ThemePreferenceStore

    // MARK: - Shared state

    @State private var selectedTab: Tab = .chat
    @State private var chatModel: ChatViewModel
    @State private var progress = CurriculumProgressStore()

    enum Tab: Hashable { case chat, curriculum }

    init(
        apiClient: APIClient,
        sessionIdentity: SessionIdentity,
        chatStore: ChatStore?,
        themeStore: ThemePreferenceStore
    ) {
        self.apiClient = apiClient
        self.sessionIdentity = sessionIdentity
        self.chatStore = chatStore
        self.themeStore = themeStore
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

            curriculumTab
                .tabItem { Label("Curriculum", systemImage: "book") }
                .tag(Tab.curriculum)
        }
        .tint(BrandColor.accent)
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
            onStartLesson: { lesson in
                // Queue the starter into the chat view model, switch
                // to the Chat tab, then send. The view model handles
                // the actual network request.
                chatModel.draft = lesson.starter
                progress.markCompleted(lesson.id)
                selectedTab = .chat
                // Defer send slightly so the tab swap animates first.
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(300))
                    chatModel.send()
                }
            }
        )
    }
}
