import SwiftUI
import DesignSystem
import MarkdownUI

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// Shared metrics for the free-chat assistant avatar, so the follow-up
/// footers in `MessageListView` can align with the assistant bubble's
/// leading edge (avatar footprint + row spacing).
enum ChatAvatarMetrics {
    /// Art size passed to `MercMascot` for the per-message avatar.
    static let size: CGFloat = 32
    /// Rendered width of the `.badge` avatar: the art frame plus the badge's
    /// 10% padding on each side (see `MercMascot.Emphasis.badge`).
    static var footprint: CGFloat { size * 1.2 }
}

/// A single message bubble. User messages are plain text in a gold
/// bubble; assistant messages render markdown.
struct MessageBubbleView: View {
    let message: ChatMessage
    /// Invoked when the user long-presses an assistant message and taps
    /// "Report response" (App Store Guideline 1.2).
    var onReport: () -> Void = {}
    /// Lesson screen styling: a white/elevated bubble with a soft shadow, a
    /// "Merc" presence line, and the tinted check-question callout. Defaults off
    /// so the free Chat tab keeps its standard bubble.
    var lessonStyle: Bool = false
    /// In the free chat, assistant messages show a small Merc avatar to their
    /// left so the conversation reads as "Merc, your tutor." Off in lessonStyle
    /// (the lesson has its own coach card).
    var showAvatar: Bool = false
    /// Mood/activity for THIS message's avatar — the live focal state on the
    /// latest assistant message, neutral/idle on older ones.
    var avatarMood: MercMood = .neutral
    var avatarActivity: MercActivity = .idle

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// Numeric size of the body text. MarkdownUI needs a `CGFloat`, and
    /// SwiftUI's `Font` type doesn't expose its size, so we keep the value
    /// here. `@ScaledMetric` makes it grow with the user's Dynamic Type
    /// setting (relative to `.body`), so reading text stays accessible.
    @ScaledMetric(relativeTo: .body) private var bodyFontSize: CGFloat = 16

    var body: some View {
        HStack(alignment: .top, spacing: shouldShowAvatar ? BrandSpacing.sm : 0) {
            if message.role == .user { Spacer(minLength: 48) }

            if shouldShowAvatar { avatarView }

            VStack(alignment: message.role == .user ? .trailing : .leading, spacing: BrandSpacing.xs) {
                if message.role == .user, let data = message.imageData, let image = Self.image(from: data) {
                    image
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: 220, maxHeight: 280)
                        .clipShape(RoundedRectangle(cornerRadius: BrandRadius.lg))
                        .overlay(
                            RoundedRectangle(cornerRadius: BrandRadius.lg)
                                .stroke(BrandColor.border, lineWidth: 1)
                        )
                        .accessibilityLabel("Attached photo")
                }
                if message.role == .assistant && lessonStyle && !isEmptyTyping {
                    presenceLine
                }
                // Skip an empty text bubble for an image-only user message.
                if message.role == .assistant || !message.content.isEmpty {
                    bubble
                }
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

    // MARK: - Avatar

    /// Assistant-only, free-chat-only small Merc badge to the message's left.
    /// Dropped at accessibility Dynamic Type sizes — the decorative avatar
    /// column would squeeze an already-narrow scaled text column (same
    /// convention as the `.peek` Merc in `MercChatZone`); the subtle leading
    /// accent line takes over as the assistant attribution there.
    private var shouldShowAvatar: Bool {
        showAvatar && message.role == .assistant && !lessonStyle
            && !dynamicTypeSize.isAccessibilitySize
    }

    private var avatarView: some View {
        // `.bust` zooms the art onto Merc's face/visor so he's recognizable
        // at avatar size — the full body reads as an unreadable speck at 32pt.
        MercMascot(avatarExpression, size: ChatAvatarMetrics.size,
                   presentation: .bust, emphasis: .badge,
                   mood: avatarMood, activity: avatarActivity)
            .padding(.top, 2)
            .accessibilityHidden(true)
    }

    /// The avatar shows a neutral face for ambient states (the motion conveys
    /// thinking/speaking/listening); only a positive reaction warms the face.
    private var avatarExpression: MercState {
        switch avatarMood {
        case .happy, .encouraging, .celebrating: return .happy
        default:                                 return .idle
        }
    }

    // MARK: - Pieces

    @ViewBuilder
    private var bubble: some View {
        switch message.role {
        case .user:
            userBubble
        case .assistant:
            if lessonStyle { lessonAssistantBubble } else { assistantBubble }
        }
    }

    /// Whether this is the empty assistant placeholder shown mid-stream.
    private var isEmptyTyping: Bool {
        if message.content.isEmpty, case .streaming = message.status { return true }
        return false
    }

    /// "● Merc" sender line above the lesson bubble (green dot + soft ring).
    private var presenceLine: some View {
        HStack(spacing: 7) {
            Circle()
                .fill(BrandColor.success)
                .frame(width: 7, height: 7)
                .background(Circle().fill(BrandColor.success.opacity(0.18)).frame(width: 13, height: 13))
            Text("Merc")
                .font(.system(size: 11.5, weight: .heavy, design: .rounded))
                .foregroundStyle(BrandColor.textSecondary)
        }
        .padding(.leading, 4)
        .accessibilityHidden(true)
    }

    /// The lesson bubble: white/elevated surface, soft shadow, 8/24 corners, and
    /// a tinted italic callout around any `[CHECK]…[/CHECK]` question.
    private var lessonAssistantBubble: some View {
        Group {
            if isEmptyTyping {
                typingIndicator
            } else {
                let parts = Self.splitCheck(message.content)
                // Strip any stray/second/partial markers from the rendered
                // segments so they never surface as literal text.
                let before = Self.stripCheckTokens(parts.before)
                let after = Self.stripCheckTokens(parts.after)
                VStack(alignment: .leading, spacing: BrandSpacing.sm) {
                    if !before.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        lessonMarkdown(before)
                    }
                    if let check = parts.check { calloutCard(check) }
                    if !after.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        lessonMarkdown(after)
                    }
                }
            }
        }
        .padding(.vertical, BrandSpacing.md)
        .padding(.horizontal, BrandSpacing.lg)
        .background(BrandColor.surface, in: lessonAssistantShape)
        .shadow(color: .black.opacity(0.12), radius: 14, y: 8)
        .contextMenu {
            if !message.content.isEmpty {
                Button(role: .destructive, action: onReport) {
                    Label("Report response", systemImage: "flag")
                }
            }
        }
    }

    private func lessonMarkdown(_ text: String) -> some View {
        Markdown(text)
            .markdownTextStyle {
                ForegroundColor(BrandColor.assistantBubbleText)
                FontSize(bodyFontSize)
            }
            .markdownBlockStyle(\.codeBlock) { config in
                config.label
                    .padding(BrandSpacing.md)
                    .background(BrandColor.surfaceElevated, in: RoundedRectangle(cornerRadius: BrandRadius.md))
            }
    }

    private func calloutCard(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12.5, weight: .heavy, design: .rounded).italic())
            .foregroundStyle(BrandColor.accent)
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.vertical, 13)
            .padding(.horizontal, 14)
            .background(BrandColor.accent.opacity(0.10),
                        in: RoundedRectangle(cornerRadius: BrandRadius.lg, style: .continuous))
    }

    /// Splits a lesson reply into the text before a `[CHECK]…[/CHECK]` block, the
    /// check question, and any text after. Handles a still-streaming (unclosed)
    /// `[CHECK]` gracefully so the marker never flashes as literal text.
    static func splitCheck(_ s: String) -> (before: String, check: String?, after: String) {
        guard let open = s.range(of: "[CHECK]") else { return (s, nil, "") }
        let before = String(s[..<open.lowerBound])
        let rest = s[open.upperBound...]
        if let close = rest.range(of: "[/CHECK]") {
            let check = String(rest[..<close.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
            return (before, check.isEmpty ? nil : check, String(rest[close.upperBound...]))
        }
        let check = String(rest).trimmingCharacters(in: .whitespacesAndNewlines)
        return (before, check.isEmpty ? nil : check, "")
    }

    /// Removes any complete `[CHECK]`/`[/CHECK]` tokens from a rendered segment
    /// (a stray second pair, or markers outside the first block), and holds back
    /// an almost-complete partial still streaming in (waiting on its `]`).
    static func stripCheckTokens(_ s: String) -> String {
        var out = s.replacingOccurrences(of: "[CHECK]", with: "")
                   .replacingOccurrences(of: "[/CHECK]", with: "")
        if out.hasSuffix("[/CHECK") { out = String(out.dropLast(7)) }
        else if out.hasSuffix("[CHECK") { out = String(out.dropLast(6)) }
        return out
    }

    private var lessonAssistantShape: some Shape {
        .rect(topLeadingRadius: 8, bottomLeadingRadius: 24, bottomTrailingRadius: 24, topTrailingRadius: 24)
    }

    private var userBubble: some View {
        Text(message.content)
            .font(BrandFont.body)
            .foregroundStyle(BrandColor.userBubbleText)
            .padding(.vertical, BrandSpacing.md)
            .padding(.horizontal, BrandSpacing.lg)
            .background(
                LinearGradient(
                    colors: [BrandColor.userBubbleTop, BrandColor.userBubbleBottom],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                in: userShape
            )
    }

    private var assistantBubble: some View {
        Group {
            if message.content.isEmpty, case .streaming = message.status {
                typingIndicator
            } else {
                // Defensive: a lesson-only [CHECK] marker should never reach the
                // free Chat tab, but strip it so it can't surface literally.
                Markdown(Self.stripCheckTokens(message.content))
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
        // The Merc avatar is the message's attribution now — a full-height
        // accent bar next to it competes with the mascot, so it only renders
        // (much subtler) when a host shows assistant bubbles avatar-less.
        .overlay(alignment: .leading) {
            if !shouldShowAvatar {
                Rectangle()
                    .fill(BrandColor.accent.opacity(0.35))
                    .frame(width: 2)
            }
        }
        .clipShape(assistantShape)
        .contextMenu {
            if !message.content.isEmpty {
                Button(role: .destructive, action: onReport) {
                    Label("Report response", systemImage: "flag")
                }
            }
        }
    }

    /// The branded "Merc is thinking…" loading state. When the avatar itself is
    /// carrying the live `.aiThinking` pulse, the bubble shows just the labeled
    /// text — no redundant second loader. Whenever it isn't (lessons have no
    /// avatar; during the first-exchange coach intro the avatar is deliberately
    /// neutral because the intro Merc is the live one — and that intro can be
    /// scrolled off-screen), the animated dots carry the motion. Either way a
    /// visible label + accessibility text is always present, so the state never
    /// relies on animation alone (and reads under Reduce Motion).
    private var typingIndicator: some View {
        HStack(spacing: BrandSpacing.sm) {
            if !(shouldShowAvatar && avatarActivity == .aiThinking) {
                TypingDots(animated: !reduceMotion)
            }
            Text("Merc is thinking…")
                .font(BrandFont.caption)
                .foregroundStyle(BrandColor.textSecondary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Merc is thinking")
    }

    private func failureLabel(_ reason: String) -> some View {
        Label(reason, systemImage: "exclamationmark.circle.fill")
            .font(BrandFont.caption)
            .foregroundStyle(BrandColor.error)
            .padding(.horizontal, BrandSpacing.sm)
    }

    /// Decode raw image bytes into a SwiftUI `Image` for an attached photo.
    private static func image(from data: Data) -> Image? {
        #if canImport(UIKit)
        return UIImage(data: data).map { Image(uiImage: $0) }
        #elseif canImport(AppKit)
        return NSImage(data: data).map { Image(nsImage: $0) }
        #else
        return nil
        #endif
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
        // Speak the reply with the check question flagged, so VoiceOver users
        // hear that a response is expected — and never hear the raw markers.
        let parts = Self.splitCheck(message.content)
        var spoken = Self.stripCheckTokens(parts.before)
        if let check = parts.check { spoken += " Question: \(check)" }
        spoken += Self.stripCheckTokens(parts.after)
        return Text("\(roleLabel): \(spoken)")
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
        // Re-arm after a lazy-container scroll-out (the repeatForever
        // animation dies with the view; the preserved @State would
        // otherwise freeze the dots at full opacity).
        .onDisappear { isOn = false }
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
