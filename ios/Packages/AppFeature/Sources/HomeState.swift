import Foundation
import CurriculumFeature

/// Everything Home shows about where the student is: streak, this week's
/// plan, the next stop on the path, and the lesson they last opened. Built
/// from the stores by `build`, then rendered by `HomeView` without further
/// lookups, so the copy rules below are plain functions of this value.
struct HomeState: Equatable {
    /// A streak the server confirmed recently; 0 otherwise.
    let streak: Int
    let week: WeeklyPlan
    /// The path's frontier. Nil once every lesson and unit check is done.
    let next: MercuriusCurriculum.PathStop?
    /// Title of the lesson opened most recently, if any.
    let lastLessonTitle: String?
    /// The next stop is a lesson the student has already opened or started,
    /// so Home offers to continue it rather than to start something new.
    let resumesNext: Bool
    /// At least one lesson is complete.
    let hasProgress: Bool

    @MainActor
    static func build(
        streak: Int,
        progress: CurriculumProgressStore,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> HomeState {
        let next = progress.frontier()
        let lastLesson = progress.lastOpenedLessonId.flatMap { id in
            MercuriusCurriculum.allLessons.first { $0.id == id }
        }
        let resumesNext: Bool
        if case .lesson(let lesson) = next {
            resumesNext = lesson.id == lastLesson?.id || progress.state(of: lesson.id) == .inProgress
        } else {
            resumesNext = false
        }
        return HomeState(
            streak: max(streak, 0),
            week: WeeklyPlan.compute(progress: progress, now: now, calendar: calendar),
            next: next,
            lastLessonTitle: lastLesson?.title,
            resumesNext: resumesNext,
            hasProgress: progress.totalCompleted() > 0
        )
    }

    // MARK: - Copy

    /// The primary CTA: the next stop, named.
    var primaryActionTitle: String {
        switch next {
        case .lesson(let lesson):
            if !hasProgress && !resumesNext {
                return "Start Lesson \(lesson.number)"
            }
            return "Continue · Lesson \(lesson.number): \(lesson.title)"
        case .unitTest(let unit):
            return "Take the Unit \(Self.unitNumber(unit)) check"
        case nil:
            return "Review your lessons"
        }
    }

    var primaryActionHint: String {
        switch next {
        case .lesson: return "Opens the lesson"
        case .unitTest: return "Opens the unit check"
        case nil: return "Opens your learning path"
        }
    }

    /// "This week · 1 of 2". Past the goal it counts lessons instead of
    /// reading "3 of 2".
    var weekLabel: String {
        if week.done > week.goal {
            return "This week · \(week.done) lessons"
        }
        return "This week · \(week.done) of \(week.goal)"
    }

    var weekAccessibilityLabel: String {
        let lessons = week.done == 1 ? "lesson" : "lessons"
        if week.done > week.goal {
            return "This week: \(week.done) \(lessons) done. Weekly goal met."
        }
        return "This week: \(week.done) of \(week.goal) \(lessons) done."
    }

    /// 0…1 for the week ring.
    var weekProgress: Double {
        guard week.goal > 0 else { return 0 }
        return min(1, Double(week.done) / Double(week.goal))
    }

    /// Merc's opening line. `hour` is the local hour (0–23).
    func greeting(hour: Int) -> String {
        if streak > 1 {
            return "Day \(streak) — let's keep your streak alive!"
        }
        switch next {
        case nil:
            return "You've finished the whole path. Chat with me any time to go deeper."
        case .unitTest(let unit):
            return "Unit \(Self.unitNumber(unit))'s lessons are done. Ready for the check?"
        case .lesson:
            if resumesNext, let lastLessonTitle {
                return "Welcome back! Let's pick up “\(lastLessonTitle)”."
            }
            if week.done >= week.goal {
                return "\(Self.opener(hour: hour)) This week's goal is done — anything more is a bonus."
            }
            if !hasProgress {
                return "\(Self.opener(hour: hour)) Your first lesson is ready when you are."
            }
            return "\(Self.opener(hour: hour)) Your next lesson is waiting."
        }
    }

    static func opener(hour: Int) -> String {
        switch hour {
        case 5..<12:  return "Good morning!"
        case 12..<17: return "Good afternoon!"
        case 17..<22: return "Good evening!"
        default:      return "Up late? Perfect time to learn."
        }
    }

    /// "01" reads as "1" in a sentence.
    private static func unitNumber(_ unit: CurriculumFeature.Unit) -> String {
        Int(unit.number).map(String.init) ?? unit.number
    }
}

extension CurriculumProgressStore {
    /// The frontier's lesson id — what a tapped reminder opens. Nil when the
    /// frontier is a unit check or the path is finished.
    @MainActor
    var frontierLessonId: String? {
        if case .lesson(let lesson) = frontier() { return lesson.id }
        return nil
    }
}
