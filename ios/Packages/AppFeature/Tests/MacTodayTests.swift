#if os(macOS)
import Foundation
import Testing
@testable import AppFeature
import ChatFeature
import CurriculumFeature
import NetworkingKit
import PersistenceKit

/// What the Mac's Today overview says: the next stop, the week, the streak
/// (never a "0"), the question to think through and a recent chat's line —
/// in Night Studio's honest copy (SPEC.md §5.1, §6).
@Suite("Mac Today")
@MainActor
struct MacTodayTests {

    private func store() -> CurriculumProgressStore {
        CurriculumProgressStore(preferences: InMemoryPreferenceStore())
    }

    private var unit1: CurriculumFeature.Unit { MercuriusCurriculum.units[0] }

    @Test("A fresh path: Up next is Lesson 1 of Unit 1, to start")
    func freshPath() {
        let progress = store()
        let next = MacTodayView.upNext(state: HomeState.build(streak: 0, progress: progress), progress: progress)
        #expect(next.eyebrow == "Up next · Unit 1 · Lesson 1 of \(unit1.lessons.count)")
        #expect(next.title == unit1.lessons[0].title)
        #expect(next.detail == unit1.lessons[0].objective)
        #expect(next.buttonTitle == "Start Lesson 1")
        #expect(next.unitProgress?.done == 0)
        #expect(next.unitProgress?.label == "0 of \(unit1.lessons.count) lessons done in Unit 1")
    }

    @Test("An opened lesson is continued; the next one after a finished lesson is started")
    func continueOrStart() {
        let progress = store()
        progress.markOpened(unit1.lessons[0].id)
        let resumed = MacTodayView.upNext(state: HomeState.build(streak: 0, progress: progress), progress: progress)
        #expect(resumed.buttonTitle == "Continue Lesson 1")
        #expect(resumed.eyebrow == "Continue · Unit 1 · Lesson 1 of \(unit1.lessons.count)")
        progress.markCompleted(unit1.lessons[0].id)
        let next = MacTodayView.upNext(state: HomeState.build(streak: 0, progress: progress), progress: progress)
        #expect(next.buttonTitle == "Start Lesson 2")
        #expect(next.unitProgress?.done == 1)
    }

    @Test("A unit's lessons all done: Up next is its check")
    func unitCheck() {
        let progress = store()
        for lesson in unit1.lessons { progress.markCompleted(lesson.id) }
        let next = MacTodayView.upNext(state: HomeState.build(streak: 0, progress: progress), progress: progress)
        #expect(next.eyebrow == "Up next · Unit 1 check")
        #expect(next.buttonTitle == "Take the Unit 1 Check")
        #expect(next.title == unit1.title)
    }

    @Test("The whole path done: a review, no progress bar")
    func pathDone() {
        let progress = store()
        for unit in MercuriusCurriculum.units {
            for lesson in unit.lessons { progress.markCompleted(lesson.id) }
            progress.markUnitMastered(unit.id)
        }
        let next = MacTodayView.upNext(state: HomeState.build(streak: 0, progress: progress), progress: progress)
        #expect(next.buttonTitle == "Review Your Lessons")
        #expect(next.unitProgress == nil)
    }

    @Test("The streak card never says 0")
    func streakWords() {
        #expect(MacTodayView.streakHeadline(0) == "No streak yet")
        #expect(MacTodayView.streakHeadline(-2) == "No streak yet")
        #expect(MacTodayView.streakHeadline(1) == "1 day")
        #expect(MacTodayView.streakHeadline(6) == "6 days")
    }

    @Test("The week card counts lessons against the goal, and past it")
    func weekWords() {
        let start = Date()
        func week(_ done: Int, _ goal: Int) -> WeeklyPlan {
            WeeklyPlan(weekStart: start, done: done, goal: goal, next: [], projectedFinish: nil)
        }
        #expect(MacTodayView.weekHeadline(week(1, 2)) == "1 of 2 lessons")
        #expect(MacTodayView.weekHeadline(week(3, 2)) == "3 lessons")
        #expect(MacTodayView.weekDetail(week(1, 2)) == "Goal: 2 lessons a week.")
        #expect(MacTodayView.weekDetail(week(2, 2)) == "Goal met. Anything more is a bonus.")
    }

    @Test("The unit meter lights the done lessons, half-lights the next and leaves the rest faint")
    func unitMeterSegments() {
        let progress = store()
        progress.markCompleted(unit1.lessons[0].id)
        progress.markCompleted(unit1.lessons[1].id)
        let next = MacTodayView.upNext(state: HomeState.build(streak: 0, progress: progress), progress: progress)
        let expected: [MacTodayView.UpNext.UnitProgress.Segment] =
            [.done, .done, .current] + Array(repeating: .ahead, count: unit1.lessons.count - 3)
        #expect(next.unitProgress?.segments == expected)
        #expect(next.unitProgress?.label == "2 of \(unit1.lessons.count) lessons done in Unit 1")
    }

    @Test("The hero reads to VoiceOver as one header: the lesson, its objective, the unit's count")
    func heroAccessibility() {
        let progress = store()
        let next = MacTodayView.upNext(state: HomeState.build(streak: 0, progress: progress), progress: progress)
        let lesson = unit1.lessons[0]
        #expect(next.accessibilityLabel.hasPrefix("Lesson 1: \(lesson.title)."))
        #expect(next.accessibilityLabel.contains(lesson.objective))
        #expect(next.accessibilityLabel.hasSuffix("0 of \(unit1.lessons.count) lessons done in Unit 1."))
    }

    @Test("The greeting is HomeState's opener with a calm full stop")
    func greeting() {
        #expect(MacNightCopy.greeting(hour: 9) == "Good morning.")
        #expect(MacNightCopy.greeting(hour: 19) == "Good evening.")
        #expect(MacNightCopy.greeting(hour: 2) == "Hi there.")
    }

    @Test("The subline says where the student is, from HomeState, without the streak cheer")
    func subline() {
        let progress = store()
        #expect(MacNightCopy.subline(HomeState.build(streak: 9, progress: progress))
            == "Your first lesson is ready when you are.")
        progress.markOpened(unit1.lessons[0].id)
        #expect(MacNightCopy.subline(HomeState.build(streak: 9, progress: progress)) == "Your next lesson is waiting.")
        progress.markCompleted(unit1.lessons[0].id)
        progress.markCompleted(unit1.lessons[1].id)
        #expect(MacNightCopy.subline(HomeState.build(streak: 9, progress: progress))
            == "This week's goal is done — anything more is a bonus.")
        for lesson in unit1.lessons { progress.markCompleted(lesson.id) }
        #expect(MacNightCopy.subline(HomeState.build(streak: 0, progress: progress))
            == "Unit 1's lessons are done. Ready for the check?")
        for unit in MercuriusCurriculum.units {
            for lesson in unit.lessons { progress.markCompleted(lesson.id) }
            progress.markUnitMastered(unit.id)
        }
        #expect(MacNightCopy.subline(HomeState.build(streak: 0, progress: progress))
            == "You've finished the whole path. Chat with Merc any time to go deeper.")
    }

    @Test("The streak is one quiet line, only when there is one: never a zero, never 'rest days never reset'")
    func streakLine() {
        #expect(MacNightCopy.streakLine(0) == nil)
        #expect(MacNightCopy.streakLine(-1) == nil)
        #expect(MacNightCopy.streakLine(1) == "1 day running. One lesson or chat a day keeps it going.")
        #expect(MacNightCopy.streakLine(4) == "4 days running. One lesson or chat a day keeps it going.")
    }

    private var gregorian: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Chicago")!
        calendar.locale = Locale(identifier: "en_US")
        return calendar
    }

    private func date(_ day: Int, hour: Int = 12) -> Date {
        gregorian.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour))!
    }

    @Test("The week's seven days start on the plan's Thursday; lesson days and today are marked")
    func weekDays() {
        // Thursday 15 October 2026 is the week's start; today is Tuesday the 20th.
        let start = gregorian.startOfDay(for: date(15))
        let days = MacTodayView.weekDays(weekStart: start, completions: [date(16, hour: 9), date(20, hour: 8)],
                                         now: date(20), calendar: gregorian)
        #expect(days.count == 7)
        #expect(days.map(\.initial) == ["T", "F", "S", "S", "M", "T", "W"])
        #expect(days.map(\.hasLesson) == [false, true, false, false, false, true, false])
        #expect(days.map(\.isToday) == [false, false, false, false, false, true, false])
        #expect(days.filter(\.hasLesson).map(\.name) == ["Friday", "Tuesday"])
    }

    @Test("VoiceOver hears which days had lessons, and the streak line")
    func weekCardSentence() {
        #expect(MacNightCopy.lessonDaysSentence([]) == "No lessons yet this week.")
        #expect(MacNightCopy.lessonDaysSentence(["Friday"]) == "A lesson done on Friday.")
        #expect(MacNightCopy.lessonDaysSentence(["Tuesday", "Thursday"]) == "Lessons done on Tuesday and Thursday.")
        let label = MacNightCopy.weekCardAccessibilityLabel(weekLabel: "This week: 1 of 2 lessons done.",
                                                            dayNames: ["Friday"], streak: 0)
        #expect(label == "This week: 1 of 2 lessons done. A lesson done on Friday.")
        let withStreak = MacNightCopy.weekCardAccessibilityLabel(weekLabel: "This week: 0 of 2 lessons done.",
                                                                 dayNames: [], streak: 3)
        #expect(withStreak.hasSuffix("3 days running. One lesson or chat a day keeps it going."))
    }

    @Test("Think it through offers one of the current mode's real prompts, the same all day")
    func thinkPrompt() {
        for mode in ChatMode.allCases {
            let prompts = ModePromptProvider.prompts(for: mode)
            let morning = MacTodayView.thinkPrompt(mode: mode, on: date(20, hour: 7), calendar: gregorian)
            let night = MacTodayView.thinkPrompt(mode: mode, on: date(20, hour: 23), calendar: gregorian)
            #expect(prompts.contains(morning))
            #expect(morning == night)
        }
        let monday = MacTodayView.thinkPrompt(mode: .socratic, on: date(19), calendar: gregorian)
        let tuesday = MacTodayView.thinkPrompt(mode: .socratic, on: date(20), calendar: gregorian)
        #expect(monday != tuesday, "it moves on day by day")
        #expect(MacNightCopy.thinkEyebrow(modeName: ChatMode.debate.displayName) == "Think it through · Debate")
    }

    @Test("The week and Think it through sit side by side while each gets 300 pt")
    func cardsFold() {
        #expect(MacTodayView.cardsSideBySide(columnWidth: 760))
        #expect(MacTodayView.cardsSideBySide(columnWidth: 652), "the 700 pt window, sidebar folded")
        #expect(!MacTodayView.cardsSideBySide(columnWidth: 600))
    }

    @Test("A recent chat's line names its mode")
    func chatLine() {
        let summary = ConversationSummary(id: UUID(), mode: "debate", title: "Is AI art art?", preview: "",
                                          messageCount: 4, createdAt: Date(), updatedAt: Date())
        #expect(MacTodayView.chatDetail(summary).hasPrefix("Debate · "))
    }
}
#endif
