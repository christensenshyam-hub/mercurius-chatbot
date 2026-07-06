import SwiftUI
import NetworkingKit
import PersistenceKit
import ChatFeature
import CurriculumFeature
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

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        SettingsView(
            model: SettingsViewModel(
                sessionStorage: sessionIdentity,
                themeStore: themeStore,
                extraReset: { [chatStore, chatModel, streakStore, achievementStore, progress] in
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
                    progress.reset()
                }
            ),
            dismissAction: { dismiss() }
        )
    }
}
