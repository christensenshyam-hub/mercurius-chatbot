import Foundation
import Testing
@testable import AppFeature
import CurriculumFeature
import DesignSystem
import EngagementFeature
import SettingsFeature

/// The app's certificates against the curriculum it ships.
@Suite("Certificate wiring")
@MainActor
struct CertificateWiringTests {
    @Test("The Deep dive asks for exactly the eight unit checks, unit_1 … unit_8")
    func deepDiveUnits() {
        #expect(CertificateCourses.deepDiveUnits.map { $0.id } == CertificateEligibility.deepDiveUnitIds)
        #expect(CertificateCourses.deepDiveUnits.first?.title == "Unit 1 · How AI Actually Works")
    }

    @Test("The certificate's words match the course: eight units, thirty-five lessons")
    func copyMatchesCurriculum() {
        #expect(MercuriusCurriculum.units.count == 8)
        #expect(MercuriusCurriculum.allLessons.count == 35)
        #expect(CertificateCopy.paragraphLines(.deepDive).joined(separator: " ")
            .contains("eight units, thirty-five lessons and eight mastery checks"))
        #expect(CertificateCopy.unitLines(.deepDive).joined(separator: " · ").components(separatedBy: " · ").count == 8)
    }

    @Test("AI Basics asks for its 18 lessons, b1_l1 … b5_l4, in course order, as the progress store records them")
    func basicsLessons() {
        let lessons = CertificateCourses.basicsLessons
        #expect(lessons.count == 18)
        #expect(lessons.map { $0.id } == BasicsCurriculum.allLessons.map(\.id))
        #expect(lessons.first?.id == "b1_l1")
        #expect(lessons.last?.id == "b5_l4")
        #expect(lessons.allSatisfy { CurriculumTrack.of(id: $0.id) == .basics })
        // Named for "what's left": "Unit N · <lesson>".
        #expect(lessons.first?.title == "Unit 1 · What is an AI chatbot?")
        #expect(lessons.map { $0.title }.contains("Unit 2 · Following up"))
        #expect(lessons.last?.title == "Unit 5 · On your own")
        let center = CertificateCenter.make(progress: CurriculumProgressStore(preferences: InMemoryPreferenceStore()),
                                            defaults: freshDefaults("wiring.basics"))
        #expect(center.kinds == [.deepDive, .basics])
        #expect(center.status(.basics)?.progressText == "0 of 18 lessons finished")
    }

    @Test("What's left of AI Basics names one real lesson, never a run of titles with commas and \"and\"")
    func basicsRemainingText() {
        let lessons = CertificateCourses.basicsLessons
        func remaining(finished: [String]) -> String? {
            CertificateEligibility.basics(lessons: lessons, completedLessonIds: Set(finished)).remainingText
        }
        #expect(remaining(finished: []) == "Next: Unit 1 · What is an AI chatbot?")
        // Twelve in course order: the next is "Meals, plans and lists", and
        // "Learn something new, with a photo" (after it) isn't run into it.
        let twelve = remaining(finished: lessons.prefix(12).map { $0.id })
        #expect(twelve == "Next: Unit 4 · Meals, plans and lists")
        #expect(twelve?.contains("with a photo") == false)
        // Out of order: the first one not finished, in course order.
        #expect(remaining(finished: lessons.map { $0.id }.filter { $0 != "b1_l3" && $0 != "b5_l2" })
                == "Next: Unit 1 · What chatbots get wrong")
        #expect(remaining(finished: lessons.dropLast().map { $0.id }) == "Next: Unit 5 · On your own")
        #expect(remaining(finished: lessons.map { $0.id }) == nil)
    }

    @Test("Finishing the 18th Basics lesson through the progress store earns AI Basics, then and there")
    func basicsEarnedThroughProgress() {
        let progress = CurriculumProgressStore(preferences: InMemoryPreferenceStore())
        let center = CertificateCenter.make(progress: progress, defaults: freshDefaults("wiring.basics.18th"))
        // Out of order: the 18th to finish needn't be b5_l4.
        let ids = BasicsCurriculum.allLessons.map(\.id)
        let last = "b3_l2"
        for id in ids where id != last {
            #expect(center.recordingNewlyEarned { progress.markCompleted(id) }.isEmpty)
        }
        #expect(center.justEarned == nil)
        #expect(center.status(.basics)?.remaining.map { $0.id } == [last])
        #expect(center.store.earnedAt(.basics) == nil)
        let newly = center.recordingNewlyEarned { progress.markCompleted(last) }
        #expect(newly == [.basics])
        #expect(center.justEarned == .basics)
        #expect(center.store.earnedAt(.basics) != nil)
        // It prints the day the 18th lesson was finished, fixed from then on.
        let finished = progress.completedAt(last)
        #expect(finished != nil)
        #expect(center.status(.basics)?.lastMetAt == finished)
        #expect(center.completionDate(.basics) == finished)
        #expect(center.store.completionDate(.basics) == finished)
        // Finishing a lesson again doesn't re-earn it.
        center.justEarned = nil
        #expect(center.recordingNewlyEarned { progress.markCompleted(last) }.isEmpty)
        #expect(center.justEarned == nil)
    }

    @Test("A Deep-dive completion never earns AI Basics")
    func deepDiveNeverEarnsBasics() {
        let progress = CurriculumProgressStore(preferences: InMemoryPreferenceStore())
        let center = CertificateCenter.make(progress: progress, defaults: freshDefaults("wiring.basics.deepdive"))
        // Every Basics lesson but one done, then the whole Deep dive.
        for lesson in BasicsCurriculum.allLessons.dropLast() { progress.markCompleted(lesson.id) }
        for lesson in MercuriusCurriculum.allLessons {
            #expect(center.recordingNewlyEarned { progress.markCompleted(lesson.id) }.isEmpty)
        }
        #expect(center.justEarned == nil)
        #expect(center.status(.basics)?.isEarned == false)
        #expect(center.status(.basics)?.remaining.map { $0.id } == ["b5_l4"])
        #expect(center.store.earnedAt(.basics) == nil)
        // The Deep dive's own certificate comes from its checks only.
        for unit in MercuriusCurriculum.units {
            center.recordingNewlyEarned { progress.markUnitMastered(unit.id) }
        }
        #expect(center.justEarned == .deepDive)
        #expect(center.status(.basics)?.isEarned == false)
    }

    @Test("Mastering the eighth unit through the progress store earns the Deep dive, then and there")
    func earnedThroughProgress() {
        let progress = CurriculumProgressStore(preferences: InMemoryPreferenceStore())
        let center = CertificateCenter.make(progress: progress, defaults: freshDefaults("wiring.earned"))
        for unit in MercuriusCurriculum.units.dropLast() {
            center.recordingNewlyEarned { progress.markUnitMastered(unit.id) }
        }
        #expect(center.status(.deepDive)?.isEarned == false)
        #expect(center.status(.deepDive)?.remaining.map { $0.id } == ["unit_8"])
        let newly = center.recordingNewlyEarned { progress.markUnitMastered("unit_8") }
        #expect(newly == [.deepDive])
        #expect(center.justEarned == .deepDive)
        #expect(center.masteryAccessory(open: { _ in }) != nil)
        // A reset of progress takes the certificate away with it.
        progress.reset()
        #expect(center.status(.deepDive)?.isEarned == false)
    }

    @Test("Settings' reset takes a waiting course-complete card with it, so a later pass can't bring it back")
    func resetClearsTheCard() {
        let progress = CurriculumProgressStore(preferences: InMemoryPreferenceStore())
        let center = CertificateCenter.make(progress: progress, defaults: freshDefaults("wiring.reset.card"))
        for unit in MercuriusCurriculum.units {
            center.recordingNewlyEarned { progress.markUnitMastered(unit.id) }
        }
        #expect(center.justEarned == .deepDive)
        // The Mac: the check left by the sidebar, then everything erased.
        progress.reset()
        center.reset()
        #expect(center.justEarned == nil)
        #expect(center.store.name == nil)
        // A later pass of Unit 1 shows no card.
        center.recordingNewlyEarned { progress.markUnitMastered("unit_1") }
        #expect(center.justEarned == nil)
        #expect(center.masteryAccessory(open: { _ in }) == nil)
    }

    @Test("Basics lessons in the shared progress store count once the seam has them")
    func basicsThroughProgressStore() {
        let progress = CurriculumProgressStore(preferences: InMemoryPreferenceStore())
        let center = CertificateCenter.make(progress: progress, defaults: freshDefaults("wiring.basics.done"))
        let lessons = (1...3).map { CertificateRequirement(id: "b1_l\($0)", title: "Basics 1.\($0)") }
        center.basicsLessons = lessons
        progress.markCompleted("b1_l1")
        progress.markCompleted("b1_l2")
        #expect(center.status(.basics)?.met == 2)
        let newly = center.recordingNewlyEarned { progress.markCompleted("b1_l3") }
        #expect(newly == [.basics])
        #expect(center.status(.basics)?.lastMetAt == progress.completedAt("b1_l3"))
    }
}
