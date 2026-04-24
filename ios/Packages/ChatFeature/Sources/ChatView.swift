import SwiftUI
import DesignSystem
import NetworkingKit
import PersistenceKit

/// The root chat screen. Owns the view model and composes the message
/// list, input bar, and empty state.
public struct ChatView: View {
    @State private var model: ChatViewModel
    @State private var showSettings = false
    @State private var activeTool: ActiveTool?

    /// First-launch hint above the input bar. Visible only when the
    /// chat is empty AND the user hasn't dismissed it once. The X
    /// button on the hint is the only explicit dismissal path;
    /// sending a first message implicitly hides it because
    /// `model.messages.isEmpty` flips to false.
    @AppStorage(ChatInputHint.storageKey) private var hasSeenChatInputHint: Bool = false

    private enum ActiveTool: Identifiable {
        case quiz, reportCard
        var id: String {
            switch self {
            case .quiz: return "quiz"
            case .reportCard: return "reportCard"
            }
        }
    }

    private let apiClient: APIClient
    private let sessionIdentity: SessionIdentity

    /// Closure the host app provides to surface the Settings screen.
    /// Kept as a closure so `ChatFeature` doesn't depend on
    /// `SettingsFeature` — composition lives in `AppFeature`.
    private let settingsPresenter: (@MainActor () -> AnyView)?

    /// Optional escape hatch: if provided, renders a leading "Home"
    /// button in the header that invokes this closure. `AppFeature`
    /// wires it up to return the user to the branded HomeView so the
    /// chat tab never feels like a dead-end. Left optional so
    /// previews / tests / any future non-TabView host can omit it.
    private let onGoHome: (@MainActor () -> Void)?

    public init(
        apiClient: APIClient,
        sessionIdentity: SessionIdentity,
        chatStore: ChatStore? = nil,
        settingsPresenter: (@MainActor () -> AnyView)? = nil,
        onGoHome: (@MainActor () -> Void)? = nil
    ) {
        _model = State(
            initialValue: ChatViewModel(
                apiClient: apiClient,
                sessionIdentity: sessionIdentity,
                store: chatStore
            )
        )
        self.apiClient = apiClient
        self.sessionIdentity = sessionIdentity
        self.settingsPresenter = settingsPresenter
        self.onGoHome = onGoHome
    }

    /// Alternate initializer used by `AppShellView`: share an existing
    /// ViewModel across tabs so the conversation survives tab switches
    /// and curriculum starters can push messages into the live chat.
    public init(
        model: ChatViewModel,
        apiClient: APIClient,
        sessionIdentity: SessionIdentity,
        settingsPresenter: (@MainActor () -> AnyView)? = nil,
        onGoHome: (@MainActor () -> Void)? = nil
    ) {
        _model = State(initialValue: model)
        self.apiClient = apiClient
        self.sessionIdentity = sessionIdentity
        self.settingsPresenter = settingsPresenter
        self.onGoHome = onGoHome
    }

    public var body: some View {
        ZStack(alignment: .top) {
            BrandColor.background.ignoresSafeArea()

            VStack(spacing: 0) {
                header
                ModeSelectorView(model: model)
                    .background(BrandColor.background)
                Divider().overlay(BrandColor.border)

                if model.messages.isEmpty {
                    EmptyChatView(
                        suggestions: ModePromptProvider.prompts(for: model.currentMode),
                        onSuggestion: { suggestion in
                            model.draft = suggestion
                            model.send()
                        }
                    )
                    // Re-key the view on the active mode so a mode
                    // switch crossfades the prompt chips rather than
                    // snap-replacing them. Cheap and obvious to the
                    // eye; tells the user "the suggestions just
                    // changed because of what you tapped."
                    .id(model.currentMode)
                    .transition(.opacity)
                    .animation(.easeInOut(duration: 0.2), value: model.currentMode)
                    .frame(maxHeight: .infinity)
                } else {
                    MessageListView(
                        messages: model.messages,
                        phase: model.phase,
                        onRetry: { model.retry() }
                    )
                }

                if model.messages.isEmpty && !hasSeenChatInputHint {
                    ChatInputHint(onDismiss: dismissChatInputHint)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }

                ChatInputBar(
                    text: Binding(
                        get: { model.draft },
                        set: { model.draft = $0 }
                    ),
                    isSending: isSending,
                    onSend: { model.send() },
                    onCancel: { model.cancel() }
                )
            }
        }
        // Animate the hint's appearance + dismissal so the transition
        // doesn't snap when `hasSeenChatInputHint` flips. Scoped to
        // just that state so other view churn isn't animated.
        .animation(.easeInOut(duration: 0.25), value: hasSeenChatInputHint)
    }

    private func dismissChatInputHint() {
        hasSeenChatInputHint = true
    }

    private var isSending: Bool {
        switch model.phase {
        case .sending, .streaming: return true
        case .idle, .failed: return false
        }
    }

    private var header: some View {
        HStack(spacing: BrandSpacing.md) {
            BrandLogo(style: .mark, size: 32)
            VStack(alignment: .leading, spacing: 0) {
                // `lineLimit(1) + minimumScaleFactor` caps growth at extreme
                // Dynamic Type sizes so the brand header doesn't wrap onto
                // three lines and push content out of the safe area.
                Text("Mercurius AI")
                    .font(BrandFont.subheading)
                    .foregroundStyle(BrandColor.text)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                Text("AI LITERACY TUTOR")
                    .font(BrandFont.caption)
                    .tracking(1.5)
                    .foregroundStyle(BrandColor.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            Spacer()
            toolsMenuButton
            if settingsPresenter != nil {
                Button {
                    showSettings = true
                } label: {
                    Image(systemName: "gearshape")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(BrandColor.textSecondary)
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel("Settings")
            }
            // Home is the rightmost trailing item so it reads as
            // "exit this context" rather than an in-screen control
            // — mirroring how Cancel/Done sit at the trailing edge
            // of iOS toolbars. Separated visually by being the last
            // item in the HStack.
            if let onGoHome {
                Button {
                    onGoHome()
                } label: {
                    Image(systemName: "house")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(BrandColor.textSecondary)
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel("Home")
                .accessibilityHint("Return to the Mercurius home screen")
            }
        }
        .padding(.leading, BrandSpacing.lg)
        .padding(.trailing, 4)
        .padding(.vertical, BrandSpacing.sm)
        .background(BrandColor.background)
        .sheet(isPresented: $showSettings) {
            settingsPresenter?()
        }
        .sheet(item: $activeTool) { tool in
            switch tool {
            case .quiz:
                QuizView(
                    model: QuizViewModel(
                        tools: apiClient,
                        sessionIdProvider: { [sessionIdentity] in
                            try sessionIdentity.current()
                        }
                    ),
                    dismissAction: { activeTool = nil }
                )
            case .reportCard:
                ReportCardView(
                    model: ReportCardViewModel(
                        tools: apiClient,
                        sessionIdProvider: { [sessionIdentity] in
                            try sessionIdentity.current()
                        }
                    ),
                    dismissAction: { activeTool = nil }
                )
            }
        }
    }

    private var toolsMenuButton: some View {
        Menu {
            Button {
                activeTool = .quiz
            } label: {
                Label("Generate Quiz", systemImage: "checkmark.rectangle.stack")
            }
            .disabled(!hasEnoughConversation)

            Button {
                activeTool = .reportCard
            } label: {
                Label("Report Card", systemImage: "chart.bar.doc.horizontal")
            }
            .disabled(!hasEnoughConversation)

            if !hasEnoughConversation {
                Divider()
                Text("Chat a bit more to unlock tools.")
            }
        } label: {
            Image(systemName: "square.grid.2x2")
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(BrandColor.textSecondary)
                .frame(width: 44, height: 44)
        }
        .accessibilityLabel("Tools")
    }

    /// The server rejects quiz / report-card requests if the conversation
    /// has fewer than 4 messages. Match that client-side for fast
    /// feedback and to avoid a pointless round-trip.
    private var hasEnoughConversation: Bool {
        model.messages.filter { $0.role == .user }.count >= 2
            && model.messages.count >= 4
    }
}

/// Scrollable list that auto-scrolls to the bottom when a new message
/// appears or when the last message's content grows (streaming).
struct MessageListView: View {
    let messages: [ChatMessage]
    let phase: ChatViewModel.Phase
    let onRetry: () -> Void

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: BrandSpacing.sm) {
                    ForEach(messages) { message in
                        MessageBubbleView(message: message)
                            .id(message.id)
                    }

                    if case .failed(_, let isRetryable) = phase, isRetryable {
                        retryFooter
                            .id("retry-footer")
                    }
                }
                .padding(.vertical, BrandSpacing.md)
            }
            .onChange(of: messages.last?.id) { _, newValue in
                guard let newValue else { return }
                withAnimation(.easeOut(duration: 0.25)) {
                    proxy.scrollTo(newValue, anchor: .bottom)
                }
            }
            .onChange(of: messages.last?.content) { _, _ in
                // During streaming, keep the bottom anchored so new
                // content is visible without yanking the user around.
                guard let id = messages.last?.id else { return }
                proxy.scrollTo(id, anchor: .bottom)
            }
        }
    }

    private var retryFooter: some View {
        HStack {
            Spacer()
            Button(action: onRetry) {
                Label("Retry", systemImage: "arrow.clockwise")
                    .font(BrandFont.caption)
                    .padding(.vertical, BrandSpacing.sm)
                    .padding(.horizontal, BrandSpacing.md)
                    .background(BrandColor.surfaceElevated)
                    .foregroundStyle(BrandColor.accent)
                    .clipShape(Capsule())
            }
            .frame(minHeight: 44)
            .accessibilityLabel("Retry sending the last message")
            Spacer()
        }
        .padding(.bottom, BrandSpacing.sm)
    }
}
