import Testing
import Foundation
@testable import CurriculumFeature

private let t0 = Date(timeIntervalSince1970: 1_790_000_000)

@Suite("CurriculumProgressStore server merge")
@MainActor
struct CurriculumProgressMergeTests {

    @Test("merge unions remote lessons + mastery; remote-only ids append after local ones")
    func unions() {
        let store = CurriculumProgressStore(preferences: InMemoryPreferenceStore())
        store.markCompleted("u1_l2")
        store.markCompleted("u1_l1")

        let changed = store.merge(completed: ["u1_l1", "u2_l1", "u3_l1"],
                                  mastered: ["unit_1"], remoteVersion: 1)

        #expect(changed)
        #expect(store.completedIds == ["u1_l1", "u1_l2", "u2_l1", "u3_l1"])
        #expect(store.masteredUnits == ["unit_1"])
        #expect(store.totalCompleted() == 4)
    }

    @Test("Merging the same remote state twice is a no-op the second time")
    func idempotent() {
        let store = CurriculumProgressStore(preferences: InMemoryPreferenceStore())
        #expect(store.merge(completed: ["u1_l1", "u1_l1"], mastered: ["unit_2"], remoteVersion: 1))
        let revision = store.revision

        #expect(!store.merge(completed: ["u1_l1"], mastered: ["unit_2"], remoteVersion: 1))
        #expect(store.revision == revision)
        #expect(store.completedIds == ["u1_l1"])
        #expect(store.masteredUnits == ["unit_2"])
    }

    @Test("Forward-only: a remote state missing local ids never removes them")
    func neverRemoves() {
        let store = CurriculumProgressStore(preferences: InMemoryPreferenceStore())
        store.markCompleted("u1_l1")
        store.markUnitMastered("unit_1")

        #expect(!store.merge(completed: [], mastered: [], remoteVersion: 1))
        #expect(!store.merge(completed: [], mastered: [], remoteVersion: nil))
        #expect(store.isCompleted("u1_l1"))
        #expect(store.isUnitMastered("unit_1"))
    }

    @Test("Remote ids from an older curriculum version are migrated before the union")
    func migratesRemoteIds() {
        let store = CurriculumProgressStore(
            preferences: InMemoryPreferenceStore(),
            migrationProvider: { step in step == 0 ? ["legacy_a": "u1_l1", "legacy_b": "u1_l2"] : [:] }
        )
        store.markCompleted("u1_l2")

        store.merge(completed: ["legacy_a", "legacy_b"], mastered: [], remoteVersion: 0,
                    remoteUpdatedAt: ["legacy_a": t0])

        #expect(store.completedIds.sorted() == ["u1_l1", "u1_l2"])
        #expect(!store.isCompleted("legacy_a"))
        // The server's date follows the renamed id.
        #expect(store.completedAt("u1_l1") == t0)
    }

    @Test("A nil remote version is treated as 0 (every migration runs), like a legacy local install")
    func nilVersionMigrates() {
        let store = CurriculumProgressStore(
            preferences: InMemoryPreferenceStore(),
            migrationProvider: { step in step == 0 ? ["legacy_a": "u1_l1"] : [:] }
        )
        store.merge(completed: ["legacy_a"], mastered: [], remoteVersion: nil)
        #expect(store.completedIds == ["u1_l1"])
    }

    @Test("Remote ids already at the current version are not migrated again")
    func currentVersionNotMigrated() {
        let store = CurriculumProgressStore(
            preferences: InMemoryPreferenceStore(),
            migrationProvider: { _ in ["u1_l1": "renamed"] }
        )
        store.merge(completed: ["u1_l1"], mastered: [], remoteVersion: MercuriusCurriculum.version)
        #expect(store.completedIds == ["u1_l1"])
    }

    @Test("Ids from a NEWER remote curriculum are kept verbatim but not counted")
    func newerVersionIdsKeptUncounted() {
        let store = CurriculumProgressStore(
            preferences: InMemoryPreferenceStore(),
            migrationProvider: { _ in ["u1_l1": "renamed"] }
        )
        let changed = store.merge(completed: ["u1_l1", "u99_l1"], mastered: [],
                                  remoteVersion: MercuriusCurriculum.version + 1)

        #expect(changed)
        #expect(store.completedIds == ["u1_l1", "u99_l1"])
        #expect(store.totalCompleted() == 1)
        #expect(store.snapshot().completed.contains("u99_l1"), "Orphans round-trip back to the server")
    }

    @Test("merge never touches in-progress resume pointers")
    func inProgressUntouched() {
        let store = CurriculumProgressStore(preferences: InMemoryPreferenceStore())
        let convo = UUID()
        store.markInProgress("u1_l1", conversationId: convo)
        store.markInProgress("u2_l1", conversationId: UUID())
        let before = store.inProgress

        store.merge(completed: ["u1_l1"], mastered: ["unit_1"], remoteVersion: 1)

        #expect(store.inProgress == before)
        #expect(store.state(of: "u1_l1") == .completed)
        #expect(store.resumeConversationId(for: "u1_l1") == convo)
        #expect(store.state(of: "u2_l1") == .inProgress)
    }

    @Test("A merge that changes something bumps revision once; a no-op merge doesn't")
    func mergeBumpsRevision() {
        let store = CurriculumProgressStore(preferences: InMemoryPreferenceStore())
        #expect(store.revision == 0)
        store.merge(completed: ["u1_l1", "u1_l2"], mastered: ["unit_1", "unit_2"], remoteVersion: 1)
        #expect(store.revision == 1)
        store.merge(completed: ["u1_l2"], mastered: ["unit_1"], remoteVersion: 1)
        #expect(store.revision == 1)
        store.merge(completed: [], mastered: ["unit_3"], remoteVersion: 1)
        #expect(store.revision == 2)
    }

    @Test("Merged progress persists across instances")
    func persistsAcrossInstances() {
        let prefs = InMemoryPreferenceStore()
        let a = CurriculumProgressStore(preferences: prefs)
        a.markCompleted("u1_l1")
        a.merge(completed: ["u2_l1"], mastered: ["unit_1"], remoteVersion: 1,
                remoteUpdatedAt: ["u2_l1": t0])

        let b = CurriculumProgressStore(preferences: prefs)
        #expect(b.completedIds == ["u1_l1", "u2_l1"])
        #expect(b.isUnitMastered("unit_1"))
        #expect(b.completedAt("u2_l1") == t0)
    }

    @Test("snapshot() carries completion + mastery at the current version, never in-progress")
    func snapshotShape() {
        let store = CurriculumProgressStore(preferences: InMemoryPreferenceStore())
        store.markCompleted("u1_l1")
        store.markUnitMastered("unit_1")
        store.markInProgress("u1_l2", conversationId: UUID())

        #expect(store.snapshot() == CurriculumProgressStore.Snapshot(
            curriculumVersion: MercuriusCurriculum.version,
            completed: ["u1_l1"],
            mastered: ["unit_1"]
        ))
    }
}

@Suite("CurriculumProgressStore revision + last opened")
@MainActor
struct CurriculumProgressRevisionTests {

    @Test("revision moves on completion, mastery and opening a new lesson — only when state changes")
    func bumps() {
        let store = CurriculumProgressStore(preferences: InMemoryPreferenceStore())
        store.markCompleted("u1_l1")
        #expect(store.revision == 1)
        store.markCompleted("u1_l1")
        #expect(store.revision == 1)
        store.markUnitMastered("unit_1")
        #expect(store.revision == 2)
        store.markUnitMastered("unit_1")
        #expect(store.revision == 2)
        store.markOpened("u1_l2")
        #expect(store.revision == 3)
        store.markOpened("u1_l2")
        #expect(store.revision == 3)
    }

    @Test("markInProgress and reset() never bump revision")
    func quietMutations() {
        let store = CurriculumProgressStore(preferences: InMemoryPreferenceStore())
        store.markInProgress("u1_l1", conversationId: UUID())
        #expect(store.revision == 0)
        store.markCompleted("u1_l1")
        store.reset()
        #expect(store.revision == 1)
    }

    @Test("markOpened persists across instances and reset() clears it")
    func lastOpenedPersists() {
        let prefs = InMemoryPreferenceStore()
        let a = CurriculumProgressStore(preferences: prefs)
        #expect(a.lastOpenedLessonId == nil)
        a.markOpened("u3_l2")
        #expect(prefs.string(for: ProgressKeys.lastOpened) == "u3_l2")

        let b = CurriculumProgressStore(preferences: prefs)
        #expect(b.lastOpenedLessonId == "u3_l2")
        b.reset()
        #expect(b.lastOpenedLessonId == nil)
        #expect(prefs.string(for: ProgressKeys.lastOpened) == nil)
        #expect(CurriculumProgressStore(preferences: prefs).lastOpenedLessonId == nil)
    }
}

@Suite("CurriculumProgressStore completion dates")
@MainActor
struct CurriculumProgressCompletedAtTests {

    @Test("markCompleted stamps the first completion only")
    func stampedOnce() {
        let clock = TestClock(t0)
        let store = CurriculumProgressStore(preferences: InMemoryPreferenceStore(), now: { clock.now })
        store.markCompleted("u1_l1")
        clock.now = t0.addingTimeInterval(3_600)
        store.markCompleted("u1_l1")
        #expect(store.completedAt("u1_l1") == t0)
        #expect(store.completedAt("u1_l2") == nil)
    }

    @Test("Dates persist across instances as [lessonId: epoch seconds]")
    func persists() throws {
        let prefs = InMemoryPreferenceStore()
        let a = CurriculumProgressStore(preferences: prefs, now: { t0 })
        a.markCompleted("u1_l1")

        let raw = try #require(prefs.string(for: ProgressKeys.completedAt))
        let decoded = try JSONDecoder().decode([String: Double].self, from: Data(raw.utf8))
        #expect(decoded == ["u1_l1": t0.timeIntervalSince1970])
        #expect(CurriculumProgressStore(preferences: prefs).completedAt("u1_l1") == t0)
    }

    @Test("Lessons completed before dates were recorded have none (old installs keep loading)")
    func absentForLegacyIds() {
        let prefs = InMemoryPreferenceStore()
        let json = try! JSONEncoder().encode(["u1_l1", "u1_l2"])
        prefs.set(String(data: json, encoding: .utf8)!, for: ProgressKeys.base)
        prefs.set(String(MercuriusCurriculum.version), for: ProgressKeys.version)

        let store = CurriculumProgressStore(preferences: prefs)
        #expect(store.totalCompleted() == 2)
        #expect(store.completedAt("u1_l1") == nil)
        #expect(store.completions(since: .distantPast).isEmpty)
    }

    @Test("A corrupted dates blob is treated as empty, not a crash")
    func corruptedRecovers() {
        let prefs = InMemoryPreferenceStore()
        prefs.set("not json", for: ProgressKeys.completedAt)
        let store = CurriculumProgressStore(preferences: prefs)
        #expect(store.completedAt("u1_l1") == nil)
    }

    @Test("merge seeds dates from the server only for lessons it adds")
    func seededFromRemote() {
        let local = t0.addingTimeInterval(-86_400)
        let store = CurriculumProgressStore(preferences: InMemoryPreferenceStore(), now: { local })
        store.markCompleted("u1_l1")          // dated locally

        store.merge(completed: ["u1_l1", "u1_l2", "u1_l3"], mastered: [], remoteVersion: 1,
                    remoteUpdatedAt: ["u1_l1": t0, "u1_l2": t0])

        #expect(store.completedAt("u1_l1") == local, "A local date is never overwritten")
        #expect(store.completedAt("u1_l2") == t0)
        #expect(store.completedAt("u1_l3") == nil, "No server date → stays undated")
    }

    @Test("A legacy undated local lesson is not back-dated by the server")
    func legacyNotBackdated() {
        let prefs = InMemoryPreferenceStore()
        let json = try! JSONEncoder().encode(["u1_l1"])
        prefs.set(String(data: json, encoding: .utf8)!, for: ProgressKeys.base)
        prefs.set(String(MercuriusCurriculum.version), for: ProgressKeys.version)
        let store = CurriculumProgressStore(preferences: prefs)

        #expect(!store.merge(completed: ["u1_l1"], mastered: [], remoteVersion: 1,
                             remoteUpdatedAt: ["u1_l1": t0]))
        #expect(store.completedAt("u1_l1") == nil)
    }

    @Test("reset() clears dates, in memory and in storage")
    func resetClears() {
        let prefs = InMemoryPreferenceStore()
        let store = CurriculumProgressStore(preferences: prefs, now: { t0 })
        store.markCompleted("u1_l1")
        store.reset()
        #expect(store.completedAt("u1_l1") == nil)
        #expect(CurriculumProgressStore(preferences: prefs).completedAt("u1_l1") == nil)
    }

    @Test("markIncomplete drops the date so an undone lesson never counts as a completion")
    func markIncompleteClears() {
        let store = CurriculumProgressStore(preferences: InMemoryPreferenceStore(), now: { t0 })
        store.markCompleted("u1_l1")
        store.markIncomplete("u1_l1")
        #expect(store.completedAt("u1_l1") == nil)
        #expect(store.completions(since: .distantPast).isEmpty)
    }

    @Test("completions(since:) returns dated completions at/after the cutoff, newest first")
    func completionsSince() {
        let clock = TestClock(t0)
        let store = CurriculumProgressStore(preferences: InMemoryPreferenceStore(), now: { clock.now })
        store.markCompleted("u1_l1")                        // t0 (exactly the cutoff)
        clock.now = t0.addingTimeInterval(-1)
        store.markCompleted("u2_l1")                        // just before
        clock.now = t0.addingTimeInterval(600)
        store.markCompleted("u1_l2")                        // later
        store.merge(completed: ["u3_l1"], mastered: [], remoteVersion: 1)   // undated

        #expect(store.completions(since: t0) == ["u1_l2", "u1_l1"])
    }

    @Test("Loading an older version migrates date, last-opened and in-progress keys together")
    func loadMigratesKeys() throws {
        let prefs = InMemoryPreferenceStore()
        let convo = UUID().uuidString
        prefs.set(String(data: try JSONEncoder().encode(["legacy_a", "u1_l2"]), encoding: .utf8)!,
                  for: ProgressKeys.base)
        prefs.set(String(data: try JSONEncoder().encode(["legacy_a": t0.timeIntervalSince1970]),
                         encoding: .utf8)!,
                  for: ProgressKeys.completedAt)
        prefs.set(String(data: try JSONEncoder().encode(["legacy_a": convo]), encoding: .utf8)!,
                  for: ProgressKeys.inProgress)
        prefs.set("legacy_a", for: ProgressKeys.lastOpened)
        // No version key: pre-migration data, so step 0 runs.

        let store = CurriculumProgressStore(
            preferences: prefs,
            migrationProvider: { step in step == 0 ? ["legacy_a": "u1_l1"] : [:] }
        )

        #expect(store.completedIds == ["u1_l1", "u1_l2"])
        #expect(store.completedAt("u1_l1") == t0)
        #expect(store.completedAt("legacy_a") == nil)
        #expect(store.lastOpenedLessonId == "u1_l1")
        #expect(store.inProgress == ["u1_l1": convo])
        // The migrated shape is written back at the current version.
        #expect(prefs.string(for: ProgressKeys.lastOpened) == "u1_l1")
        #expect(prefs.string(for: ProgressKeys.version) == String(MercuriusCurriculum.version))
        let reloaded = CurriculumProgressStore(preferences: prefs)
        #expect(reloaded.completedAt("u1_l1") == t0)
    }

    @Test("migrateKeys resolves two old ids landing on one new id with the given rule")
    func migrateKeysCollision() {
        let result = CurriculumProgressStore.migrateKeys(
            ["old": 20.0, "new": 10.0, "other": 5.0],
            from: 1, to: 2,
            migrationProvider: { step in step == 1 ? ["old": "new"] : [:] },
            uniquingKeysWith: min
        )
        #expect(result == ["new": 10.0, "other": 5.0])
    }
}

@Suite("CurriculumProgressStore frontier")
@MainActor
struct CurriculumProgressFrontierTests {

    private var unit1: CurriculumFeature.Unit { MercuriusCurriculum.units[0] }
    private var unit2: CurriculumFeature.Unit { MercuriusCurriculum.units[1] }

    @Test("A fresh learner's frontier is the very first lesson")
    func freshStart() {
        let store = CurriculumProgressStore(preferences: InMemoryPreferenceStore())
        #expect(store.frontier() == .lesson(unit1.lessons[0]))
    }

    @Test("The frontier advances lesson by lesson within the unit")
    func advances() {
        let store = CurriculumProgressStore(preferences: InMemoryPreferenceStore())
        store.markCompleted(unit1.lessons[0].id)
        #expect(store.frontier() == .lesson(unit1.lessons[1]))
    }

    @Test("A lesson that's mid-way stays the frontier")
    func inProgressStaysFrontier() {
        let store = CurriculumProgressStore(preferences: InMemoryPreferenceStore())
        store.markInProgress(unit1.lessons[0].id, conversationId: UUID())
        #expect(store.frontier() == .lesson(unit1.lessons[0]))
    }

    @Test("With every lesson in a unit done, its unit test is the frontier until mastered")
    func unitTestThenNextUnit() {
        let store = CurriculumProgressStore(preferences: InMemoryPreferenceStore())
        for lesson in unit1.lessons { store.markCompleted(lesson.id) }
        #expect(store.frontier() == .unitTest(unit1))
        store.markUnitMastered(unit1.id)
        #expect(store.frontier() == .lesson(unit2.lessons[0]))
    }

    @Test("Mastery alone (e.g. merged from the server) doesn't skip unfinished lessons")
    func masteryDoesNotSkipLessons() {
        let store = CurriculumProgressStore(preferences: InMemoryPreferenceStore())
        store.markUnitMastered(unit1.id)
        #expect(store.frontier() == .lesson(unit1.lessons[0]))
    }

    @Test("A finished, fully mastered path has no frontier")
    func finished() {
        let store = CurriculumProgressStore(preferences: InMemoryPreferenceStore())
        for unit in MercuriusCurriculum.units {
            for lesson in unit.lessons { store.markCompleted(lesson.id) }
            store.markUnitMastered(unit.id)
        }
        #expect(store.frontier() == nil)
    }
}
