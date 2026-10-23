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
    /// The one-time "Try a prompt above, or type your own below." hint. It
    /// sits at the end of this scroll content, under the prompts it points
    /// at, rather than pinned above the composer where it took ~50 pt from
    /// an iPhone SE's prompts (AUD-50).
    var showsHint: Bool = false
    var onDismissHint: () -> Void = {}
    let onSuggestion: (String) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var introState: MercState = .idle

    static let subtitle = "Your AI literacy tutor — here to help you think, not think for you."

    /// Below this height (an iPhone SE's empty chat is ~380 pt) Merc sits
    /// beside his greeting at a smaller size, so the starter prompts — the
    /// next step — show without scrolling (AUD-50). Accessibility sizes keep
    /// the stacked layout and scroll.
    static let compactIntroThreshold: CGFloat = 440

    static func usesCompactIntro(height: CGFloat, dynamicTypeSize: DynamicTypeSize) -> Bool {
        !dynamicTypeSize.isAccessibilitySize && height > 0 && height < compactIntroThreshold
    }

    var body: some View {
        // Wrapped in a ScrollView so that at accessibility Dynamic Type sizes
        // the intro + starter prompts remain reachable even when they exceed
        // the screen height.
        GeometryReader { geo in
            let compact = Self.usesCompactIntro(height: geo.size.height, dynamicTypeSize: dynamicTypeSize)
            ScrollView {
                VStack(spacing: compact ? BrandSpacing.lg : BrandSpacing.xl) {
                    Spacer(minLength: compact ? BrandSpacing.sm : BrandSpacing.lg)

                    if compact {
                        compactIntro
                    } else {
                        intro
                    }

                    VStack(spacing: BrandSpacing.sm) {
                        ForEach(suggestions, id: \.self) { prompt in
                            SuggestionButton(prompt: prompt) {
                                onSuggestion(prompt)
                            }
                        }
                        if showsHint {
                            ChatInputHint(onDismiss: onDismissHint)
                                .clipShape(RoundedRectangle(cornerRadius: BrandRadius.md, style: .continuous))
                                .padding(.top, BrandSpacing.xs)
                                .transition(.opacity)
                        }
                    }
                    .padding(.horizontal, BrandSpacing.lg)

                    Spacer(minLength: compact ? BrandSpacing.md : BrandSpacing.xl)
                }
                .padding(.horizontal, BrandSpacing.lg)
                // The Mac's reading column, centred in a wide window.
                .macReadableColumn()
                .frame(maxWidth: .infinity)
            }
        }
        .onAppear {
            guard !reduceMotion else { return }
            introState = .wave
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.7) { introState = .idle }
        }
    }

    /// Branded intro coach — Merc, the tutor, greeting the learner.
    /// Antics + poke: he waves hello, then keeps living between
    /// interactions and reacts when tapped, Duolingo-style.
    private var intro: some View {
        VStack(spacing: BrandSpacing.md) {
            mascot(size: 140)

            VStack(spacing: 4) {
                greeting
                Text(Self.subtitle)
                    .font(BrandFont.caption)
                    .foregroundStyle(BrandColor.textSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// The short-screen intro: a smaller Merc beside the greeting.
    private var compactIntro: some View {
        HStack(alignment: .center, spacing: BrandSpacing.md) {
            mascot(size: 84)

            VStack(alignment: .leading, spacing: 4) {
                greeting
                Text(Self.subtitle)
                    .font(BrandFont.caption)
                    .foregroundStyle(BrandColor.textSecondary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, BrandSpacing.lg)
    }

    private func mascot(size: CGFloat) -> some View {
        MercMascot(introState, size: size, emphasis: .softGlow,
                   mood: mercMood, activity: mercActivity,
                   idleAntics: true, pokeable: true)
            .accessibilityHidden(true)
    }

    private var greeting: some View {
        Text("Hi, I'm Merc")
            .font(.system(.title2, design: .rounded).weight(.heavy))
            .foregroundStyle(BrandColor.text)
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
            .macHoverHighlight(cornerRadius: BrandRadius.md)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(prompt)
    }
}
