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

    @Test("Shape invariants: ≥5 units, each ≥4 lessons numbered 1…n; allLessons is their sum")
    func shape() {
        #expect(MercuriusCurriculum.units.count >= 5)
        let summed = MercuriusCurriculum.units.reduce(0) { $0 + $1.lessons.count }
        #expect(MercuriusCurriculum.allLessons.count == summed)
        for unit in MercuriusCurriculum.units {
            #expect(unit.lessons.count >= 4, "Unit \(unit.number) has only \(unit.lessons.count) lessons")
            #expect(unit.lessons.map(\.number) == Array(1...unit.lessons.count),
                    "Unit \(unit.number) lessons aren't numbered 1…n in order")
        }
    }

    @Test("Lesson ids are unique across the whole curriculum")
    func idsUnique() {
        let ids = MercuriusCurriculum.allLessons.map(\.id)
        #expect(Set(ids).count == ids.count)
    }

    @Test("Every lesson starter is tagged [CURRICULUM: Unit N, Lesson k …] so the server routes it correctly")
    func startersTagged() {
        for lesson in MercuriusCurriculum.allLessons {
            #expect(
                lesson.starter.range(of: #"^\[CURRICULUM: Unit \d+, Lesson \d+"#, options: .regularExpression) != nil,
                "Lesson \(lesson.id) starter is malformed: \(lesson.starter.prefix(48))"
            )
        }
    }

    @Test("unit(withId:) lookup works for all units; returns nil for unknown")
    func unitLookup() {
        for unit in MercuriusCurriculum.units {
            #expect(MercuriusCurriculum.unit(withId: unit.id)?.id == unit.id)
        }
        #expect(MercuriusCurriculum.unit(withId: "unit_nope") == nil)
    }

    @Test("Every unit has a well-formed cumulative unit test (≥5 Qs, valid answers, non-empty defense)")
    func unitTestsWellFormed() {
        for unit in MercuriusCurriculum.units {
            guard let test = MercuriusCurriculum.unitTest(for: unit.id) else {
                Issue.record("Unit \(unit.id) has no unit test")
                continue
            }
            #expect(test.unitId == unit.id)
            #expect(test.questions.count >= 5, "Unit \(unit.id) has only \(test.questions.count) questions")
            #expect(!test.defensePrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                    "Unit \(unit.id) has an empty defense prompt")
            for q in test.questions {
                // answer is a single A–D letter that indexes a real option.
                #expect(q.isWellFormed, "Question \(q.id) malformed: answer \(q.answer), \(q.options.count) options")
                #expect(q.options.count == 4, "Question \(q.id) should have 4 options")
                #expect(!q.q.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                #expect(!q.explanation.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }

    @Test("Unit-test question ids are unique within each unit")
    func unitTestQuestionIdsUnique() {
        for unit in MercuriusCurriculum.units {
            guard let test = MercuriusCurriculum.unitTest(for: unit.id) else { continue }
            let ids = test.questions.map(\.id)
            #expect(Set(ids).count == ids.count, "Duplicate question ids in \(unit.id)")
        }
    }

    @Test("unitTest(for:) returns nil for an unknown unit")
    func unitTestUnknown() {
        #expect(MercuriusCurriculum.unitTest(for: "unit_nope") == nil)
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

@Suite("CurriculumProgressStore sequential lesson gating")
@MainActor
struct CurriculumProgressStoreGatingTests {

    @Test("The first lesson of a unit is unlocked with no progress")
    func firstLessonUnlockedByDefault() {
        let store = CurriculumProgressStore(preferences: InMemoryPreferenceStore())
        let unit = MercuriusCurriculum.units[0]
        #expect(store.isLessonUnlocked(unit.lessons[0], in: unit))
    }

    @Test("The 2nd lesson is locked until the 1st is completed")
    func secondLessonLockedUntilFirstDone() {
        let store = CurriculumProgressStore(preferences: InMemoryPreferenceStore())
        let unit = MercuriusCurriculum.units[0]
        #expect(!store.isLessonUnlocked(unit.lessons[1], in: unit))
    }

    @Test("Completing the 1st lesson unlocks the 2nd")
    func completingFirstUnlocksSecond() {
        let store = CurriculumProgressStore(preferences: InMemoryPreferenceStore())
        let unit = MercuriusCurriculum.units[0]
        store.markCompleted(unit.lessons[0].id)
        #expect(store.isLessonUnlocked(unit.lessons[1], in: unit))
        // The 3rd remains locked until the 2nd is done.
        #expect(!store.isLessonUnlocked(unit.lessons[2], in: unit))
    }

    @Test("Each lesson gates only on the immediately-previous lesson in the same unit")
    func gatesOnImmediatelyPreviousOnly() {
        let store = CurriculumProgressStore(preferences: InMemoryPreferenceStore())
        let unit = MercuriusCurriculum.units[0]
        // Completing lesson 1 (but not 2) must NOT unlock lesson 3.
        store.markCompleted(unit.lessons[0].id)
        #expect(!store.isLessonUnlocked(unit.lessons[2], in: unit))
        // Completing lesson 2 then unlocks lesson 3.
        store.markCompleted(unit.lessons[1].id)
        #expect(store.isLessonUnlocked(unit.lessons[2], in: unit))
    }

    @Test("A later unit's first lesson is unlocked regardless of earlier units")
    func laterUnitFirstLessonAlwaysUnlocked() {
        let store = CurriculumProgressStore(preferences: InMemoryPreferenceStore())
        let unit2 = MercuriusCurriculum.units[1]
        // No progress anywhere — unit 2's first lesson is still unlocked,
        // because units are independent.
        #expect(store.isLessonUnlocked(unit2.lessons[0], in: unit2))
        // But its 2nd lesson is still gated on unit 2's own 1st lesson.
        #expect(!store.isLessonUnlocked(unit2.lessons[1], in: unit2))
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

    @Test("migrateInProgressKeys rewrites lesson-id KEYS but preserves conversation VALUES")
    func migratesInProgressKeys() {
        let convo = UUID().uuidString
        let result = CurriculumProgressStore.migrateInProgressKeys(
            ["old": convo, "unrelated": "x"],
            from: 1,
            to: 2,
            migrationProvider: { step in step == 1 ? ["old": "new"] : [:] }
        )
        #expect(result["new"] == convo, "Key migrated, conversation id preserved")
        #expect(result["old"] == nil)
        #expect(result["unrelated"] == "x")
    }

    @Test("migrateInProgressKeys with from == to is a no-op")
    func inProgressNoOpWhenVersionsMatch() {
        let result = CurriculumProgressStore.migrateInProgressKeys(
            ["old": "c"],
            from: 2,
            to: 2,
            migrationProvider: { _ in ["old": "new"] }
        )
        #expect(result == ["old": "c"])
    }
}

@Suite("CurriculumProgressStore in-progress + states")
@MainActor
struct CurriculumProgressStoreStateTests {

    @Test("A fresh lesson is .notStarted with no resume conversation")
    func notStartedByDefault() {
        let store = CurriculumProgressStore(preferences: InMemoryPreferenceStore())
        #expect(store.state(of: "u1_l1") == .notStarted)
        #expect(store.resumeConversationId(for: "u1_l1") == nil)
    }

    @Test("markInProgress moves a lesson to .inProgress and records its conversation — but is NOT completion")
    func marksInProgress() {
        let store = CurriculumProgressStore(preferences: InMemoryPreferenceStore())
        let convo = UUID()
        store.markInProgress("u1_l1", conversationId: convo)
        #expect(store.state(of: "u1_l1") == .inProgress)
        #expect(store.resumeConversationId(for: "u1_l1") == convo)
        #expect(!store.isCompleted("u1_l1"))
        #expect(store.totalCompleted() == 0)
    }

    @Test("markCompleted outranks in-progress but KEEPS the resume pointer for review")
    func completionKeepsResumePointer() {
        let store = CurriculumProgressStore(preferences: InMemoryPreferenceStore())
        let convo = UUID()
        store.markInProgress("u1_l1", conversationId: convo)
        store.markCompleted("u1_l1")
        #expect(store.state(of: "u1_l1") == .completed)
        // Review reopens the finished thread rather than minting a fresh
        // (orphaned) conversation record on every visit.
        #expect(store.resumeConversationId(for: "u1_l1") == convo)
    }

    @Test("markInProgress on a completed lesson records the review thread without downgrading")
    func reviewThreadRecordedWithoutDowngrade() {
        let store = CurriculumProgressStore(preferences: InMemoryPreferenceStore())
        let convo = UUID()
        store.markCompleted("u1_l1")
        store.markInProgress("u1_l1", conversationId: convo)
        #expect(store.state(of: "u1_l1") == .completed)   // completed still outranks
        #expect(store.resumeConversationId(for: "u1_l1") == convo)
    }

    @Test("In-progress state + conversation persist across instances")
    func inProgressPersists() {
        let prefs = InMemoryPreferenceStore()
        let convo = UUID()
        let a = CurriculumProgressStore(preferences: prefs)
        a.markInProgress("u1_l1", conversationId: convo)

        let b = CurriculumProgressStore(preferences: prefs)
        #expect(b.state(of: "u1_l1") == .inProgress)
        #expect(b.resumeConversationId(for: "u1_l1") == convo)
    }

    @Test("inProgressCount(in:) counts only that unit's in-progress lessons; completing one removes it")
    func perUnitInProgressCount() {
        let store = CurriculumProgressStore(preferences: InMemoryPreferenceStore())
        let unit1 = MercuriusCurriculum.units[0]
        store.markInProgress(unit1.lessons[0].id, conversationId: UUID())
        store.markInProgress(unit1.lessons[1].id, conversationId: UUID())
        store.markCompleted(unit1.lessons[1].id)
        #expect(store.inProgressCount(in: unit1) == 1)
    }

    @Test("reset() clears in-progress too")
    func resetClearsInProgress() {
        let prefs = InMemoryPreferenceStore()
        let store = CurriculumProgressStore(preferences: prefs)
        store.markInProgress("u1_l1", conversationId: UUID())
        store.reset()
        #expect(store.state(of: "u1_l1") == .notStarted)
        let restored = CurriculumProgressStore(preferences: prefs)
        #expect(restored.state(of: "u1_l1") == .notStarted)
    }

    @Test("Corrupted in-progress blob is treated as empty, not a crash")
    func corruptedInProgressRecovers() {
        let prefs = InMemoryPreferenceStore()
        prefs.set("not json", for: "com.mayoailiteracy.mercurius.curriculumProgress.inProgress")
        let store = CurriculumProgressStore(preferences: prefs)
        #expect(store.state(of: "u1_l1") == .notStarted)
    }
}

@Suite("CurriculumProgressStore unit mastery")
@MainActor
struct CurriculumProgressStoreMasteryTests {

    @Test("No units mastered by default; the test is locked until lessons are done")
    func defaults() {
        let store = CurriculumProgressStore(preferences: InMemoryPreferenceStore())
        let unit = MercuriusCurriculum.units[0]
        #expect(!store.isUnitMastered(unit.id))
        #expect(!store.isUnitTestUnlocked(unit))
        #expect(store.masteredUnits.isEmpty)
    }

    @Test("The unit test unlocks only when every lesson in the unit is complete")
    func unlockGating() {
        let store = CurriculumProgressStore(preferences: InMemoryPreferenceStore())
        let unit = MercuriusCurriculum.units[0]
        for lesson in unit.lessons.dropLast() { store.markCompleted(lesson.id) }
        #expect(!store.isUnitTestUnlocked(unit))   // 3 of 4
        store.markCompleted(unit.lessons.last!.id)
        #expect(store.isUnitTestUnlocked(unit))    // 4 of 4
    }

    @Test("markUnitMastered records the unit and is idempotent")
    func marksMastered() {
        let store = CurriculumProgressStore(preferences: InMemoryPreferenceStore())
        store.markUnitMastered("unit_1")
        store.markUnitMastered("unit_1")
        #expect(store.isUnitMastered("unit_1"))
        #expect(store.masteredUnits.count == 1)
    }

    @Test("Mastery is independent of lesson completion (the UI gates entry, not the store)")
    func independentOfCompletion() {
        let store = CurriculumProgressStore(preferences: InMemoryPreferenceStore())
        store.markUnitMastered("unit_2")
        #expect(store.isUnitMastered("unit_2"))
        #expect(store.totalCompleted() == 0)
    }

    @Test("Mastery persists across instances sharing a preference store")
    func persistsAcrossInstances() {
        let prefs = InMemoryPreferenceStore()
        let a = CurriculumProgressStore(preferences: prefs)
        a.markUnitMastered("unit_1")
        a.markUnitMastered("unit_3")

        let b = CurriculumProgressStore(preferences: prefs)
        #expect(b.isUnitMastered("unit_1"))
        #expect(b.isUnitMastered("unit_3"))
        #expect(b.masteredUnits.count == 2)
    }

    @Test("reset() clears mastery")
    func resetClearsMastery() {
        let prefs = InMemoryPreferenceStore()
        let store = CurriculumProgressStore(preferences: prefs)
        store.markUnitMastered("unit_1")
        store.reset()
        #expect(store.masteredUnits.isEmpty)
        let restored = CurriculumProgressStore(preferences: prefs)
        #expect(!restored.isUnitMastered("unit_1"))
    }

    @Test("Corrupted mastery blob is treated as empty, not a crash")
    func corruptedRecovers() {
        let prefs = InMemoryPreferenceStore()
        prefs.set("not json", for: "com.mayoailiteracy.mercurius.curriculumProgress.masteredUnits")
        let store = CurriculumProgressStore(preferences: prefs)
        #expect(store.masteredUnits.isEmpty)
    }
}
