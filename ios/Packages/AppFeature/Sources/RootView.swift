import SwiftUI
import DesignSystem
import NetworkingKit
import ChatFeature

/// Root view of the app. Resolves the session id in the background, then
/// hands off to `ChatView`. If the session id cannot be resolved, shows
/// a recoverable error — never crashes.
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
                ChatView(
                    apiClient: env.apiClient,
                    sessionIdentity: env.sessionIdentity
                )
                .transition(.opacity)
            case .failed(let reason):
                failureView(reason: reason)
            }
        }
        .animation(.easeOut(duration: 0.2), value: bootstrapState)
        .task { await bootstrap() }
    }

    // MARK: - States

    private var loadingView: some View {
        VStack(spacing: BrandSpacing.lg) {
            monogram
            Text("Mercurius Ⅰ")
                .font(BrandFont.title)
                .foregroundStyle(BrandColor.text)
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

    private var monogram: some View {
        ZStack {
            Circle()
                .fill(BrandColor.surface)
                .frame(width: 72, height: 72)
                .overlay(Circle().strokeBorder(BrandColor.accent, lineWidth: 2))
            Text("MⅠ")
                .font(BrandFont.title)
                .foregroundStyle(BrandColor.accent)
        }
        .accessibilityHidden(true)
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
