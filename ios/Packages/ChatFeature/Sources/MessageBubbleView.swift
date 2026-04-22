import SwiftUI
import DesignSystem
import MarkdownUI

/// A single message bubble. User messages are plain text in a gold
/// bubble; assistant messages render markdown.
struct MessageBubbleView: View {
    let message: ChatMessage

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Numeric size of the body text. MarkdownUI needs a `CGFloat`, and
    /// SwiftUI's `Font` type doesn't expose its size, so we keep the
    /// value here paired with `BrandFont.body` (size 16).
    private let bodyFontSize: CGFloat = 16

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            if message.role == .user { Spacer(minLength: 48) }

            VStack(alignment: message.role == .user ? .trailing : .leading, spacing: BrandSpacing.xs) {
                bubble
                if case .failed(let reason) = message.status, message.role == .assistant {
                    failureLabel(reason)
                }
            }

            if message.role == .assistant { Spacer(minLength: 48) }
        }
        .padding(.horizontal, BrandSpacing.lg)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
    }

    // MARK: - Pieces

    @ViewBuilder
    private var bubble: some View {
        switch message.role {
        case .user:
            userBubble
        case .assistant:
            assistantBubble
        }
    }

    private var userBubble: some View {
        Text(message.content)
            .font(BrandFont.body)
            .foregroundStyle(BrandColor.userBubbleText)
            .padding(.vertical, BrandSpacing.md)
            .padding(.horizontal, BrandSpacing.lg)
            .background(BrandColor.userBubble, in: userShape)
    }

    private var assistantBubble: some View {
        Group {
            if message.content.isEmpty, case .streaming = message.status {
                typingIndicator
            } else {
                Markdown(message.content)
                    .markdownTextStyle {
                        ForegroundColor(BrandColor.assistantBubbleText)
                        FontSize(bodyFontSize)
                    }
                    .markdownBlockStyle(\.codeBlock) { config in
                        config.label
                            .padding(BrandSpacing.md)
                            .background(
                                BrandColor.surface,
                                in: RoundedRectangle(cornerRadius: BrandRadius.md)
                            )
                    }
            }
        }
        .padding(.vertical, BrandSpacing.md)
        .padding(.horizontal, BrandSpacing.lg)
        .background(BrandColor.assistantBubble)
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(BrandColor.accent)
                .frame(width: 2)
        }
        .clipShape(assistantShape)
    }

    private var typingIndicator: some View {
        TypingDots(animated: !reduceMotion)
            .accessibilityLabel("Mercurius is replying")
    }

    private func failureLabel(_ reason: String) -> some View {
        Label(reason, systemImage: "exclamationmark.circle.fill")
            .font(BrandFont.caption)
            .foregroundStyle(BrandColor.error)
            .padding(.horizontal, BrandSpacing.sm)
    }

    // MARK: - Shapes

    private var userShape: some Shape {
        .rect(
            topLeadingRadius: BrandRadius.xl,
            bottomLeadingRadius: BrandRadius.xl,
            bottomTrailingRadius: BrandRadius.sm,
            topTrailingRadius: BrandRadius.xl
        )
    }

    private var assistantShape: some Shape {
        .rect(
            topLeadingRadius: BrandRadius.sm,
            bottomLeadingRadius: BrandRadius.xl,
            bottomTrailingRadius: BrandRadius.xl,
            topTrailingRadius: BrandRadius.xl
        )
    }

    // MARK: - Accessibility

    private var accessibilityLabel: Text {
        let roleLabel = message.role == .user ? "You said" : "Mercurius replied"
        if message.content.isEmpty, case .streaming = message.status {
            return Text("Mercurius is replying")
        }
        return Text("\(roleLabel): \(message.content)")
    }
}

// MARK: - Typing dots

private struct TypingDots: View {
    let animated: Bool
    @State private var isOn: Bool = false

    var body: some View {
        HStack(spacing: 4) {
            dot(delay: 0.0)
            dot(delay: 0.15)
            dot(delay: 0.3)
        }
        .frame(width: 40, height: 18)
        .onAppear {
            guard animated else { return }
            isOn = true
        }
    }

    private func dot(delay: Double) -> some View {
        Circle()
            .fill(BrandColor.accent)
            .frame(width: 6, height: 6)
            .opacity(isOn ? 1 : 0.35)
            .animation(
                animated
                    ? .easeInOut(duration: 0.8)
                        .repeatForever(autoreverses: true)
                        .delay(delay)
                    : .default,
                value: isOn
            )
    }
}
