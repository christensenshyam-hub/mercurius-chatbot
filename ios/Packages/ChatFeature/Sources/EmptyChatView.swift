import SwiftUI
import DesignSystem

/// Shown when the chat has no messages. Offers a few starter prompts
/// so users don't stare at an empty input field wondering what to ask.
///
/// Suggestions are passed in by the host (typically `ChatView` reading
/// `ModePromptProvider.prompts(for: model.currentMode)`) so the chips
/// re-render whenever the active mode changes. Keeping the data flow
/// inside the parent — rather than letting EmptyChatView observe the
/// model directly — keeps this view dumb and previewable in isolation.
struct EmptyChatView: View {
    let suggestions: [String]
    let onSuggestion: (String) -> Void

    var body: some View {
        // Wrapped in a ScrollView so that at accessibility Dynamic Type sizes
        // the logo + starter prompts remain reachable even when they exceed
        // the screen height. Centered with top/bottom spacers at normal sizes.
        ScrollView {
            VStack(spacing: BrandSpacing.xl) {
                Spacer(minLength: BrandSpacing.xl)

                VStack(spacing: BrandSpacing.md) {
                    BrandLogo(style: .full, size: 180)

                    Text("Here to help you think, not think for you.")
                        .font(BrandFont.caption)
                        .italic()
                        .foregroundStyle(BrandColor.textSecondary)
                        .multilineTextAlignment(.center)
                }

                VStack(spacing: BrandSpacing.sm) {
                    ForEach(suggestions, id: \.self) { prompt in
                        SuggestionButton(prompt: prompt) {
                            onSuggestion(prompt)
                        }
                    }
                }
                .padding(.horizontal, BrandSpacing.lg)

                Spacer(minLength: BrandSpacing.xl)
            }
            .padding(.horizontal, BrandSpacing.lg)
            .frame(maxWidth: .infinity)
        }
    }
}

private struct SuggestionButton: View {
    let prompt: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: BrandSpacing.sm) {
                Rectangle()
                    .fill(BrandColor.accent)
                    .frame(width: 3)
                Text(prompt)
                    .font(BrandFont.body)
                    .foregroundStyle(BrandColor.text)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, BrandSpacing.md)
                    .padding(.trailing, BrandSpacing.md)
            }
            .frame(minHeight: 44)
            .background(BrandColor.surface)
            .clipShape(RoundedRectangle(cornerRadius: BrandRadius.md))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(prompt)
    }
}
