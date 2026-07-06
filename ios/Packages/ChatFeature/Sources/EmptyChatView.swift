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
    /// Live Merc state so the intro mascot reacts (e.g. leans in while you type).
    var mercMood: MercMood = .neutral
    var mercActivity: MercActivity = .idle
    let onSuggestion: (String) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var introState: MercState = .idle

    var body: some View {
        // Wrapped in a ScrollView so that at accessibility Dynamic Type sizes
        // the intro + starter prompts remain reachable even when they exceed
        // the screen height. Centered with top/bottom spacers at normal sizes.
        ScrollView {
            VStack(spacing: BrandSpacing.xl) {
                Spacer(minLength: BrandSpacing.lg)

                // Branded intro coach — Merc, the tutor, greeting the learner.
                // Antics + poke: he waves hello, then keeps living between
                // interactions and reacts when tapped, Duolingo-style.
                VStack(spacing: BrandSpacing.md) {
                    MercMascot(introState, size: 140, emphasis: .softGlow,
                               mood: mercMood, activity: mercActivity,
                               idleAntics: true, pokeable: true)
                        .accessibilityHidden(true)

                    VStack(spacing: 4) {
                        Text("Hi, I'm Merc")
                            .font(.system(.title2, design: .rounded).weight(.heavy))
                            .foregroundStyle(BrandColor.text)
                        Text("Your AI literacy tutor — here to help you think, not think for you.")
                            .font(BrandFont.caption)
                            .foregroundStyle(BrandColor.textSecondary)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                    }
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
        .onAppear {
            guard !reduceMotion else { return }
            introState = .wave
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.7) { introState = .idle }
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
