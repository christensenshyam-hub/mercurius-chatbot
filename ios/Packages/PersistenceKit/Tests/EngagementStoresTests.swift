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

    private func calendar(_ zone: String) -> Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: zone)!
        return c
    }

    @Test("A seed's UTC-midnight stamp is the server's day, even west of UTC")
    func seedStampIsItsUTCDay() throws {
        let store = StreakStore(defaults: freshDefaults("streak"))
        store.seed(streak: 3, lastSessionDate: "2026-09-21")
        let stamp = try #require(store.lastUpdatedAt)
        // Read locally in New York this is 20:00 on the 20th.
        let newYork = calendar("America/New_York")
        let day = StreakStore.confirmedDay(for: stamp, calendar: newYork)
        #expect(newYork.dateComponents([.year, .month, .day, .hour], from: day)
                == DateComponents(year: 2026, month: 9, day: 21, hour: 0))
        let tokyo = calendar("Asia/Tokyo")
        #expect(tokyo.dateComponents([.day], from: StreakStore.confirmedDay(for: stamp, calendar: tokyo)).day == 21)
    }

    @Test("An in-app confirmation is the local day of the chat")
    func updateStampIsItsLocalDay() {
        let newYork = calendar("America/New_York")
        // 21:30 on Monday the 21st in New York is already the 22nd in UTC.
        let lateChat = newYork.date(from: DateComponents(year: 2026, month: 9, day: 21, hour: 21, minute: 30))!
        let day = StreakStore.confirmedDay(for: lateChat, calendar: newYork)
        #expect(newYork.dateComponents([.month, .day, .hour], from: day)
                == DateComponents(month: 9, day: 21, hour: 0))
    }

    @Test("No confirmation, no confirmed day")
    func noConfirmedDay() {
        #expect(StreakStore(defaults: freshDefaults("streak")).lastConfirmedDay == nil)
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
        #expect(Set(AchievementCatalog.all.map(\.id)).count == AchievementCatalog.all.count)
    }

    @Test("the retired report-card badge is gone from the catalog")
    func reportCardRetired() {
        #expect(AchievementCatalog.achievement(id: "report_card") == nil)
        #expect(!AchievementCatalog.all.contains { $0.title == "Self-Aware" })
    }

    @Test("earned ids no longer in the catalog are dropped on load")
    func orphanIdsFiltered() {
        let d = freshDefaults("ach")
        d.set(["report_card", AchievementCatalog.debater, "not_a_real_badge"],
              forKey: "engagement.achievements.earned")
        let store = AchievementStore(defaults: d)
        #expect(store.earned == [AchievementCatalog.debater])
        #expect(store.earnedCount == 1)
        #expect(!store.has("report_card"))
        #expect(store.earnedCount <= AchievementCatalog.all.count)
    }
}

@MainActor
@Suite("ReminderStore")
struct ReminderStoreTests {
    @Test("defaults: every reminder off, daily time 6:00 PM")
    func defaults() {
        let store = ReminderStore(defaults: freshDefaults("rem"))
        #expect(store.enabled == false)
        #expect(store.weeklyEnabled == false)
        #expect(store.hour == 18)
        #expect(store.minute == 0)
    }

    @Test("An upgraded install (no weekly key) reads weekly off, whatever its daily choice")
    func upgradeReadsWeeklyOff() {
        for daily in [true, false] {
            let d = freshDefaults("rem")
            d.set(daily, forKey: "engagement.reminder.enabled")
            let store = ReminderStore(defaults: d)
            #expect(store.enabled == daily)
            #expect(store.weeklyEnabled == false)
            // Nothing is written until the student chooses.
            #expect(d.object(forKey: "engagement.reminder.weeklyEnabled") == nil)
        }
    }

    @Test("persists changes across instances")
    func persists() {
        let d = freshDefaults("rem")
        let store = ReminderStore(defaults: d)
        store.enabled = true
        store.weeklyEnabled = false
        store.hour = 9
        store.minute = 30
        let reloaded = ReminderStore(defaults: d)
        #expect(reloaded.enabled == true)
        #expect(reloaded.weeklyEnabled == false)
        #expect(reloaded.hour == 9)
        #expect(reloaded.minute == 30)
    }

    @Test("weekly nudges read the stored key; an explicit off survives")
    func weeklyKey() {
        let d = freshDefaults("rem")
        d.set(false, forKey: "engagement.reminder.weeklyEnabled")
        #expect(ReminderStore(defaults: d).weeklyEnabled == false)
        let store = ReminderStore(defaults: d)
        store.weeklyEnabled = true
        #expect(ReminderStore(defaults: d).weeklyEnabled == true)
    }
}

@MainActor
@Suite("LastActivityStore")
struct LastActivityStoreTests {
    private let t0 = Date(timeIntervalSince1970: 1_790_000_000)

    @Test("a fresh store has no activity and is never within any window")
    func empty() {
        let store = LastActivityStore(defaults: freshDefaults("act"))
        #expect(store.lastActivityAt == nil)
        #expect(store.lastTab == nil)
        #expect(!store.isWithin(30 * 60, now: t0))
    }

    @Test("touch stamps the time; isWithin is a half-open window")
    func touchAndWindow() {
        let store = LastActivityStore(defaults: freshDefaults("act"))
        store.touch(now: t0)
        #expect(store.lastActivityAt == t0)
        #expect(store.isWithin(30 * 60, now: t0))
        #expect(store.isWithin(30 * 60, now: t0.addingTimeInterval(29 * 60)))
        #expect(!store.isWithin(30 * 60, now: t0.addingTimeInterval(30 * 60)))
        #expect(!store.isWithin(30 * 60, now: t0.addingTimeInterval(2 * 60 * 60)))
    }

    @Test("a stamp in the future (clock moved back) is not recent")
    func futureStampIsNotRecent() {
        let store = LastActivityStore(defaults: freshDefaults("act"))
        store.touch(now: t0)
        #expect(!store.isWithin(30 * 60, now: t0.addingTimeInterval(-60)))
    }

    @Test("stamp and last tab persist across instances; nil clears the tab")
    func persists() {
        let d = freshDefaults("act")
        let store = LastActivityStore(defaults: d)
        store.touch(now: t0)
        store.lastTab = "curriculum"
        let reloaded = LastActivityStore(defaults: d)
        #expect(reloaded.lastActivityAt == t0)
        #expect(reloaded.lastTab == "curriculum")
        reloaded.lastTab = nil
        #expect(LastActivityStore(defaults: d).lastTab == nil)
    }

    @Test("a later touch moves the stamp")
    func retouch() {
        let store = LastActivityStore(defaults: freshDefaults("act"))
        store.touch(now: t0)
        store.touch(now: t0.addingTimeInterval(3600))
        #expect(store.lastActivityAt == t0.addingTimeInterval(3600))
        #expect(store.isWithin(60, now: t0.addingTimeInterval(3630)))
    }
}

@MainActor
@Suite("ReviewPromptStore")
struct ReviewPromptStoreTests {
    @Test("prompts exactly on the 3rd and 10th completion")
    func thresholds() {
        let store = ReviewPromptStore(defaults: freshDefaults("review"))
        #expect(store.completedLessons == 0)
        var promptedAt: [Int] = []
        for _ in 1...15 {
            if store.recordCompletion() { promptedAt.append(store.completedLessons) }
        }
        #expect(promptedAt == [3, 10])
        #expect(store.completedLessons == 15)
    }

    @Test("the count and the used thresholds survive a new instance")
    func persistsAcrossInstances() {
        let d = freshDefaults("review")
        let first = ReviewPromptStore(defaults: d)
        #expect(!first.recordCompletion())
        #expect(!first.recordCompletion())
        #expect(first.recordCompletion())            // 3rd
        let second = ReviewPromptStore(defaults: d)
        #expect(second.completedLessons == 3)
        let prompts = (4...10).map { _ in second.recordCompletion() }
        #expect(prompts == [false, false, false, false, false, false, true])   // 10th
        let third = ReviewPromptStore(defaults: d)
        #expect(third.completedLessons == 10)
        #expect(!third.recordCompletion())
    }

    @Test("a stale instance can't claim a threshold another instance already used")
    func staleInstanceIsIdempotent() {
        let d = freshDefaults("review")
        let a = ReviewPromptStore(defaults: d)
        let b = ReviewPromptStore(defaults: d)       // created before a records anything
        a.recordCompletion()
        a.recordCompletion()
        #expect(a.recordCompletion())                // count 3, prompted
        #expect(!b.recordCompletion())               // count 4 — no second prompt
        #expect(b.completedLessons == 4)
    }

    @Test("a threshold already marked as prompted is not prompted again")
    func alreadyPromptedThreshold() {
        let d = freshDefaults("review")
        d.set(2, forKey: "review.completedLessons")
        d.set([3], forKey: "review.promptedCounts")
        let store = ReviewPromptStore(defaults: d)
        #expect(!store.recordCompletion())
        #expect(store.completedLessons == 3)
    }
}
