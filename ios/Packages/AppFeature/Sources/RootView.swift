import SwiftUI
import DesignSystem
import NetworkingKit

/// Root view of the app. For the scaffold, this shows a branded launch
/// state and verifies that connectivity to the backend works. The real
/// tab bar (Chat / Curriculum / Club / Settings) will replace this in
/// the next session.
public struct RootView: View {
    @EnvironmentObject private var env: AppEnvironment

    @State private var backendReachable: Bool? = nil
    @State private var sessionId: String? = nil
    @State private var healthCheckError: String? = nil

    public init() {}

    public var body: some View {
        ZStack {
            BrandColor.background.ignoresSafeArea()

            VStack(spacing: BrandSpacing.xl) {
                Spacer()

                monogram

                VStack(spacing: BrandSpacing.xs) {
                    Text("Mercurius Ⅰ")
                        .font(BrandFont.largeTitle)
                        .foregroundStyle(BrandColor.text)

                    Text("AI Literacy Tutor")
                        .font(BrandFont.caption)
                        .textCase(.uppercase)
                        .tracking(2)
                        .foregroundStyle(BrandColor.textSecondary)
                }

                backendStatus

                Spacer()

                VStack(spacing: BrandSpacing.xs) {
                    if let sessionId {
                        Text("Session: \(sessionId.prefix(8))…")
                            .font(BrandFont.caption)
                            .foregroundStyle(BrandColor.textSecondary)
                    }
                    Text("Chat feature arrives next.")
                        .font(BrandFont.caption)
                        .foregroundStyle(BrandColor.textSecondary.opacity(0.6))
                }
                .padding(.bottom, BrandSpacing.xl)
            }
            .padding(.horizontal, BrandSpacing.xl)
        }
        .task { await bootstrap() }
    }

    private var monogram: some View {
        ZStack {
            Circle()
                .fill(BrandColor.surface)
                .frame(width: 96, height: 96)
                .overlay(
                    Circle().strokeBorder(BrandColor.accent, lineWidth: 2)
                )
            Text("MⅠ")
                .font(BrandFont.title)
                .foregroundStyle(BrandColor.accent)
        }
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private var backendStatus: some View {
        switch backendReachable {
        case .none:
            HStack(spacing: BrandSpacing.sm) {
                ProgressView().controlSize(.small)
                Text("Connecting to server…")
                    .font(BrandFont.caption)
                    .foregroundStyle(BrandColor.textSecondary)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Connecting to server")

        case .some(true):
            Label("Connected", systemImage: "checkmark.circle.fill")
                .font(BrandFont.caption)
                .foregroundStyle(BrandColor.success)
                .accessibilityLabel("Server reachable")

        case .some(false):
            VStack(spacing: BrandSpacing.sm) {
                Label("Offline or server unreachable", systemImage: "exclamationmark.triangle.fill")
                    .font(BrandFont.caption)
                    .foregroundStyle(BrandColor.error)

                BrandButton("Retry", style: .secondary) {
                    backendReachable = nil
                    healthCheckError = nil
                    Task { await bootstrap() }
                }
                .frame(maxWidth: 180)
            }
            .accessibilityElement(children: .combine)
        }
    }

    private func bootstrap() async {
        // Resolve session id off the main thread so Keychain I/O doesn't
        // block rendering on first launch.
        let identity = env.sessionIdentity
        let resolvedId: String?
        do {
            resolvedId = try await Task.detached(priority: .userInitiated) {
                try identity.current()
            }.value
        } catch {
            healthCheckError = "Could not create session"
            backendReachable = false
            return
        }
        sessionId = resolvedId

        let ok = await env.apiClient.checkHealth()
        backendReachable = ok
    }
}

#Preview {
    RootView()
        .environmentObject(AppEnvironment(environment: .production))
}
