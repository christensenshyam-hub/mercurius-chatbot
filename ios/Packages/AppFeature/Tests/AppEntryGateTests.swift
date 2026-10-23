import Foundation
import Testing
import CurriculumFeature
import EngagementFeature
@testable import AppFeature

@Suite("AppEntryView gate decision")
struct AppEntryGateTests {

    @Test("Fresh install: no consent, no onboarding → gate")
    func freshInstall() {
        #expect(AppEntryView.showsGate(consentVersion: 0, hasSeenOnboarding: false, clearedThisLaunch: false))
    }

    @Test("Pre-2.3.0 install: onboarding done but consent never recorded → gate")
    func preConsentInstall() {
        #expect(AppEntryView.showsGate(consentVersion: 0, hasSeenOnboarding: true, clearedThisLaunch: false))
    }

    @Test("Current consent and onboarding done → no gate")
    func consented() {
        #expect(!AppEntryView.showsGate(consentVersion: 1, hasSeenOnboarding: true, clearedThisLaunch: false))
    }

    @Test("Consent without onboarding still runs the full flow")
    func consentedButNeverOnboarded() {
        #expect(AppEntryView.showsGate(consentVersion: 1, hasSeenOnboarding: false, clearedThisLaunch: false))
    }

    @Test("Completing the flow in this launch clears the gate even if the stored flags read stale")
    func clearedThisLaunchWins() {
        // The UI tests pin `-consentVersion 0` through the argument domain,
        // which shadows the flow's own write for the whole process.
        #expect(!AppEntryView.showsGate(consentVersion: 0, hasSeenOnboarding: false, clearedThisLaunch: true))
        #expect(!AppEntryView.showsGate(consentVersion: 0, hasSeenOnboarding: true, clearedThisLaunch: true))
    }

    @Test("Withdrawing consent (version reset, flag cleared) re-gates")
    func withdrawal() {
        #expect(AppEntryView.showsGate(consentVersion: 0, hasSeenOnboarding: true, clearedThisLaunch: false))
    }
}

@Suite("AppEntryView reminder consent guard")
struct ReminderConsentGuardTests {

    @Test("Consent current: re-plan from the preferences")
    func consentCurrentPlans() {
        // Also "Your path", where consent is recorded while the gate still
        // shows: the reminders chosen there must stand.
        #expect(AppEntryView.reminderReplan(consentVersion: ConsentGate.currentVersion, clearedThisLaunch: false) == .plan)
        // Cleared this launch under a pinned stale flag (the UI tests).
        #expect(AppEntryView.reminderReplan(consentVersion: 0, clearedThisLaunch: true) == .plan)
    }

    @Test("Consent missing, stale, or withdrawn: cancel everything, schedule nothing")
    func consentMissingCancels() {
        // A 2.2 upgrader on the gate, a first run, the under-13 and paused
        // screens, and a withdrawal all read consent version 0.
        #expect(AppEntryView.reminderReplan(consentVersion: 0, clearedThisLaunch: false) == .cancel)
        #expect(AppEntryView.reminderReplan(consentVersion: ConsentGate.currentVersion - 1, clearedThisLaunch: false) == .cancel)
    }
}

// AUD-36: the reminder planner counts the same Thursday week as the
// curriculum's WeeklyPlan, and the composition root hands it that plan.
@Suite("Weekly nudges read the weekly plan")
struct WeeklyNudgeWiringTests {

    @Test("The planner's week starts on the same Thursday as WeeklyPlan's, on every weekday")
    @MainActor
    func sameWeek() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Chicago")!
        let progress = CurriculumProgressStore(preferences: InMemoryPreferenceStore())
        // Two weeks of days, across the DST change on 1 November 2026.
        for dayOffset in 0..<14 {
            for hour in [0, 9, 23] {
                let date = calendar.date(from: DateComponents(year: 2026, month: 10, day: 26 + dayOffset, hour: hour))!
                let plan = WeeklyPlan.compute(progress: progress, now: date, calendar: calendar)
                #expect(ReminderPlanner.weekStart(containing: date, calendar: calendar) == plan.weekStart)
            }
        }
    }

    @Test("The weekly plan maps straight into the planner's week, and two done means no nudge")
    @MainActor
    func mapsPlan() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let monday = calendar.date(from: DateComponents(year: 2026, month: 7, day: 6, hour: 10))!
        let progress = CurriculumProgressStore(preferences: InMemoryPreferenceStore(), now: { monday })
        let unit1 = MercuriusCurriculum.units[0]

        var week = AppEntryView.weekProgress(WeeklyPlan.compute(progress: progress, now: monday, calendar: calendar))
        #expect(week.done == 0)
        #expect(week.goal == ReminderPlanner.defaultWeeklyGoal)
        #expect(ReminderPlanner.weeklyPlan(now: monday, calendar: calendar, week: week).first?.fireDate.day == 8)

        progress.markCompleted(unit1.lessons[0].id)
        progress.markCompleted(unit1.lessons[1].id)
        week = AppEntryView.weekProgress(WeeklyPlan.compute(progress: progress, now: monday, calendar: calendar))
        #expect(week.done == 2)
        #expect(week.goalMet)
        let nudges = ReminderPlanner.weeklyPlan(now: monday, calendar: calendar, week: week)
        #expect(!nudges.contains { $0.fireDate.month == 7 && $0.fireDate.day == 8 })
        #expect(nudges.first?.fireDate.day == 12)
    }
}
