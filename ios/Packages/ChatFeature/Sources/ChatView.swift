import SwiftUI
import DesignSystem
import NetworkingKit

/// The root chat screen. Owns the view model and composes the message
/// list, input bar, and empty state.
public struct ChatView: View {
    @State private var model: ChatViewModel

    public init(apiClient: APIClient, sessionIdentity: SessionIdentity) {
        _model = State(
            initialValue: ChatViewModel(
                apiClient: apiClient,
                sessionIdentity: sessionIdentity
            )
        )
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
            BrandLogo(style: .mark, size: 32)
            VStack(alignment: .leading, spacing: 0) {
                Text("Mercurius AI")
                    .font(BrandFont.subheading)
                    .foregroundStyle(BrandColor.text)
                Text("AI LITERACY TUTOR")
                    .font(BrandFont.caption)
                    .tracking(1.5)
                    .foregroundStyle(BrandColor.textSecondary)
            }
            Spacer()
        }
        .padding(.horizontal, BrandSpacing.lg)
        .padding(.vertical, BrandSpacing.md)
        .background(BrandColor.background)
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
