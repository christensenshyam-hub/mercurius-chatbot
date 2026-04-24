import SwiftUI
import DesignSystem
import NetworkingKit
import ChatFeature
import SettingsFeature

/// Post-bootstrap entry flow. Owns the onboarding gate and the
/// Home → AppShell handoff so that `RootView` can stay focused on
/// bootstrap concerns (session resolve, container readiness).
///
/// Three mutually exclusive states:
///
/// 1. **Onboarding** — `!hasSeenOnboarding`. Shown only on first
///    launch. Uses `@AppStorage("hasSeenOnboarding")` via
///    `OnboardingView.storageKey`, which `OnboardingView` flips to
///    `true` when the user taps Skip or Get Started. No callback
///    wiring — the shared UserDefaults value propagates through
///    `@AppStorage` to every observer automatically.
///
/// 2. **Home** — `hasSeenOnboarding && !hasEnteredApp`. The
///    branded entry screen with the Start Chat / How it works
///    affordances. Not persisted: every cold launch begins here.
///
/// 3. **App shell** — `hasEnteredApp`. The main `TabView`
///    (Chat / Curriculum / Club). Shown once the user taps
///    Start Chat.
///
/// The animations are declared once at this view's root so the
/// child views can each use a bare `.transition(.opacity)` and
/// get a consistent crossfade.
///
/// Separation of concerns:
/// - This view knows nothing about session resolution, networking,
///   or persistence init. Those live in `RootView` / `AppEnvironment`.
/// - This view owns the user-facing entry state only.
/// - The "How it works" sheet is hoisted here (not onto `HomeView`)
///   so its `isPresented` state isn't rebuilt every time `HomeView`
///   reappears, and so a future push to "How it works" from
///   elsewhere in the entry flow can reuse the same presenter.
struct AppEntryView: View {
    @EnvironmentObject private var env: AppEnvironment

    @AppStorage(OnboardingView.storageKey) private var hasSeenOnboarding: Bool = false

    /// Flips true when the user taps **Start Chat** on HomeView.
    /// In-memory only: every cold launch restarts at Home (by design
    /// — we'd rather reintroduce the framing every launch than drop
    /// straight into a mid-conversation chat).
    @State private var hasEnteredApp: Bool = false

    /// Drives the "How it works" sheet presented from HomeView.
    @State private var showHowItWorks: Bool = false

    var body: some View {
        content
            .animation(.easeInOut(duration: 0.25), value: hasSeenOnboarding)
            .animation(.easeInOut(duration: 0.25), value: hasEnteredApp)
            .sheet(isPresented: $showHowItWorks) {
                HowItWorksView(dismiss: { showHowItWorks = false })
            }
    }

    @ViewBuilder
    private var content: some View {
        if !hasSeenOnboarding {
            OnboardingView()
                .transition(.opacity)
        } else if hasEnteredApp {
            AppShellView(
                apiClient: env.apiClient,
                sessionIdentity: env.sessionIdentity,
                chatStore: env.chatStore,
                themeStore: env.themeStore,
                clubClient: env.clubClient
            )
            .transition(.opacity)
        } else {
            HomeView(
                onStartChat: { hasEnteredApp = true },
                onHowItWorks: { showHowItWorks = true }
            )
            .transition(.opacity)
        }
    }
}
