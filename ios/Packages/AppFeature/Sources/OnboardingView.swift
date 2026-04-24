import SwiftUI
import DesignSystem

// MARK: - Page model

/// The hero visual for an onboarding page. Modeled as an enum so the
/// first (brand-intro) page can render the full Mercurius logo while
/// later (tutorial) pages use SF Symbols — without branching renderer
/// logic at call sites.
enum OnboardingPageHero: Equatable {
    /// Show the `BrandLogo(style: .full, ...)` asset at a size that
    /// reads as a brand intro. Used for page 1 only.
    case logo(size: CGFloat)
    /// Show an SF Symbol rendered in the accent gradient.
    case symbol(String)
}

/// Content for a single onboarding page. Broken out as a value type so
/// the pages array is easy to read and the page view has a single,
/// typed input.
struct OnboardingPage: Equatable {
    let hero: OnboardingPageHero
    let title: String
    let body: String
}

// MARK: - OnboardingView

/// First-launch onboarding. Three swipeable pages that frame what the
/// tutor is, how to use it, and a heads-up about critical thinking.
///
/// Sits between `RootView`'s `.ready` state and `HomeView`, one time
/// only. Persistence lives in `@AppStorage("hasSeenOnboarding")`:
/// flipping it to `true` (via Skip or Get Started) causes every
/// observer of that key — notably `RootView` — to re-render and move
/// past onboarding. The component is fully self-contained; it doesn't
/// take a completion callback because a shared UserDefaults value
/// propagates to every `@AppStorage` observer automatically.
///
/// Design decisions worth calling out:
/// - `TabView(selection:).tabViewStyle(.page)` is the stock SwiftUI
///   pager. Swipe, page dots, and VoiceOver page navigation come
///   free. Brand accent tint flows through from the enclosing
///   `.tint(BrandColor.accent)` modifier.
/// - The Get Started CTA is always in the layout, but `opacity` +
///   `allowsHitTesting` gate it to the last page. Keeping it in the
///   layout reserves vertical space so the page indicator dots don't
///   jump position the moment the button appears.
/// - Skip stays visible on every page. Giving users a fast exit from
///   any step matters more than a marginally cleaner toolbar on the
///   last page.
/// - SF Symbols render in the accent gradient to match
///   `BrandLogo(.mark)` and the primary CTA — it reads as brand
///   iconography rather than stock system art.
public struct OnboardingView: View {

    /// UserDefaults key that gates this view. Exposed so `RootView`
    /// (and any future caller) can observe the same storage without
    /// string drift.
    public static let storageKey = "hasSeenOnboarding"

    @AppStorage(OnboardingView.storageKey) private var hasSeenOnboarding: Bool = false
    @State private var currentPage: Int = 0

    public init() {}

    private static let pages: [OnboardingPage] = [
        // Page 1 is deliberately brand-first, not tutorial-first. The
        // full Mercurius logo + a welcome line give new users a clear
        // "this is the app I installed" signal before any explainer
        // copy lands on pages 2-3.
        OnboardingPage(
            hero: .logo(size: 200),
            title: "Welcome to Mercurius AI",
            body: "Your AI literacy tutor for learning how to use AI effectively, ethically, and intelligently."
        ),
        OnboardingPage(
            hero: .symbol("questionmark.bubble"),
            title: "Ask better questions",
            body: "Get smarter answers by learning how to prompt AI."
        ),
        OnboardingPage(
            hero: .symbol("checkmark.shield"),
            title: "Think critically",
            body: "AI can be wrong. Always verify important information."
        ),
    ]

    private var isLastPage: Bool {
        currentPage == Self.pages.count - 1
    }

    // MARK: - Body

    public var body: some View {
        ZStack {
            BrandColor.background.ignoresSafeArea()

            VStack(spacing: 0) {
                header
                pager
                cta
            }
        }
        .tint(BrandColor.accent)
        .animation(.easeInOut(duration: 0.2), value: isLastPage)
    }

    // MARK: - Pieces

    private var header: some View {
        HStack {
            Spacer()
            Button("Skip", action: finish)
                .font(BrandFont.bodyEmphasized)
                .foregroundStyle(BrandColor.textSecondary)
                .accessibilityHint("Skips onboarding and opens the home screen")
        }
        .padding(.horizontal, BrandSpacing.xl)
        .padding(.top, BrandSpacing.sm)
        .frame(minHeight: 44)
    }

    private var pager: some View {
        TabView(selection: $currentPage) {
            ForEach(Array(Self.pages.enumerated()), id: \.offset) { index, page in
                OnboardingPageView(page: page)
                    .tag(index)
            }
        }
#if os(iOS)
        // `.always` keeps the dots visible on both light and dark
        // backgrounds; the system pill behind them only appears
        // while the user is actively swiping (see `indexViewStyle`).
        .tabViewStyle(.page(indexDisplayMode: .always))
        .indexViewStyle(.page(backgroundDisplayMode: .interactive))
#endif
    }

    private var cta: some View {
        BrandButton("Get Started", style: .primary, action: finish)
            .frame(maxWidth: 420)
            .padding(.horizontal, BrandSpacing.xl)
            .padding(.bottom, BrandSpacing.xl)
            .opacity(isLastPage ? 1 : 0)
            .allowsHitTesting(isLastPage)
            // Hidden from VoiceOver on non-final pages so swiping
            // through doesn't announce a button that can't actually
            // be tapped. Re-exposed once the user reaches page 3.
            .accessibilityHidden(!isLastPage)
            .accessibilityHint("Completes onboarding and opens the home screen")
    }

    // MARK: - Actions

    /// Persist completion and let observers of `hasSeenOnboarding`
    /// (i.e. `RootView`) drive the transition to HomeView. Reached
    /// from both Skip and Get Started — the two are the same action
    /// from this screen's perspective.
    private func finish() {
        hasSeenOnboarding = true
    }
}

// MARK: - Single-page layout

/// One page of the onboarding pager. Icon, title, body — no buttons
/// of its own. Swiping and CTAs are owned by the parent so they
/// don't fight the pager's gesture handling.
struct OnboardingPageView: View {
    let page: OnboardingPage

    var body: some View {
        VStack(spacing: BrandSpacing.xxl) {
            Spacer(minLength: BrandSpacing.xxl)

            hero

            VStack(spacing: BrandSpacing.md) {
                Text(page.title)
                    .font(BrandFont.largeTitle)
                    .foregroundStyle(BrandColor.text)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

                Text(page.body)
                    .font(BrandFont.body)
                    .foregroundStyle(BrandColor.textSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, BrandSpacing.xl)

            // Bottom spacer is larger than the top so the content
            // sits a touch above the vertical midpoint — leaves room
            // for the page indicator dots without feeling bottom-heavy.
            Spacer(minLength: BrandSpacing.xxxl)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(page.title). \(page.body)")
    }

    @ViewBuilder
    private var hero: some View {
        switch page.hero {
        case .logo(let size):
            BrandLogo(style: .full, size: size)
                .accessibilityHidden(true)
        case .symbol(let name):
            Image(systemName: name)
                .font(.system(size: 80, weight: .regular))
                .foregroundStyle(
                    LinearGradient(
                        colors: [BrandColor.accent, BrandColor.accentLight],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .accessibilityHidden(true)
        }
    }
}

// MARK: - Previews

#Preview("Light") {
    OnboardingView()
        .preferredColorScheme(.light)
}

#Preview("Dark") {
    OnboardingView()
        .preferredColorScheme(.dark)
}

#Preview("Accessibility XXL") {
    OnboardingView()
        .environment(\.dynamicTypeSize, .accessibility3)
}
