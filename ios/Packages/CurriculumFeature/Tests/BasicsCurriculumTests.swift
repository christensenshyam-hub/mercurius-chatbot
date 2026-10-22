import Foundation
import Testing
import DesignSystem
import SwiftUI
@testable import CurriculumFeature

/// The Basics course's data, its ids and opener tags, its own progress, and
/// the learner's track choice.
@Suite("Basics curriculum")
@MainActor
struct BasicsCurriculumTests {

    // MARK: - Shape and ids

    @Test("Five units, eighteen lessons, b<unit>_l<lesson> ids, basics_<n> units")
    func shapeAndIds() {
        let units = BasicsCurriculum.units
        #expect(units.map(\.id) == ["basics_1", "basics_2", "basics_3", "basics_4", "basics_5"])
        #expect(units.map { $0.lessons.count } == [3, 4, 3, 4, 4])
        #expect(BasicsCurriculum.allLessons.count == 18)
        for (u, unit) in units.enumerated() {
            #expect(unit.number == String(format: "%02d", u + 1))
            #expect(unit.id == BasicsCurriculum.unitId(u + 1))
            for (l, lesson) in unit.lessons.enumerated() {
                #expect(lesson.number == l + 1)
                #expect(lesson.id == BasicsCurriculum.lessonId(unit: u + 1, lesson: l + 1))
                #expect(BasicsCurriculum.isBasicsId(lesson.id))
            }
        }
        #expect(BasicsCurriculum.allLessons.first?.id == "b1_l1")
        #expect(BasicsCurriculum.allLessons.last?.id == "b5_l4")
    }

    @Test("Basics and Deep-dive ids never overlap, and each id names its track")
    func idsBelongToOneTrack() {
        let basics = Set(BasicsCurriculum.allLessons.map(\.id) + BasicsCurriculum.units.map(\.id))
        let deepDive = Set(MercuriusCurriculum.allLessons.map(\.id) + MercuriusCurriculum.units.map(\.id))
        #expect(basics.isDisjoint(with: deepDive))
        for id in basics { #expect(CurriculumTrack.of(id: id) == .basics) }
        for id in deepDive { #expect(CurriculumTrack.of(id: id) == .deepDive) }
        #expect(CurriculumTrack.of(id: "b1") == nil)
        #expect(CurriculumTrack.of(id: "basics") == nil)
        #expect(CurriculumTrack.of(id: "x1_l1") == nil)
        #expect(CurriculumTrack.unit(containingLesson: "b2_l3")?.id == "basics_2")
        #expect(CurriculumTrack.unit(containingLesson: "u2_l3")?.id == "unit_2")
        #expect(CurriculumTrack.lesson(withId: "b5_l4")?.title == "On your own")
    }

    @Test("Basics has no unit checks; the Deep dive does")
    func unitChecks() {
        #expect(!CurriculumTrack.basics.hasUnitTests)
        #expect(CurriculumTrack.deepDive.hasUnitTests)
        for unit in BasicsCurriculum.units {
            #expect(MercuriusCurriculum.unitTest(for: unit.id) == nil)
        }
    }

    // MARK: - Opener tags

    @Test("Every starter opens with the server's canonical Basics tag for its own lesson")
    func canonicalTags() {
        for unit in BasicsCurriculum.units {
            let u = Int(unit.number) ?? 0
            for lesson in unit.lessons {
                let tag = BasicsCurriculum.tag(unit: u, lesson: lesson.number)
                #expect(tag == "[BASICS: Unit \(u), Lesson \(lesson.number)]")
                #expect(lesson.starter.hasPrefix(tag + " "), "\(lesson.id): \(lesson.starter)")
                // Never the alias: a server from before Basics routes it into
                // the Deep-dive guide.
                #expect(!lesson.starter.contains("[CURRICULUM"))
                #expect(!lesson.starter.dropFirst().contains("["), "one tag, at index 0 only")
            }
        }
    }

    @Test("The server's Basics pattern parses every starter back to its b id")
    func serverPatternParses() throws {
        // lib/curriculumTag.js (feat/basics-server), case-sensitive, index 0.
        let regex = try NSRegularExpression(
            pattern: #"^\[BASICS:\s*Unit\s*(\d+)[\s,·•\-–—/|:;]*Lesson\s*(\d+)[^\]]*\]"#)
        for lesson in BasicsCurriculum.allLessons {
            let text = lesson.starter
            let match = try #require(regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)))
            let unit = try #require(Range(match.range(at: 1), in: text).map { Int(text[$0]) } ?? nil)
            let number = try #require(Range(match.range(at: 2), in: text).map { Int(text[$0]) } ?? nil)
            #expect(BasicsCurriculum.lessonId(unit: unit, lesson: number) == lesson.id)
        }
        // And no Deep-dive starter ever matches it.
        for lesson in MercuriusCurriculum.allLessons {
            let text = lesson.starter
            #expect(regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) == nil)
        }
    }

    // MARK: - The reviewed content

    /// docs/basics/basics.json: the curriculum file, with its starters' tag
    /// rewritten to the canonical form.
    private struct File: Decodable {
        struct FileUnit: Decodable {
            let id: String
            let number: String
            let title: String
            let summary: String
            let lessons: [FileLesson]
        }
        struct FileLesson: Decodable {
            let id: String
            let number: Int
            let title: String
            let objective: String
            let starter: String
        }
        let track: String
        let units: [FileUnit]
    }

    @Test("The Swift data is the reviewed curriculum (docs/basics/basics.json), word for word")
    func matchesCurriculumFile() throws {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // Tests
            .deletingLastPathComponent()   // CurriculumFeature
            .deletingLastPathComponent()   // Packages
            .deletingLastPathComponent()   // ios
            .deletingLastPathComponent()   // repo
            .appendingPathComponent("docs/basics/basics.json")
        let file = try JSONDecoder().decode(File.self, from: Data(contentsOf: url))
        #expect(file.track == "basics")
        #expect(file.units.count == BasicsCurriculum.units.count)
        for (fileUnit, unit) in zip(file.units, BasicsCurriculum.units) {
            #expect(fileUnit.id == unit.id)
            #expect(fileUnit.number == unit.number)
            #expect(fileUnit.title == unit.title)
            #expect(fileUnit.summary == unit.summary)
            #expect(fileUnit.lessons.count == unit.lessons.count)
            for (fileLesson, lesson) in zip(fileUnit.lessons, unit.lessons) {
                #expect(fileLesson.id == lesson.id)
                #expect(fileLesson.number == lesson.number)
                #expect(fileLesson.title == lesson.title)
                #expect(fileLesson.objective == lesson.objective)
                #expect(fileLesson.starter == lesson.starter)
            }
        }
    }

    @Test("Every lesson has a Try this today; quoted messages come out ready to copy")
    func tryThisToday() {
        for lesson in BasicsCurriculum.allLessons {
            let line = BasicsCurriculum.tryThisToday(for: lesson.id)
            #expect(line?.isEmpty == false, "\(lesson.id) has no Try this today")
        }
        #expect(BasicsCurriculum.tryThisToday(for: "u1_l1") == nil)
        #expect(BasicsCurriculum.tryThisTodayMessage(for: "b3_l3") == "What could go wrong?")
        #expect(BasicsCurriculum.tryThisTodayMessage(for: "b2_l2") == "What does that mean?")
        #expect(BasicsCurriculum.tryThisTodayMessage(for: "b5_l1") == "Where could I check this?")
        #expect(BasicsCurriculum.tryThisTodayMessage(for: "b1_l1") == nil, "a task with no message")
        #expect(BasicsCurriculum.quotedMessage(in: #"Ask: "Is it safe?""#) == "Is it safe?")
        #expect(BasicsCurriculum.quotedMessage(in: "No quotes here.") == nil)
        #expect(BasicsCurriculum.quotedMessage(in: "Open “ only") == nil)
    }

    @Test("The four safety lessons are the server's")
    func safetyLessons() {
        #expect(BasicsCurriculum.safetyLessonIds == ["b2_l3", "b2_l4", "b5_l2", "b5_l3"])
        for id in BasicsCurriculum.safetyLessonIds {
            #expect(BasicsCurriculum.lesson(withId: id) != nil)
        }
    }

    @Test("Basics' words stay plain: no \"easy\", \"just\" or \"simply\" in a title, objective or task")
    func plainWords() {
        let banned = ["easy", "just ", "simply", "obviously", "of course", "quickly", "in seconds"]
        let texts = BasicsCurriculum.units.flatMap { [$0.title, $0.summary] + $0.lessons.flatMap { [$0.title, $0.objective] } }
            + BasicsCurriculum.allLessons.compactMap { BasicsCurriculum.tryThisToday(for: $0.id) }
        for text in texts {
            for word in banned {
                #expect(!text.lowercased().contains(word), "\"\(word)\" in: \(text)")
            }
        }
    }

    // MARK: - Progress, per track

    private func makeStore() -> CurriculumProgressStore {
        CurriculumProgressStore(preferences: InMemoryPreferenceStore())
    }

    @Test("Basics completions never move the Deep dive's counts or frontier, nor the other way round")
    func countsArePerTrack() {
        let store = makeStore()
        store.markCompleted("b1_l1")
        store.markCompleted("b1_l2")
        #expect(store.totalCompleted() == 0)
        #expect(store.totalCompleted(in: .deepDive) == 0)
        #expect(store.totalCompleted(in: .basics) == 2)
        #expect(store.totalLessons == 35)
        #expect(store.totalLessons(in: .basics) == 18)
        #expect(store.frontier() == .lesson(MercuriusCurriculum.units[0].lessons[0]))

        store.markCompleted("u1_l1")
        #expect(store.totalCompleted() == 1)
        #expect(store.totalCompleted(in: .basics) == 2)
        #expect(store.frontier(in: .basics) == .lesson(BasicsCurriculum.units[0].lessons[2]))
    }

    @Test("Basics' frontier walks its lessons in order and is never a unit check")
    func basicsFrontier() {
        let store = makeStore()
        #expect(store.frontierLessonId(in: .basics) == "b1_l1")
        for lesson in BasicsCurriculum.units[0].lessons { store.markCompleted(lesson.id) }
        // Unit 1 done: no check to take, so the next unit's first lesson.
        #expect(store.frontierLessonId(in: .basics) == "b2_l1")
        for lesson in BasicsCurriculum.allLessons { store.markCompleted(lesson.id) }
        #expect(store.frontier(in: .basics) == nil)
        #expect(store.frontierLessonId(in: .basics) == nil)
        #expect(store.frontier() == .lesson(MercuriusCurriculum.units[0].lessons[0]), "the Deep dive is untouched")
    }

    @Test("Basics ids go into the one snapshot, under the app's curriculum version")
    func snapshotCarriesBasicsIds() {
        let store = makeStore()
        store.markCompleted("b2_l3")
        store.markCompleted("u1_l1")
        let snapshot = store.snapshot()
        #expect(snapshot.completed == ["b2_l3", "u1_l1"])
        #expect(snapshot.curriculumVersion == MercuriusCurriculum.version)
        #expect(snapshot.curriculumVersion == 1)
    }

    @Test("A server merge with Basics ids counts them in Basics only")
    func mergeBasicsIds() {
        let store = makeStore()
        let changed = store.merge(completed: ["b1_l1", "b1_l2", "u1_l1"], mastered: [], remoteVersion: 1)
        #expect(changed)
        #expect(store.totalCompleted(in: .basics) == 2)
        #expect(store.totalCompleted() == 1)
        #expect(store.state(of: "b1_l2") == .completed)
        #expect(store.frontierLessonId(in: .basics) == "b1_l3")
    }

    @Test("Basics' unlocks are the Deep dive's rule: in order within a unit, units independent")
    func basicsUnlocks() {
        let store = makeStore()
        let unit2 = BasicsCurriculum.units[1]
        #expect(store.isLessonUnlocked(unit2.lessons[0], in: unit2))
        #expect(!store.isLessonUnlocked(unit2.lessons[1], in: unit2))
        store.markCompleted(unit2.lessons[0].id)
        #expect(store.isLessonUnlocked(unit2.lessons[1], in: unit2))
    }

    // MARK: - The track choice

    @Test("No choice yet reads as the Deep dive; a choice persists")
    func trackChoicePersists() {
        let prefs = InMemoryPreferenceStore()
        let store = CurriculumTrackStore(preferences: prefs)
        #expect(store.track == .deepDive)
        #expect(!store.hasChosen)
        #expect(!store.offersReadingSize, "the size offer is Basics'")

        store.choose(.basics)
        #expect(store.track == .basics)
        #expect(store.hasChosen)
        #expect(store.offersReadingSize)

        let reopened = CurriculumTrackStore(preferences: prefs)
        #expect(reopened.track == .basics)
        #expect(reopened.hasChosen)

        reopened.choose(.deepDive)
        #expect(CurriculumTrackStore(preferences: prefs).track == .deepDive)
    }

    @Test("The Basics reading size persists and answers the one-time offer")
    func readingSizePersists() {
        let prefs = InMemoryPreferenceStore()
        let store = CurriculumTrackStore(preferences: prefs)
        store.choose(.basics)
        #expect(store.basicsReadingSize == .standard)
        store.setBasicsReadingSize(.larger)
        #expect(!store.offersReadingSize)
        let reopened = CurriculumTrackStore(preferences: prefs)
        #expect(reopened.basicsReadingSize == .larger)
        #expect(reopened.readingSizeOfferHandled)

        let other = CurriculumTrackStore(preferences: InMemoryPreferenceStore())
        other.choose(.basics)
        other.markReadingSizeOfferHandled()
        #expect(!other.offersReadingSize)
        #expect(other.basicsReadingSize == .standard, "closing the offer keeps the size")
    }

    @Test("A stored value this build doesn't know reads as no choice")
    func unknownStoredTrack() {
        let prefs = InMemoryPreferenceStore()
        prefs.set("advanced", for: "com.mayoailiteracy.mercurius.curriculumTrack")
        let store = CurriculumTrackStore(preferences: prefs)
        #expect(store.track == .deepDive)
        #expect(!store.hasChosen)
    }

    @Test("Reading sizes are floors: the larger of the system's and the choice")
    func readingSizeFloors() {
        #expect(ReadingSize.standard.applied(to: .small) == .small)
        #expect(ReadingSize.larger.applied(to: .large) == .xLarge)
        #expect(ReadingSize.larger.applied(to: .accessibility3) == .accessibility3)
        #expect(ReadingSize.largest.applied(to: .large) == .xxxLarge)
        #expect(ReadingSize.allCases.map(\.symbol) == ["A", "A+", "A++"])
    }

    @Test("The size offer stays away once the system's own size is the largest choice or more")
    func readingSizeOfferWhenUseful() {
        #expect(ReadingSize.standard.offersChoice(atFlooredSize: .large))
        #expect(ReadingSize.standard.offersChoice(atFlooredSize: .xxLarge))
        #expect(!ReadingSize.standard.offersChoice(atFlooredSize: .xxxLarge))
        #expect(!ReadingSize.standard.offersChoice(atFlooredSize: .accessibility3))
        // The largest choice's own floor: the learner can still come back down.
        #expect(ReadingSize.largest.offersChoice(atFlooredSize: .xxxLarge))
        #expect(!ReadingSize.largest.offersChoice(atFlooredSize: .accessibility1))
        #expect(!ReadingSize.larger.offersChoice(atFlooredSize: .xxxLarge))
    }

    @Test("The Basics path is \"Lessons\", not the school word \"Curriculum\" (review 2026-10-22)")
    func pathTitle() {
        #expect(CurriculumView<EmptyView>.title(unitId: nil, track: .basics) == "Lessons")
        #expect(CurriculumView<EmptyView>.title(unitId: nil, track: .deepDive) == "Curriculum")
        #expect(CurriculumView<EmptyView>.title(unitId: "unit_1", track: .deepDive) == CurriculumView<EmptyView>.title(unitId: "unit_1"))
    }
}
