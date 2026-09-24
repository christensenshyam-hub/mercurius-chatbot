import Testing
import Foundation
import PersistenceKit
@testable import EngagementFeature

/// The streak surfaces never show a "0": at zero the flame stands alone with
/// the invitation, in the visible copy and in VoiceOver.
struct StreakDisplayTests {

    @Test("Zero: no number, the invitation instead")
    func zeroState() {
        let d = StreakDisplay(count: 0)
        #expect(d.isZero)
        #expect(d.countText == nil)
        #expect(d.heroMessage == "Start your streak today — one lesson does it")
        #expect(d.spokenStreak == "Start your streak today — one lesson does it.")
        #expect(!d.spokenStreak.contains("0"))
        #expect(!d.heroMessage.contains("0"))
    }

    @Test("A negative count is treated as no streak")
    func negativeIsZero() {
        #expect(StreakDisplay(count: -2) == StreakDisplay(count: 0))
    }

    @Test("One day is singular")
    func oneDay() {
        let d = StreakDisplay(count: 1)
        #expect(!d.isZero)
        #expect(d.countText == "1")
        #expect(d.spokenStreak == "Current streak: 1 day.")
        #expect(d.heroMessage == "You're on the board. Come back tomorrow to keep it going.")
    }

    @Test("Several days show the number")
    func severalDays() {
        let d = StreakDisplay(count: 12)
        #expect(d.countText == "12")
        #expect(d.spokenStreak == "Current streak: 12 days.")
        #expect(d.heroMessage == "Keep it alive — one conversation a day.")
    }
}

/// `ReminderEnabler` on the macOS test host, where permission is never
/// granted: a denial must leave the stored preferences untouched.
@MainActor
struct ReminderEnablerTests {

    private func freshDefaults() -> UserDefaults {
        UserDefaults(suiteName: "test-enabler-\(UUID().uuidString)")!
    }

    @Test("Denied permission reports false and changes nothing")
    func denialLeavesPreferences() async {
        let store = ReminderStore(defaults: freshDefaults())
        store.weeklyEnabled = false
        let granted = await ReminderEnabler.enable(
            store: store, scheduler: NotificationScheduler(),
            streakStore: StreakStore(defaults: freshDefaults())
        )
        #expect(!granted)
        #expect(store.enabled == false)
        #expect(store.weeklyEnabled == false)
    }

    @Test("A single-kind denial also leaves the default-on weekly preference alone")
    func singleKindDenial() async {
        let store = ReminderStore(defaults: freshDefaults())
        let granted = await ReminderEnabler.enable(
            [.daily], store: store, scheduler: NotificationScheduler(), streakStore: nil
        )
        #expect(!granted)
        #expect(store.enabled == false)
        #expect(store.weeklyEnabled == true)
    }
}
