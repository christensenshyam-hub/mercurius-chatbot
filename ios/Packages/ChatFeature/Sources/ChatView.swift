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
                    EmptyChatView { suggestion in
                        model.draft = suggestion
                        model.send()
                    }
                    .frame(maxHeight: .infinity)
                } else {
                    MessageListView(
                        messages: model.messages,
                        phase: model.phase,
                        onRetry: { model.retry() }
                    )
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
    }

    private var isSending: Bool {
        switch model.phase {
        case .sending, .streaming: return true
        case .idle, .failed: return false
        }
    }

    private var header: some View {
        HStack(spacing: BrandSpacing.md) {
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
        }
        // When the Home button is present it brings its own leading
        // padding via its 44pt hit target; otherwise pad to match the
        // previous look.
        .padding(.leading, onGoHome == nil ? BrandSpacing.lg : 4)
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
