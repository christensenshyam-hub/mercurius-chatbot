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

    @Test("Orphaned ids (not in current curriculum) are excluded from totalCompleted()")
    func orphansFilteredFromCount() {
        // Seed storage as though the user completed two current lessons
        // plus one lesson id that no longer exists.
        let prefs = InMemoryPreferenceStore()
        let seeded = ["u1_l1", "u1_l2", "u_ghost_l1"]
        let json = try! JSONEncoder().encode(seeded)
        prefs.set(String(data: json, encoding: .utf8)!, for: "com.mayoailiteracy.mercurius.curriculumProgress")
        prefs.set(String(MercuriusCurriculum.version), for: "com.mayoailiteracy.mercurius.curriculumProgress.version")

        let store = CurriculumProgressStore(preferences: prefs)

        // Orphan is preserved in storage (future app version could
        // restore the lesson and recover the user's progress).
        #expect(store.completedIds.contains("u_ghost_l1"))
        // But totalCompleted() only counts ids that match a current lesson.
        #expect(store.totalCompleted() == 2)
    }

    @Test("Saving stamps the current curriculum version")
    func saveStampsVersion() {
        let prefs = InMemoryPreferenceStore()
        let store = CurriculumProgressStore(preferences: prefs)
        store.markCompleted("u1_l1")
        let storedVersion = prefs.string(for: "com.mayoailiteracy.mercurius.curriculumProgress.version")
        #expect(storedVersion == String(MercuriusCurriculum.version))
    }

    @Test("Legacy storage without a version key still loads cleanly at current version")
    func legacyDataLoads() {
        // Pre-migration data: no version key stored. The store treats
        // missing-version as 0 and runs every migration from 0 upward,
        // but since v1 has no migrations the end state equals the start.
        let prefs = InMemoryPreferenceStore()
        let seeded = ["u1_l1"]
        let json = try! JSONEncoder().encode(seeded)
        prefs.set(String(data: json, encoding: .utf8)!, for: "com.mayoailiteracy.mercurius.curriculumProgress")
        // No version key — simulates legacy data from before this phase.

        let store = CurriculumProgressStore(preferences: prefs)

        #expect(store.completedIds == ["u1_l1"])
        // After init with migration, the version key should be written.
        #expect(prefs.string(for: "com.mayoailiteracy.mercurius.curriculumProgress.version") == String(MercuriusCurriculum.version))
    }
}

@Suite("CurriculumProgressStore migration")
@MainActor
struct CurriculumProgressStoreMigrationTests {

    @Test("applyMigrations with from == to is a no-op")
    func noOpWhenVersionsMatch() {
        let result = CurriculumProgressStore.applyMigrations(
            ids: ["u1_l1", "u1_l2"],
            from: 1,
            to: 1,
            migrationProvider: { _ in ["u1_l1": "renamed"] }
        )
        #expect(result == ["u1_l1", "u1_l2"], "No migration should run when versions are equal")
    }

    @Test("applyMigrations rewrites ids according to the map")
    func rewritesIds() {
        let result = CurriculumProgressStore.applyMigrations(
            ids: ["u1_l1", "u1_l2", "u2_l1"],
            from: 1,
            to: 2,
            migrationProvider: { step in
                step == 1 ? ["u1_l1": "u1_intro", "u1_l2": "u1_tokens"] : [:]
            }
        )
        #expect(result == ["u1_intro", "u1_tokens", "u2_l1"])
    }

    @Test("applyMigrations runs every intervening step (1 → 3 applies step 1 AND step 2)")
    func multiStepMigration() {
        let result = CurriculumProgressStore.applyMigrations(
            ids: ["a"],
            from: 0,
            to: 3,
            migrationProvider: { step in
                switch step {
                case 0: return ["a": "b"]
                case 1: return ["b": "c"]
                case 2: return ["c": "d"]
                default: return [:]
                }
            }
        )
        #expect(result == ["d"], "Every step in [from, to) should apply in order")
    }

    @Test("applyMigrations dedupes when both old and new id are present in storage")
    func dedupesAcrossMigration() {
        // User has both "old" and "new" — happens if they ran a beta
        // that introduced the new id before the renamed version shipped.
        let result = CurriculumProgressStore.applyMigrations(
            ids: ["old", "new", "unrelated"],
            from: 1,
            to: 2,
            migrationProvider: { step in step == 1 ? ["old": "new"] : [:] }
        )
        #expect(result == ["new", "unrelated"], "Duplicate-after-mapping should be collapsed")
    }

    @Test("Empty migration maps pass ids through unchanged")
    func emptyMapsPassThrough() {
        let result = CurriculumProgressStore.applyMigrations(
            ids: ["u1_l1"],
            from: 0,
            to: 5,
            migrationProvider: { _ in [:] }
        )
        #expect(result == ["u1_l1"])
    }
}
