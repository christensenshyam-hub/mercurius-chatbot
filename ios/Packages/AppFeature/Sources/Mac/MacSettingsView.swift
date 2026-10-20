#if os(macOS)
import SwiftUI
import DesignSystem
import EngagementFeature

/// The Settings window (Mercurius ▸ Settings…, ⌘,): the same `SettingsView`
/// the iPhone shows — theme, privacy choices, delete my data, withdraw
/// consent — wired to the main window's shell, so a reset clears the chat
/// the window shows and a withdrawal puts the window back on the gate.
///
/// Until consent is on record it only says where to go: Settings can erase
/// the session on the server, and nothing may reach the server before the
/// data-use agreement.
public struct MacSettingsView: View {
    @EnvironmentObject private var env: AppEnvironment
    @AppStorage(ConsentGate.storageKey) private var consentVersion: Int = 0

    public init() {}

    public var body: some View {
        Group {
            if ConsentGate.needsGate(storedVersion: consentVersion) {
                beforeConsent
            } else {
                settingsSheet(
                    env: env,
                    shell: env.macShell,
                    scheduler: env.macShell.scheduler,
                    onConsentWithdrawn: {
                        // Recorded here too: with the main window closed
                        // there is no entry view to do it, and the next
                        // window must open on the gate.
                        consentVersion = 0
                        env.macShell.onConsentWithdrawn?()
                    }
                )
            }
        }
        .frame(width: 540, height: 680)
        .preferredColorScheme(env.themeStore.theme.colorScheme)
        .tint(BrandColor.accent)
    }

    private var beforeConsent: some View {
        VStack(spacing: BrandSpacing.md) {
            MercMascot(.idle, size: 72)
                .accessibilityHidden(true)
            Text("Settings open once you've finished setting up Mercurius in the main window.")
                .font(BrandFont.body)
                .foregroundStyle(BrandColor.text)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(BrandSpacing.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(BrandColor.background)
    }
}
#endif
