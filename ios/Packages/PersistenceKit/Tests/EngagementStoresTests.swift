import Testing
import Foundation
@testable import PersistenceKit

private func freshDefaults(_ tag: String) -> UserDefaults {
    UserDefaults(suiteName: "test-\(tag)-\(UUID().uuidString)")!
}

@MainActor
@Suite("StreakStore")
struct StreakStoreTests {
    @Test("update sets current and tracks best across a reset")
    func updateBest() {
        let store = StreakStore(defaults: freshDefaults("streak"))
        #expect(store.current == 0)
        store.update(streak: 3)
        #expect(store.current == 3)
        #expect(store.best == 3)
        // Server reset the streak (e.g. a missed day) — current drops, best holds.
        store.update(streak: 1)
        #expect(store.current == 1)
        #expect(store.best == 3)
    }

    @Test("ignores non-positive streaks")
    func ignoresZero() {
        let store = StreakStore(defaults: freshDefaults("streak"))
        store.update(streak: 0)
        #expect(store.current == 0)
    }

    @Test("persists across instances")
    func persists() {
        let d = freshDefaults("streak")
        StreakStore(defaults: d).update(streak: 5)
        #expect(StreakStore(defaults: d).current == 5)
    }
}

@MainActor
@Suite("AchievementStore")
struct AchievementStoreTests {
    @Test("award is idempotent; first earn returns true")
    func awardOnce() {
        let store = AchievementStore(defaults: freshDefaults("ach"))
        #expect(store.award(AchievementCatalog.firstConversation) == true)
        #expect(store.award(AchievementCatalog.firstConversation) == false)
        #expect(store.has(AchievementCatalog.firstConversation))
        #expect(store.earnedCount == 1)
    }

    @Test("unknown id is rejected")
    func unknownId() {
        let store = AchievementStore(defaults: freshDefaults("ach"))
        #expect(store.award("not_a_real_badge") == false)
    }

    @Test("lastEarned is set on new award and clears")
    func lastEarned() {
        let store = AchievementStore(defaults: freshDefaults("ach"))
        store.award(AchievementCatalog.debater)
        #expect(store.lastEarned?.id == AchievementCatalog.debater)
        store.clearLastEarned()
        #expect(store.lastEarned == nil)
    }

    @Test("streak milestones are cumulative")
    func milestones() {
        #expect(AchievementCatalog.streakMilestones(for: 2).isEmpty)
        #expect(AchievementCatalog.streakMilestones(for: 3) == [AchievementCatalog.streak3])
        #expect(AchievementCatalog.streakMilestones(for: 14).count == 3)
    }

    @Test("every catalog id resolves to metadata")
    func catalogIntegrity() {
        for achievement in AchievementCatalog.all {
            #expect(AchievementCatalog.achievement(id: achievement.id) != nil)
        }
    }
}

@MainActor
@Suite("ReminderStore")
struct ReminderStoreTests {
    @Test("defaults: disabled, 6:00 PM")
    func defaults() {
        let store = ReminderStore(defaults: freshDefaults("rem"))
        #expect(store.enabled == false)
        #expect(store.hour == 18)
        #expect(store.minute == 0)
    }

    @Test("persists changes across instances")
    func persists() {
        let d = freshDefaults("rem")
        let store = ReminderStore(defaults: d)
        store.enabled = true
        store.hour = 9
        store.minute = 30
        let reloaded = ReminderStore(defaults: d)
        #expect(reloaded.enabled == true)
        #expect(reloaded.hour == 9)
        #expect(reloaded.minute == 30)
    }
}
