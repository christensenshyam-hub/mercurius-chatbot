#if os(macOS)
import SwiftUI
import DesignSystem
import EngagementFeature
import SettingsFeature

/// The Settings window (Mercurius ▸ Settings…, ⌘,): `MacSettingsWindowView`
/// — General, Privacy, About — on the iPhone's `SettingsViewModel` with the
/// iPhone's reset wiring (`SettingsSheet.makeModel`), connected to the main
/// window's shell, so a reset clears the chat the window shows and a
/// withdrawal puts the window back on the gate.
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
                MacSettingsPanes(env: env, onConsentWithdrawn: {
                    // Recorded here too: with the main window closed there
                    // is no entry view to do it, and the next window must
                    // open on the gate.
                    consentVersion = 0
                    env.macShell.onConsentWithdrawn?()
                })
            }
        }
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
        .frame(width: 420, height: 240)
    }
}

/// The panes on one model for the window's life (a model per render would
/// lose an erasure in progress).
private struct MacSettingsPanes: View {
    @State private var model: SettingsViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openWindow) private var openWindow
    private let shell: MacShellModel
    private let dismissBox: DismissBox

    /// The model's "close the sheet" before a withdrawal hands back to the
    /// gate: here, close the Settings window. Filled in once the view has
    /// its environment.
    @MainActor private final class DismissBox {
        var action: () -> Void = {}
    }

    init(env: AppEnvironment, onConsentWithdrawn: @escaping @MainActor () -> Void) {
        let box = DismissBox()
        let sheet = settingsSheet(env: env, shell: env.macShell, scheduler: env.macShell.scheduler,
                                  onConsentWithdrawn: onConsentWithdrawn)
        _model = State(initialValue: sheet.makeModel(dismiss: { box.action() }))
        self.shell = env.macShell
        self.dismissBox = box
    }

    var body: some View {
        MacSettingsWindowView(
            model: model,
            onShowHowItTeaches: { openWindow(id: MacCommands.helpWindowId) }
        )
        .onAppear {
            dismissBox.action = { dismiss() }
            // The main window holds still while this model erases — even
            // after this window closes (`MacShellModel.isErasing`).
            shell.settingsModel = model
        }
    }
}
#endif
