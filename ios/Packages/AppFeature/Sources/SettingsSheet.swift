import SwiftUI
import NetworkingKit
import PersistenceKit
import ChatFeature
import SettingsFeature

/// Thin wrapper around `SettingsView` that constructs the view model
/// and wires up the sheet's own dismiss action. Lives in `AppFeature`
/// because it's a composition concern — `SettingsFeature` itself
/// shouldn't know about presentation mode or PersistenceKit.
struct SettingsSheet: View {
    let sessionIdentity: SessionIdentity
    let themeStore: ThemePreferenceStore
    let chatStore: ChatStore?
    let chatModel: ChatViewModel

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        SettingsView(
            model: SettingsViewModel(
                sessionStorage: sessionIdentity,
                themeStore: themeStore,
                extraReset: { [chatStore, chatModel] in
                    // Order matters: wipe the disk store first so the
                    // new conversation `startNewConversation()` opens
                    // is the only record in the freshly-empty store.
                    // Reversing the order would wipe the new record.
                    chatStore?.deleteAll()
                    // Clear in-memory messages too — otherwise the user
                    // dismisses the sheet and still sees the old chat
                    // on screen until app relaunch, which reads as a
                    // bug ("I just hit Start Over, why are they still
                    // here?"). Also resets `draft`, cancels any in-
                    // flight stream, and flips phase back to `.idle`.
                    chatModel.startNewConversation()
                }
            ),
            dismissAction: { dismiss() }
        )
    }
}
