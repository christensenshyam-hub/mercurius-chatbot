import SwiftUI
import DesignSystem

/// One-time nudge that sits between the empty-chat state and the
/// input bar, pointing the user at where to actually type their
/// question. Mirrors the `ModeDescriptionSheet` pattern: shown once,
/// then suppressed forever via `@AppStorage`.
///
/// Why it exists: first-launch users land on EmptyChatView with four
/// starter prompts AND a text field. It's not always obvious that
/// typing in the field is a legitimate path — the prompt chips tend
/// to dominate the visual hierarchy. This hint makes the second
/// path explicit without requiring a full onboarding step.
///
/// Dismissal is implicit: if the user does anything — taps a starter
/// prompt, types a character, or taps the X — the hint goes away.
/// The `@AppStorage` flag on the calling view handles "goes away on
/// first send" automatically because `model.messages.isEmpty` flips
/// the moment a message exists.
struct ChatInputHint: View {
    let onDismiss: () -> Void

    /// Public key so the UI test harness can bypass the hint via
    /// `-hasSeenChatInputHint YES` in the launch-args argument domain
    /// — same pattern used for onboarding and mode descriptions.
    static let storageKey = "hasSeenChatInputHint"

    var body: some View {
        HStack(spacing: BrandSpacing.sm) {
            Image(systemName: "arrow.down")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(BrandColor.accent)
                .accessibilityHidden(true)

            Text("Try a prompt above, or type your own below.")
                .font(BrandFont.caption)
                .foregroundStyle(BrandColor.textSecondary)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: BrandSpacing.sm)

            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(BrandColor.textSecondary)
                    .frame(width: 32, height: 32)
            }
            .accessibilityLabel("Dismiss hint")
            .accessibilityHint("Hides this hint and doesn't show it again")
        }
        .padding(.horizontal, BrandSpacing.md)
        .padding(.vertical, BrandSpacing.xs)
        .background(BrandColor.accent.opacity(0.08))
        // Thin dividers top and bottom — matches the feel of the
        // ModeSelectorView's separator without adding a heavyweight
        // card treatment.
        .overlay(
            Rectangle()
                .fill(BrandColor.accent.opacity(0.25))
                .frame(height: 0.5),
            alignment: .top
        )
        .overlay(
            Rectangle()
                .fill(BrandColor.accent.opacity(0.25))
                .frame(height: 0.5),
            alignment: .bottom
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Hint: try a prompt above, or type your own below.")
    }
}

#Preview("Light") {
    VStack {
        Spacer()
        ChatInputHint(onDismiss: { print("dismissed") })
    }
    .background(BrandColor.background)
    .preferredColorScheme(.light)
}

#Preview("Dark") {
    VStack {
        Spacer()
        ChatInputHint(onDismiss: { print("dismissed") })
    }
    .background(BrandColor.background)
    .preferredColorScheme(.dark)
}
