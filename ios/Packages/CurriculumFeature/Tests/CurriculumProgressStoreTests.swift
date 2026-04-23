import Testing
import Foundation
@testable import CurriculumFeature
@testable import SettingsFeature

/// Minimal in-memory `PreferenceStore` for tests. Mirrors the one in
/// SettingsFeatureTests but kept local so this package's tests don't
/// cross-module-depend on another package's test target.
private final class InMemoryPreferenceStore: PreferenceStore, @unchecked Sendable {
    private var storage: [String: String] = [:]
    func string(for key: String) -> String? { storage[key] }
    func set(_ value: String?, for key: String) {
        if let value { storage[key] = value } else { storage.removeValue(forKey: key) }
    }
}

@Suite("MercuriusCurriculum data")
struct CurriculumDataTests {

    @Test("Five units, 20 lessons, 4 lessons each")
    func shape() {
        #expect(MercuriusCurriculum.units.count == 5)
        #expect(MercuriusCurriculum.allLessons.count == 20)
        for unit in MercuriusCurriculum.units {
            #expect(unit.lessons.count == 4, "Unit \(unit.number) has \(unit.lessons.count) lessons")
        }
    }

    @Test("Lesson ids are unique across the whole curriculum")
    func idsUnique() {
        let ids = MercuriusCurriculum.allLessons.map(\.id)
        #expect(Set(ids).count == ids.count)
    }

    @Test("Every lesson starter includes a [CURRICULUM: …] prefix so the server routes it correctly")
    func startersTagged() {
        for lesson in MercuriusCurriculum.allLessons {
            #expect(lesson.starter.hasPrefix("[CURRICULUM:"), "Lesson \(lesson.id) starter is untagged")
        }
    }

    @Test("unit(withId:) lookup works for all units; returns nil for unknown")
    func unitLookup() {
        for unit in MercuriusCurriculum.units {
            #expect(MercuriusCurriculum.unit(withId: unit.id)?.id == unit.id)
        }
        #expect(MercuriusCurriculum.unit(withId: "unit_nope") == nil)
    }
}

@Suite("CurriculumProgressStore")
@MainActor
struct CurriculumProgressStoreTests {

    @Test("Starts with no completed lessons")
    func defaultsEmpty() {
        let store = CurriculumProgressStore(preferences: InMemoryPreferenceStore())
        #expect(store.completedIds.isEmpty)
        #expect(store.totalCompleted() == 0)
    }

    @Test("markCompleted records the lesson and counts up")
    func marksCompleted() {
        let store = CurriculumProgressStore(preferences: InMemoryPreferenceStore())
        store.markCompleted("u1_l1")
        #expect(store.isCompleted("u1_l1"))
        #expect(store.totalCompleted() == 1)
    }

    @Test("markCompleted is idempotent")
    func idempotentComplete() {
        let store = CurriculumProgressStore(preferences: InMemoryPreferenceStore())
        store.markCompleted("u1_l1")
        store.markCompleted("u1_l1")
        #expect(store.totalCompleted() == 1)
    }

    @Test("markIncomplete removes the lesson")
    func markIncomplete() {
        let store = CurriculumProgressStore(preferences: InMemoryPreferenceStore())
        store.markCompleted("u1_l1")
        store.markIncomplete("u1_l1")
        #expect(!store.isCompleted("u1_l1"))
        #expect(store.totalCompleted() == 0)
    }

    @Test("completedCount(in:) counts only that unit's lessons")
    func perUnitCount() {
        let store = CurriculumProgressStore(preferences: InMemoryPreferenceStore())
        let unit1 = MercuriusCurriculum.units[0]
        let unit2 = MercuriusCurriculum.units[1]
        store.markCompleted(unit1.lessons[0].id)
        store.markCompleted(unit1.lessons[1].id)
        store.markCompleted(unit2.lessons[0].id)
        #expect(store.completedCount(in: unit1) == 2)
        #expect(store.completedCount(in: unit2) == 1)
    }

    @Test("Progress persists across instances sharing the same preference store")
    func persistenceAcrossInstances() {
        let prefs = InMemoryPreferenceStore()
        let a = CurriculumProgressStore(preferences: prefs)
        a.markCompleted("u1_l1")
        a.markCompleted("u3_l2")

        let b = CurriculumProgressStore(preferences: prefs)
        #expect(b.isCompleted("u1_l1"))
        #expect(b.isCompleted("u3_l2"))
        #expect(b.totalCompleted() == 2)
    }

    @Test("reset() clears everything")
    func resetClears() {
        let prefs = InMemoryPreferenceStore()
        let store = CurriculumProgressStore(preferences: prefs)
        store.markCompleted("u1_l1")
        store.markCompleted("u2_l1")
        store.reset()
        #expect(store.completedIds.isEmpty)
        let restored = CurriculumProgressStore(preferences: prefs)
        #expect(restored.completedIds.isEmpty)
    }

    @Test("Corrupted stored value is treated as empty, not a crash")
    func corruptedStorageRecovers() {
        let prefs = InMemoryPreferenceStore()
        prefs.set("not json", for: "com.mayoailiteracy.mercurius.curriculumProgress")
        let store = CurriculumProgressStore(preferences: prefs)
        #expect(store.completedIds.isEmpty)
    }
}
