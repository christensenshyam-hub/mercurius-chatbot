import Foundation
import Testing
@testable import AppFeature
import ChatFeature
import CurriculumFeature
import EngagementFeature
import NetworkingKit
import PersistenceKit
import SettingsFeature

/// The Settings reset paths — "Delete my data & start over", "Reset this
/// device only", and both consent withdrawals — run the sheet's local wipe,
/// which must leave every reminder off: stored false, so no later re-plan
/// can bring them back.
@Suite("Settings reset turns the reminders off")
@MainActor
struct SettingsResetTests {

    private let reminderDefaults = freshDefaults("settings.reminders")

    private func makeSheet(
        reminderStore: ReminderStore,
        onConsentWithdrawn: (@MainActor () -> Void)? = nil
    ) -> SettingsSheet {
        let identity = SessionIdentity(keychain: InMemoryKeychain())
        let chatStore = InMemoryChatStore()
        let progress = CurriculumProgressStore(preferences: InMemoryPreferenceStore())
        return SettingsSheet(
            sessionIdentity: identity,
            themeStore: ThemePreferenceStore(preferences: InMemoryPreferenceStore()),
            chatStore: chatStore,
            chatModel: ChatViewModel(
                apiClient: APIClient(environment: .local, sessionIdentity: identity),
                sessionIdentity: identity,
                store: chatStore
            ),
            streakStore: StreakStore(defaults: freshDefaults("settings.streak")),
            achievementStore: AchievementStore(defaults: freshDefaults("settings.achievements")),
            progress: progress,
            progressSync: CurriculumProgressSync(
                progress: progress, remote: StubProgressRemote(),
                sessionId: { try identity.current() }, isEnabled: false
            ),
            reminderStore: reminderStore,
            scheduler: NotificationScheduler(),
            sessionDeleter: nil,
            onConsentWithdrawn: onConsentWithdrawn
        )
    }

    private func remindersOn() -> ReminderStore {
        let store = ReminderStore(defaults: reminderDefaults)
        store.enabled = true
        store.weeklyEnabled = true
        return store
    }

    private func expectBothOff(_ store: ReminderStore) {
        #expect(!store.enabled)
        #expect(!store.weeklyEnabled)
        let reloaded = ReminderStore(defaults: reminderDefaults)
        #expect(!reloaded.enabled && !reloaded.weeklyEnabled)
        #expect(reminderDefaults.object(forKey: "engagement.reminder.weeklyEnabled") as? Bool == false)
    }

    @Test("Delete my data & start over")
    func deleteMyData() async {
        let store = remindersOn()
        let model = makeSheet(reminderStore: store).makeModel(dismiss: {})
        #expect(await model.deleteServerDataAndStartOver())
        expectBothOff(store)
    }

    @Test("Reset this device only")
    func resetDeviceOnly() async {
        let store = remindersOn()
        let model = makeSheet(reminderStore: store).makeModel(dismiss: {})
        #expect(await model.resetSession())
        expectBothOff(store)
    }

    @Test("Withdrawing consent, with or without the server: off before the gate comes back",
          arguments: [true, false])
    func withdrawal(reachesServer: Bool) async {
        let store = remindersOn()
        var offWhenGateReturned: Bool?
        var dismissed = false
        let model = makeSheet(reminderStore: store, onConsentWithdrawn: {
            offWhenGateReturned = !store.enabled && !store.weeklyEnabled
        }).makeModel(dismiss: { dismissed = true })

        let ok = reachesServer ? await model.withdrawConsent() : await model.withdrawConsentLocally()
        #expect(ok)
        #expect(dismissed)
        #expect(offWhenGateReturned == true)
        expectBothOff(store)
    }
}
