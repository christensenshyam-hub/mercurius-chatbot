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

    @Test("AI Basics isn't in this build: no Basics certificate until the seam gets its lessons")
    func basicsSeam() {
        #expect(CertificateCourses.basicsLessons == nil)
        let center = CertificateCenter.make(progress: CurriculumProgressStore(preferences: InMemoryPreferenceStore()),
                                            defaults: freshDefaults("wiring.basics"))
        #expect(center.kinds == [.deepDive])
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
