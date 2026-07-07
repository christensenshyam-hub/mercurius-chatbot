import Testing
import Foundation
@testable import EngagementFeature

/// Pins the reminder plan: rotating Merc copy, streak-defense selection, and
/// the today-slot rules. All inputs fixed (calendar, now) so runs are
/// deterministic on any machine or CI timezone.
struct ReminderPlannerTests {

    /// Fixed clock: 2026-07-06 10:00 UTC, reminders at 18:00.
    private var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }

    private var morning: Date {
        calendar.date(from: DateComponents(year: 2026, month: 7, day: 6, hour: 10))!
    }

    private func plan(streak: Int? = nil, chattedToday: Bool = false,
                      now: Date? = nil, hour: Int = 18) -> [ReminderPlanner.PlannedReminder] {
        ReminderPlanner.plan(now: now ?? morning, calendar: calendar,
                             hour: hour, minute: 0,
                             streak: streak, chattedToday: chattedToday)
    }

    @Test("A live streak makes the FIRST slot the defense line, with the number")
    func firstSlotIsDefense() {
        let p = plan(streak: 4)
        #expect(p.count == 7)
        #expect(p[0].body.contains("4-day streak is on the line"))
        #expect(p[0].pose == .sleep)   // the streak is about to doze off
        // Only the first slot defends; the rest rotate.
        #expect(!p[1].body.contains("streak is on the line"))
        #expect(p[1].pose != .sleep)
    }

    @Test("Every rotation line carries its paired pose")
    func rotationPoses() {
        let p = plan(streak: nil)
        for reminder in p {
            let match = ReminderPlanner.dailyLines.first { $0.body == reminder.body }
            #expect(match?.pose == reminder.pose)
        }
    }

    @Test("Pose tiles render to non-empty PNG data")
    @MainActor func tilesRender() {
        for pose in ReminderPlanner.Pose.allCases {
            let data = MercNotificationArt.pngData(for: pose)
            #expect((data?.count ?? 0) > 1000, "pose \(pose.rawValue) rendered no data")
        }
    }

    @Test("Chatting today drops today's slot and moves the defense to tomorrow")
    func chattedTodayMovesDefense() {
        let p = plan(streak: 5, chattedToday: true)
        #expect(p.count == 6)                       // today's slot dropped
        #expect(p[0].fireDate.day == 7)             // first slot is tomorrow
        #expect(p[0].body.contains("5-day streak"))
    }

    @Test("A reminder time already past drops today's slot")
    func pastTimeDropsToday() {
        let evening = calendar.date(from: DateComponents(year: 2026, month: 7, day: 6, hour: 20))!
        let p = plan(streak: nil, now: evening, hour: 18)
        #expect(p.count == 6)
        #expect(p[0].fireDate.day == 7)
    }

    @Test("No streak means pure rotation — no defense copy anywhere")
    func noStreakNoDefense() {
        let p = plan(streak: nil)
        #expect(p.count == 7)
        #expect(p.allSatisfy { !$0.body.contains("streak is on the line") })
    }

    @Test("Adjacent days get different rotation lines; ids are unique + date-keyed")
    func rotationAndIds() {
        let p = plan(streak: nil)
        for (a, b) in zip(p, p.dropFirst()) {
            #expect(a.body != b.body)
        }
        #expect(Set(p.map(\.id)).count == p.count)
        #expect(p.allSatisfy { $0.id.hasPrefix(ReminderPlanner.idPrefix) })
        #expect(p[0].id == ReminderPlanner.idPrefix + "2026-07-06")
    }

    @Test("Fire dates carry the chosen hour/minute on consecutive days")
    func fireDates() {
        let p = plan(streak: 2)
        #expect(p.allSatisfy { $0.fireDate.hour == 18 && $0.fireDate.minute == 0 })
        #expect(p.map(\.fireDate.day) == [6, 7, 8, 9, 10, 11, 12])
    }
}
