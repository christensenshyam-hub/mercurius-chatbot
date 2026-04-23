import SwiftUI
import NetworkingKit
import PersistenceKit
import SettingsFeature

/// Thin wrapper around `SettingsView` that constructs the view model
/// and wires up the sheet's own dismiss action. Lives in `AppFeature`
/// because it's a composition concern — `SettingsFeature` itself
/// shouldn't know about presentation mode or PersistenceKit.
struct SettingsSheet: View {
    let sessionIdentity: SessionIdentity
    let themeStore: ThemePreferenceStore
    let chatStore: ChatStore?

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        SettingsView(
            model: SettingsViewModel(
                sessionStorage: sessionIdentity,
                themeStore: themeStore,
                extraReset: { [chatStore] in
                    chatStore?.deleteAll()
                }
            ),
            dismissAction: { dismiss() }
        )
    }
}
