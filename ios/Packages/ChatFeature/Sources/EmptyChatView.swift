import SwiftUI
import DesignSystem

/// Shown when the chat has no messages. Offers a few starter prompts
/// so users don't stare at an empty input field wondering what to ask.
struct EmptyChatView: View {
    let onSuggestion: (String) -> Void

    private let suggestions: [String] = [
        "How does an LLM actually work?",
        "Is AI biased? Where does the bias come from?",
        "When should I NOT use AI?",
        "Prep me for the next club meeting.",
    ]

    var body: some View {
        VStack(spacing: BrandSpacing.xl) {
            Spacer()

            VStack(spacing: BrandSpacing.sm) {
                Text("Mercurius Ⅰ")
                    .font(BrandFont.title)
                    .foregroundStyle(BrandColor.text)

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

            Spacer()
        }
        .padding(.horizontal, BrandSpacing.lg)
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
