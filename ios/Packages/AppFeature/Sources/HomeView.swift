import SwiftUI
import DesignSystem

/// The first screen a user sees after the app finishes bootstrapping.
///
/// Sits between `RootView`'s `.ready` state and `AppShellView`'s
/// `TabView`. Shows the brand, a one-line framing of what the tutor
/// does, and two affordances:
///
/// - **Start Chat** — the primary CTA that transitions into the main
///   TabView (behavior provided by the host via `onStartChat`).
/// - **How it works** — opens a brief explainer (behavior provided
///   via `onHowItWorks`). Kept as a subdued text-style button so it
///   doesn't compete with the primary CTA.
///
/// Design decisions worth calling out:
///
/// - The whole layout sits inside a `ScrollView`. At normal Dynamic
///   Type the content fits on every current iPhone without scrolling
///   (`.scrollBounceBehavior(.basedOnSize)` suppresses rubber-band
///   bounce in that case), but at accessibility sizes the content
///   would otherwise clip below the CTA. Same posture as
///   `EmptyChatView`'s Phase 3f layout fix.
/// - `BrandLogo(style: .mark, size: 88)` — the `.full` variant
///   already embeds the "Mercurius AI" wordmark, which would
///   duplicate the large title. `.mark` is just the seraphed
///   profile + halo, which reads as iconography rather than a
///   second headline.
/// - No gradients on the hero itself. The CTA button inherits the
///   navy→purple brand gradient through `BrandButton(.primary)` —
///   that's the one concession to gradient styling and it's already
///   part of the design system.
/// - Spacing uses `BrandSpacing` tokens throughout. No magic
///   numbers except the logo size (which is a visual calibration,
///   not a layout one).
/// - No custom navigation bar. The NavigationStack is here so
///   future pushes from this screen (e.g. "How it works" detail)
///   get native back-swipe; today the bar is hidden to keep the
///   screen visually uncluttered.
public struct HomeView: View {

    // MARK: - Inputs

    private let onStartChat: () -> Void
    private let onHowItWorks: () -> Void

    public init(
        onStartChat: @escaping () -> Void,
        onHowItWorks: @escaping () -> Void
    ) {
        self.onStartChat = onStartChat
        self.onHowItWorks = onHowItWorks
    }

    // MARK: - Body

    public var body: some View {
        NavigationStack {
            ZStack {
                BrandColor.background
                    .ignoresSafeArea()

                content
            }
#if os(iOS)
            .toolbar(.hidden, for: .navigationBar)
#endif
        }
        .tint(BrandColor.accent)
    }

    // MARK: - Layout

    private var content: some View {
        ScrollView {
            VStack(spacing: BrandSpacing.xxl) {
                Spacer(minLength: BrandSpacing.xl)

                heroSection

                descriptionSection

                ctaSection

                Spacer(minLength: BrandSpacing.xl)
            }
            .padding(.horizontal, BrandSpacing.xl)
            .frame(maxWidth: .infinity)
        }
        .scrollBounceBehavior(.basedOnSize)
    }

    // MARK: - Pieces

    /// The hero uses the app's real brand logo (the winged-Mercury
    /// image asset from Phase 3's rebrand) rather than the
    /// alphanumeric `.mark` monogram. The `.full` variant already
    /// embeds the "Mercurius AI" wordmark, so a separate large-title
    /// `Text` would be visually redundant — letting the logo carry
    /// the title is the cleaner, more credible composition.
    ///
    /// The custom "Your AI literacy tutor" subtitle below is
    /// intentionally different from the logo's own "AI LITERACY
    /// TUTOR" caption: first-person framing, sentence case, warmer.
    /// Grouped into one accessibility element so VoiceOver reads
    /// the whole hero as a single coherent header.
    private var heroSection: some View {
        VStack(spacing: BrandSpacing.md) {
            BrandLogo(style: .full, size: 200)

            Text("Your AI literacy tutor")
                .font(BrandFont.subheading)
                .foregroundStyle(BrandColor.textSecondary)
                .multilineTextAlignment(.center)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Mercurius AI — your AI literacy tutor")
        .accessibilityAddTraits(.isHeader)
    }

    /// One-line framing that sets the pedagogical tone. Kept to a
    /// single sentence on purpose — the goal is credible, not verbose.
    private var descriptionSection: some View {
        Text("Learn how to use AI effectively, ethically, and intelligently.")
            .font(BrandFont.body)
            .foregroundStyle(BrandColor.textSecondary)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, BrandSpacing.md)
    }

    /// Primary CTA + subdued secondary link. `BrandButton(.primary)`
    /// uses the system accent gradient and honors Reduce Motion,
    /// Dynamic Type, and the 44pt hit target automatically.
    private var ctaSection: some View {
        VStack(spacing: BrandSpacing.md) {
            BrandButton("Start Chat", style: .primary, action: onStartChat)
                .accessibilityHint("Opens the tutor and starts a new conversation")

            Button(action: onHowItWorks) {
                Text("How it works")
                    .font(BrandFont.bodyEmphasized)
                    .foregroundStyle(BrandColor.accent)
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.plain)
            .accessibilityHint("Opens a short explanation of how Mercurius teaches")
        }
        // Cap the CTA width on larger devices (iPad) so the buttons
        // don't stretch across the entire screen. On iPhone this is
        // effectively a no-op — the column is narrower than the cap.
        .frame(maxWidth: 420)
    }
}

// MARK: - Preview

#Preview("Light") {
    HomeView(
        onStartChat: { print("Start Chat") },
        onHowItWorks: { print("How it works") }
    )
    .preferredColorScheme(.light)
}

#Preview("Dark") {
    HomeView(
        onStartChat: { print("Start Chat") },
        onHowItWorks: { print("How it works") }
    )
    .preferredColorScheme(.dark)
}

#Preview("Accessibility XXL") {
    HomeView(
        onStartChat: { print("Start Chat") },
        onHowItWorks: { print("How it works") }
    )
    .environment(\.dynamicTypeSize, .accessibility3)
}
