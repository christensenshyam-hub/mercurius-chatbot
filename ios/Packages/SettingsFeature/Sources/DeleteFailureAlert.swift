import SwiftUI

/// Alert shown when "Delete my data" / "Withdraw consent" couldn't complete.
/// Offers a retry (the server endpoint is idempotent, so retrying is safe)
/// and the local-only fallback. Shared by `SettingsView` and
/// `PrivacyChoicesView`; each owns its own `message` state so only the
/// visible screen presents.
struct DeleteFailureAlert: ViewModifier {
    @Binding var message: String?
    let retry: () -> Void
    let resetDeviceOnly: () -> Void

    func body(content: Content) -> some View {
        content.alert(
            "Couldn't delete your data",
            isPresented: Binding(
                get: { message != nil },
                set: { if !$0 { message = nil } }
            )
        ) {
            Button("Try again", action: retry)
            Button("Reset this device only", role: .destructive, action: resetDeviceOnly)
            Button("Cancel", role: .cancel) { }
        } message: {
            Text(message ?? "")
        }
    }
}

/// Alert for the local-only reset failing (Keychain error). Nothing to
/// retry against a server here, so a single dismiss button.
struct ResetFailureAlert: ViewModifier {
    @Binding var message: String?

    func body(content: Content) -> some View {
        content.alert(
            "Couldn't reset",
            isPresented: Binding(
                get: { message != nil },
                set: { if !$0 { message = nil } }
            )
        ) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(message ?? "")
        }
    }
}
