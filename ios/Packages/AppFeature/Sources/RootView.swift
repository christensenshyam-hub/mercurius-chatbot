import SwiftUI
import DesignSystem
import NetworkingKit
import ChatFeature
import SettingsFeature

/// Root view of the app. Resolves the session id in the background, then
/// hands off to `ChatView`. If the session id cannot be resolved, shows
/// a recoverable error — never crashes.
public struct RootView: View {
    @EnvironmentObject private var env: AppEnvironment

    @State private var bootstrapState: BootstrapState = .loading

    /// Flips true when the user taps **Start Chat** on the home
    /// screen. Drives the transition from `HomeView` to the main
    /// `AppShellView`. Not persisted — each cold launch begins at
    /// Home by design (it's the first screen users see, and we'd
    /// rather reintroduce the framing every launch than drop
    /// straight into mid-conversation chat).
    @State private var hasEnteredApp: Bool = false

    /// Drives the "How it works" sheet presented from HomeView.
    @State private var showHowItWorks = false

    private enum BootstrapState: Equatable {
        case loading
        case ready(sessionId: String)
        case failed(reason: String)
    }

    public init() {}

    public var body: some View {
        ZStack {
            BrandColor.background.ignoresSafeArea()

            switch bootstrapState {
            case .loading:
                loadingView
            case .ready:
                readyContent
                    .transition(.opacity)
            case .failed(let reason):
                failureView(reason: reason)
            }
        }
        .animation(.easeOut(duration: 0.2), value: bootstrapState)
        .animation(.easeInOut(duration: 0.25), value: hasEnteredApp)
        .preferredColorScheme(env.themeStore.theme.colorScheme)
        .task { await bootstrap() }
        .sheet(isPresented: $showHowItWorks) {
            HowItWorksView(dismiss: { showHowItWorks = false })
        }
    }

    /// Post-bootstrap content — either the HomeView entry point or
    /// the full TabView once the user's past it. Split out so the
    /// `switch` above stays readable and the two child views can
    /// animate cleanly via `.transition`.
    @ViewBuilder
    private var readyContent: some View {
        if hasEnteredApp {
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

    // MARK: - States

    private var loadingView: some View {
        VStack(spacing: BrandSpacing.lg) {
            BrandLogo(style: .full, size: 240)
            ProgressView().controlSize(.small)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Loading Mercurius")
    }

    private func failureView(reason: String) -> some View {
        VStack(spacing: BrandSpacing.lg) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 40))
                .foregroundStyle(BrandColor.error)
            Text("Couldn't start")
                .font(BrandFont.title)
                .foregroundStyle(BrandColor.text)
            Text(reason)
                .font(BrandFont.caption)
                .foregroundStyle(BrandColor.textSecondary)
                .multilineTextAlignment(.center)
            BrandButton("Try again", style: .primary) {
                bootstrapState = .loading
                Task { await bootstrap() }
            }
            .frame(maxWidth: 200)
        }
        .padding(BrandSpacing.xl)
    }

    // MARK: - Bootstrap

    private func bootstrap() async {
        let identity = env.sessionIdentity
        do {
            let id = try await Task.detached(priority: .userInitiated) {
                try identity.current()
            }.value
            bootstrapState = .ready(sessionId: id)
        } catch {
            bootstrapState = .failed(reason: "Could not create a session on this device. Please restart the app.")
        }
    }
}
