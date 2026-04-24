import SwiftUI
import DesignSystem

/// Root view of the app. Focused on **bootstrap** only:
///
/// - `.loading`  — session identity is being resolved (+ SwiftData
///                 container spinning up via `AppEnvironment`).
/// - `.ready`    — hand off to `AppEntryView`, which owns the user-
///                 facing entry flow (Onboarding → Home → AppShell).
/// - `.failed`   — show a recoverable error with a Try-again CTA.
///                 Never crashes.
///
/// Intentionally does **not** know about onboarding, HomeView, or
/// the TabView. Those concerns live in `AppEntryView`, which keeps
/// this file small and keeps the bootstrap state machine readable.
public struct RootView: View {
    @EnvironmentObject private var env: AppEnvironment

    @State private var bootstrapState: BootstrapState = .loading

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
                AppEntryView()
                    .transition(.opacity)
            case .failed(let reason):
                failureView(reason: reason)
            }
        }
        .animation(.easeOut(duration: 0.2), value: bootstrapState)
        .preferredColorScheme(env.themeStore.theme.colorScheme)
        .task { await bootstrap() }
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
