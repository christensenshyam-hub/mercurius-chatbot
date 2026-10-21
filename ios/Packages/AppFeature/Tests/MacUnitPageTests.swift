#if os(macOS)
import Foundation
import Testing
@testable import AppFeature
@testable import ChatFeature
import CurriculumFeature
import PersistenceKit

/// The Mac's unit page (SPEC.md §5.2): every stop's state comes from the
/// iPhone's own gating, said in numbers instead of padlocks.
@Suite("Mac unit page")
@MainActor
struct MacUnitPageTests {
    private let unit1 = MercuriusCurriculum.units[0]
    private let unit2 = MercuriusCurriculum.units[1]

    private func store() -> CurriculumProgressStore {
        CurriculumProgressStore(preferences: InMemoryPreferenceStore())
    }

    @Test("A fresh unit: Lesson 1.1 is lit, each later one opens after the one before, the check after 1.4")
    func fresh() {
        let page = MacUnitPage.page(unit: unit1, progress: store())
        #expect(page.lessons.map(\.code) == ["1.1", "1.2", "1.3", "1.4"])
        #expect(page.lessons[0].state == .current(isFrontier: true, inProgress: false))
        for index in 1..<page.lessons.count {
            #expect(page.lessons[index].state == .locked(after: unit1.lessons[index - 1]))
        }
        #expect(page.check == .locked(after: unit1.lessons[3]))
        #expect(page.status == "Not started")
        #expect(MacUnitPage.checkNote(page) == "Opens after 1.4")
        #expect(MacUnitPage.coverMeterLabel(page) == "0 of 4 lessons · then the unit check")
        #expect(!page.checkIsPrimary)
    }

    @Test("Two lessons done: they're marked done, 1.3 is lit, 1.4 opens after 1.3")
    func midway() {
        let progress = store()
        progress.markCompleted(unit1.lessons[0].id)
        progress.markCompleted(unit1.lessons[1].id)
        let page = MacUnitPage.page(unit: unit1, progress: progress)
        #expect(page.lessons[0].state == .done)
        #expect(page.lessons[1].state == .done)
        #expect(page.lessons[2].state == .current(isFrontier: true, inProgress: false))
        #expect(page.lessons[3].state == .locked(after: unit1.lessons[2]))
        #expect(MacUnitPage.opensAfter("1.3") == "Opens after 1.3")
        #expect(page.status == "In progress")
        #expect(MacUnitPage.coverMeterLabel(page) == "2 of 4 lessons · then the unit check")
    }

    @Test("A lesson in progress says Continue; another unit's first lesson is next in its unit, not \"You're here\"")
    func continueAndFrontier() {
        let progress = store()
        progress.markInProgress(unit1.lessons[0].id, conversationId: UUID())
        let page1 = MacUnitPage.page(unit: unit1, progress: progress)
        #expect(page1.lessons[0].state == .current(isFrontier: true, inProgress: true))
        #expect(page1.status == "In progress")
        #expect(MacUnitPage.currentButton(code: "1.1", inProgress: true) == "Continue Lesson 1.1")
        #expect(MacUnitPage.currentButton(code: "1.1", inProgress: false) == "Start Lesson 1.1")
        // Units aren't gated: Unit 2 opens on its first lesson, which isn't
        // the student's frontier.
        let page2 = MacUnitPage.page(unit: unit2, progress: progress)
        #expect(page2.lessons[0].state == .current(isFrontier: false, inProgress: false))
        #expect(MacUnitPage.currentEyebrow(code: "2.1", isFrontier: false) == "Lesson 2.1 · Next in this unit")
        #expect(MacUnitPage.currentEyebrow(code: "1.1", isFrontier: true) == "Lesson 1.1 · You're here")
    }

    @Test("Today and the unit page say the same word and label for the same lesson")
    func sameWordEverywhere() {
        // The seeded week: 1.1 and 1.2 done, 1.3 opened (not yet started).
        let progress = store()
        progress.markCompleted(unit1.lessons[0].id)
        progress.markCompleted(unit1.lessons[1].id)
        progress.markOpened(unit1.lessons[2].id)
        let today = MacTodayView.upNext(state: HomeState.build(streak: 4, progress: progress), progress: progress)
        let page = MacUnitPage.page(unit: unit1, progress: progress)
        guard case .current(_, let resumes) = page.lessons[2].state else {
            Issue.record("1.3 should be current")
            return
        }
        #expect(today.buttonTitle == "Continue Lesson 1.3")
        #expect(MacUnitPage.currentButton(code: page.lessons[2].code, inProgress: resumes) == today.buttonTitle)
        #expect(today.eyebrow == "Continue · Lesson 1.3")
        // The predicate is HomeState's own.
        #expect(MacNightCopy.resumes(lessonId: unit1.lessons[2].id, progress: progress)
            == HomeState.build(streak: 0, progress: progress).resumesNext)
    }

    @Test("Every lesson done: the check is open and is the page's prominent action; mastered once passed")
    func check() {
        let progress = store()
        for lesson in unit1.lessons { progress.markCompleted(lesson.id) }
        let open = MacUnitPage.page(unit: unit1, progress: progress)
        #expect(open.check == .open)
        #expect(open.checkIsPrimary)
        #expect(open.status == "All lessons done")
        #expect(MacUnitPage.checkNote(open) == nil)
        progress.markUnitMastered(unit1.id)
        let mastered = MacUnitPage.page(unit: unit1, progress: progress)
        #expect(mastered.check == .mastered)
        #expect(mastered.status == "Mastered")
        #expect(MacUnitPage.checkNote(mastered) == "Mastered")
        #expect(MacUnitPage.coverEyebrow(mastered) == "Unit 01 · Mastered")
    }

    @Test("Progress merged out of order: an unlocked lesson past the lit one opens, without the prominent button")
    func outOfOrder() {
        let progress = store()
        progress.markCompleted(unit1.lessons[1].id)
        let page = MacUnitPage.page(unit: unit1, progress: progress)
        #expect(page.lessons[0].state == .current(isFrontier: true, inProgress: false))
        #expect(page.lessons[1].state == .done)
        #expect(page.lessons[2].state == .open)
        #expect(page.lessons[3].state == .locked(after: unit1.lessons[2]))
    }

    @Test("The next unit is named with its summary; the last unit has none")
    func nextUnit() {
        let page = MacUnitPage.page(unit: unit1, progress: store())
        #expect(page.nextUnit?.id == unit2.id)
        #expect(MacUnitPage.nextUnitLabel(unit2) == "Unit 2 · Bias & Fairness")
        if let last = MercuriusCurriculum.units.last {
            #expect(MacUnitPage.page(unit: last, progress: store()).nextUnit == nil)
        }
        #expect(MacUnitPage.subtitle(unitId: unit1.id) == "Unit 1 of \(MercuriusCurriculum.units.count)")
    }

    @Test("VoiceOver hears each row in words: done, you're here, opens after")
    func spoken() {
        let progress = store()
        progress.markCompleted(unit1.lessons[0].id)
        let page = MacUnitPage.page(unit: unit1, progress: progress)
        #expect(MacUnitPage.lessonAccessibility(page.lessons[0])
                == "Lesson 1.1, done: What happens when you type a prompt.")
        #expect(MacUnitPage.lessonAccessibility(page.lessons[1]).hasPrefix("Lesson 1.2, you're here: "))
        #expect(MacUnitPage.lessonAccessibility(page.lessons[2]).hasPrefix("Lesson 1.3, opens after lesson 1.2: "))
        #expect(MacUnitPage.checkAccessibility(page).hasPrefix("Unit 1 check, opens after lesson 1.4: "))
        #expect(MacUnitPage.checkDetail(questionCount: 5) == "5 questions, then one written answer Merc grades.")
    }

    @Test("The complete card's week: this week's count, and whether this lesson is in it")
    func lessonWeek() {
        let progress = store()
        let lesson = unit1.lessons[0]
        let none = MacShellView.lessonWeek(lessonId: lesson.id, progress: progress)
        #expect(none.done == 0)
        #expect(none.goal == 2)
        #expect(!none.includesThisLesson)
        progress.markCompleted(lesson.id)
        let one = MacShellView.lessonWeek(lessonId: lesson.id, progress: progress)
        #expect(one.done == 1)
        #expect(one.includesThisLesson)
        #expect(one.before == 0)
    }

    @Test("Every \"Understand …\" objective in the curriculum gives a credential; no other one does")
    func credentialsAcrossTheCurriculum() {
        var credentials = 0
        for lesson in MercuriusCurriculum.allLessons {
            let credential = NightCompleteCopy.credential(objective: lesson.objective)
            if lesson.objective.hasPrefix("Understand ") {
                credentials += 1
                #expect(credential?.hasPrefix("You can now explain ") == true, "\(lesson.id)")
                #expect(credential?.hasSuffix(".") == true)
                #expect(credential?.contains("..") == false)
            } else {
                #expect(credential == nil, "\(lesson.id): \(lesson.objective)")
            }
        }
        // SYNTHESIS.md Q3: about 15 of the objectives read "Understand …".
        #expect(credentials >= 10)
    }
}
#endif
