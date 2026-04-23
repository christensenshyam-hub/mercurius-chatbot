import SwiftUI
import NetworkingKit
import SettingsFeature

/// Thin wrapper around `SettingsView` that constructs the view model
/// and wires up the sheet's own dismiss action. Lives in `AppFeature`
/// because it's a composition concern — `SettingsFeature` itself
/// shouldn't know about presentation mode.
struct SettingsSheet: View {
    let sessionIdentity: SessionIdentity

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        SettingsView(
            model: SettingsViewModel(sessionStorage: sessionIdentity),
            dismissAction: { dismiss() }
        )
    }
}
