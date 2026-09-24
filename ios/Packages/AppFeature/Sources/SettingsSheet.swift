import SwiftUI
import NetworkingKit
import PersistenceKit
import ChatFeature
import CurriculumFeature
import MercuriusActivity
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
    let streakStore: StreakStore
    let achievementStore: AchievementStore
    let progress: CurriculumProgressStore
    let progressSync: CurriculumProgressSync
    /// Server-side erasure for "Delete my data" (the `APIClient`, narrowed).
    let sessionDeleter: SessionDeleting?
    /// Fires after the user withdraws the data-use agreement; the entry
    /// view re-mounts the consent gate.
    let onConsentWithdrawn: (@MainActor () -> Void)?

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let model = SettingsViewModel(
            sessionStorage: sessionIdentity,
            themeStore: themeStore,
            extraReset: { [chatStore, chatModel, streakStore, achievementStore, progress, progressSync] in
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
                // The on-device engagement + curriculum caches describe
                // the OLD identity: a fresh session must not inherit its
                // streak, badges, or lesson progress — and the curriculum
                // resume pointers now reference conversations `deleteAll()`
                // just removed, so they'd show dead "Resume" affordances.
                streakStore.reset()
                achievementStore.reset()
                // A push queued before the reset would carry the old
                // identity's lessons to the new session id.
                progressSync.cancelPending()
                progress.reset()
                progressSync.cancelPending()
                // The Lock Screen card would otherwise keep showing the
                // erased streak/progress (a lesson open under Settings is
                // still running one).
#if os(iOS)
                LearningActivityController.shared.endSession(immediately: true)
#endif
            },
            sessionDeleter: sessionDeleter
        )
        // A reply still streaming under the old id must stop BEFORE the server
        // erasure, or its completion re-creates the session. `cancel()` from
        // idle would stamp "Cancelled." on a finished bubble, so only stop a
        // request that is actually running. Not `startNewConversation()`: that
        // clears the thread before the server has confirmed anything.
        model.cancelInFlight = { [chatModel, progressSync] in
            switch chatModel.phase {
            case .sending, .streaming: chatModel.cancel()
            case .idle, .failed: break
            }
            // Same for a progress PUT: landing after the erasure would
            // recreate the old session's progress on the server.
            progressSync.cancelPending()
        }
        // Close the sheet before its host (the shell) leaves the tree.
        model.onConsentWithdrawn = { [dismiss, onConsentWithdrawn] in
            dismiss()
            onConsentWithdrawn?()
        }
        return SettingsView(model: model, dismissAction: { dismiss() })
    }
}
