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

    @Test("seed anchors freshness to the server's last_session_date, not the fetch time")
    func seedUsesServerRecency() {
        let store = StreakStore(defaults: freshDefaults("streak"))
        // A lapsed user's session row still carries the old streak — seeding
        // must not re-stamp it as freshly confirmed.
        store.seed(streak: 5, lastSessionDate: "2020-01-01")
        #expect(store.current == 5)
        #expect(store.best == 5)
        #expect(!store.isCurrentFresh)
    }

    @Test("seed with a recent last_session_date is fresh")
    func seedRecentIsFresh() {
        let store = StreakStore(defaults: freshDefaults("streak"))
        // Today in the server's format (yyyy-MM-dd, UTC) — ISO8601's default
        // time zone is GMT, matching the server's date stamping.
        let today = String(ISO8601DateFormatter().string(from: Date()).prefix(10))
        store.seed(streak: 2, lastSessionDate: today)
        #expect(store.isCurrentFresh)
    }

    @Test("seed with a missing or unparseable date never freshens the cache")
    func seedBadDateStaysStale() {
        let store = StreakStore(defaults: freshDefaults("streak"))
        store.seed(streak: 4, lastSessionDate: "not-a-date")
        #expect(store.current == 4)
        #expect(!store.isCurrentFresh)
        store.seed(streak: 4, lastSessionDate: nil)
        #expect(!store.isCurrentFresh)
    }

    @Test("seed never regresses a fresher on-device confirmation")
    func seedKeepsNewerStamp() {
        let store = StreakStore(defaults: freshDefaults("streak"))
        store.update(streak: 5)   // chat-confirmed just now
        // The row's midnight-UTC date is older than the live confirmation —
        // seeding must not un-freshen it.
        store.seed(streak: 5, lastSessionDate: "2020-01-01")
        #expect(store.isCurrentFresh)
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
    func lastEarned() throws {
        let store = AchievementStore(defaults: freshDefaults("ach"))
        store.award(AchievementCatalog.debater)
        let earned = try #require(store.lastEarned)
        #expect(earned.id == AchievementCatalog.debater)
        store.clearLastEarned(earned)
        #expect(store.lastEarned == nil)
    }

    @Test("burst awards queue their toasts FIFO instead of clobbering the first")
    func burstAwardsQueue() throws {
        let store = AchievementStore(defaults: freshDefaults("ach"))
        // e.g. streak 3 + streak 7 newly awarded in one loop after a reinstall.
        store.award(AchievementCatalog.streak3)
        store.award(AchievementCatalog.streak7)
        let first = try #require(store.lastEarned)
        #expect(first.id == AchievementCatalog.streak3)
        store.clearLastEarned(first)
        #expect(store.lastEarned?.id == AchievementCatalog.streak7)
    }

    @Test("a duplicate clear (second presenter layer) can't swallow the next queued toast")
    func duplicateClearIsHeadGuarded() throws {
        let store = AchievementStore(defaults: freshDefaults("ach"))
        store.award(AchievementCatalog.streak3)
        store.award(AchievementCatalog.streak7)
        let first = try #require(store.lastEarned)
        store.clearLastEarned(first)
        store.clearLastEarned(first)   // stale clear from another attached presenter
        #expect(store.lastEarned?.id == AchievementCatalog.streak7)
    }

    @Test("reset clears earned badges and any pending toasts")
    func resetClearsQueue() {
        let store = AchievementStore(defaults: freshDefaults("ach"))
        store.award(AchievementCatalog.debater)
        store.reset()
        #expect(store.earnedCount == 0)
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
