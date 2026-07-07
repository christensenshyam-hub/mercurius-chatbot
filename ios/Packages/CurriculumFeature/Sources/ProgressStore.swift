import Foundation
import Observation
import SettingsFeature

/// Persists the set of completed lesson ids. Backed by the same
/// `PreferenceStore` abstraction used by theme preferences, so tests
/// can inject an in-memory fake.
///
/// Storage format:
/// - A JSON-encoded `[String]` under `storageKey` — the completed-id list.
/// - A plain integer string under `"<storageKey>.version"` — the
///   curriculum version at which those ids were saved.
///
/// On load, if the saved version is older than `MercuriusCurriculum.version`,
/// we run every intervening migration step from `MercuriusCurriculum.migrations(stepFrom:)`
/// against the stored ids, deduping as we go. Orphans — ids that don't
/// appear in the current curriculum and don't have a mapping — are kept
/// in storage (so a future app version can restore them) but excluded
/// from `totalCompleted()` and `completedCount(in:)` so the visible
/// progress never exceeds the number of lessons that actually exist.
@MainActor
@Observable
public final class CurriculumProgressStore {

    /// Ordered by insertion — newest first, for future "recently
    /// completed" UI. The public API treats it as a set.
    ///
    /// May contain orphaned ids carried over from an older curriculum
    /// version — `totalCompleted()` and `completedCount(in:)` filter
    /// those out at query time.
    public private(set) var completedIds: [String] = []

    /// lessonId → conversationId (UUID string) for each lesson's latest
    /// conversation. Drives the "In progress" / Resume state for started
    /// lessons — and survives completion, so reopening a completed lesson
    /// (Review) resumes the existing thread instead of minting a fresh hidden
    /// conversation record on every visit. `state(of:)` ranks completed above
    /// inProgress, so a completed lesson never *displays* as in-progress.
    public private(set) var inProgress: [String: String] = [:]

    /// Unit ids whose cumulative unit test the student has passed. Drives the
    /// "Mastered" badge. Independent of lesson completion — passing the test is
    /// an extra checkpoint on top of finishing the four lessons.
    public private(set) var masteredUnits: Set<String> = []

    private let preferences: PreferenceStore
    private let storageKey: String
    private var versionStorageKey: String { storageKey + ".version" }
    private var inProgressStorageKey: String { storageKey + ".inProgress" }
    private var masteredUnitsStorageKey: String { storageKey + ".masteredUnits" }

    public init(
        preferences: PreferenceStore = UserDefaultsPreferenceStore(),
        storageKey: String = "com.mayoailiteracy.mercurius.curriculumProgress"
    ) {
        self.preferences = preferences
        self.storageKey = storageKey

        let (loaded, loadedInProgress, loadedMastered, wasMigrated) = loadAndMigrate()
        self.completedIds = loaded
        self.inProgress = loadedInProgress
        self.masteredUnits = loadedMastered
        if wasMigrated {
            // Persist the migrated shape + current version stamp so the
            // next launch starts at the current curriculum version and
            // we don't re-run migrations.
            save()
        }
    }

    // MARK: - Queries

    public func isCompleted(_ lessonId: String) -> Bool {
        completedIds.contains(lessonId)
    }

    public func completedCount(in unit: Unit) -> Int {
        unit.lessons.reduce(0) { $0 + (isCompleted($1.id) ? 1 : 0) }
    }

    /// Total number of completed lessons that still exist in the current
    /// curriculum. Orphaned ids from older curriculum versions are not
    /// counted — the user can't see a "21 of 20" progress bar just
    /// because a lesson got removed.
    public func totalCompleted() -> Int {
        let currentIds = Set(MercuriusCurriculum.allLessons.map(\.id))
        return completedIds.filter { currentIds.contains($0) }.count
    }

    public var totalLessons: Int { MercuriusCurriculum.allLessons.count }

    /// Three-state status of a lesson. `completed` outranks `inProgress` so a
    /// lesson that was in progress and then completed shows only as completed.
    public enum LessonState: Equatable, Sendable {
        case notStarted
        case inProgress
        case completed
    }

    public func state(of lessonId: String) -> LessonState {
        if completedIds.contains(lessonId) { return .completed }
        if inProgress[lessonId] != nil { return .inProgress }
        return .notStarted
    }

    /// The conversation to resume for an in-progress lesson, if any.
    public func resumeConversationId(for lessonId: String) -> UUID? {
        inProgress[lessonId].flatMap(UUID.init(uuidString:))
    }

    public func inProgressCount(in unit: Unit) -> Int {
        unit.lessons.reduce(0) { $0 + (state(of: $1.id) == .inProgress ? 1 : 0) }
    }

    /// Sequential gating: within a unit, the first lesson is always unlocked and
    /// every later lesson stays locked until the immediately-previous lesson in
    /// the SAME unit is completed. Units are independent — unit N+1's first
    /// lesson does not depend on unit N. A lesson not found in `unit` is treated
    /// as unlocked (defensive default).
    public func isLessonUnlocked(_ lesson: Lesson, in unit: Unit) -> Bool {
        guard let idx = unit.lessons.firstIndex(where: { $0.id == lesson.id }) else { return true }
        if idx == 0 { return true }
        return isCompleted(unit.lessons[idx - 1].id)
    }

    // MARK: - Unit tests

    /// A unit's cumulative test unlocks once every lesson in it is completed.
    public func isUnitTestUnlocked(_ unit: Unit) -> Bool {
        !unit.lessons.isEmpty && completedCount(in: unit) == unit.lessons.count
    }

    public func isUnitMastered(_ unitId: String) -> Bool {
        masteredUnits.contains(unitId)
    }

    // MARK: - Mutations

    /// Mark a lesson started/in-progress, recording its conversation for resume.
    /// Completed lessons record it too (a review visit that had to start a new
    /// thread stays resumable) — they can't be downgraded because `state(of:)`
    /// ranks completed above inProgress.
    public func markInProgress(_ lessonId: String, conversationId: UUID) {
        inProgress[lessonId] = conversationId.uuidString
        save()
    }

    /// The resume pointer is deliberately KEPT on completion: Review reopens
    /// the finished conversation rather than silently restarting the lesson in
    /// a brand-new (and otherwise orphaned) conversation record on every visit.
    public func markCompleted(_ lessonId: String) {
        guard !completedIds.contains(lessonId) else { return }
        completedIds.insert(lessonId, at: 0)
        save()
    }

    public func markIncomplete(_ lessonId: String) {
        guard let index = completedIds.firstIndex(of: lessonId) else { return }
        completedIds.remove(at: index)
        save()
    }

    /// Record that the student passed a unit's cumulative test. Idempotent.
    public func markUnitMastered(_ unitId: String) {
        guard !masteredUnits.contains(unitId) else { return }
        masteredUnits.insert(unitId)
        save()
    }

    public func reset() {
        completedIds = []
        inProgress = [:]
        masteredUnits = []
        save()
    }

    // MARK: - Persistence

    /// Decode the stored ids, then run any pending migrations from the
    /// stored curriculum version up to `MercuriusCurriculum.version`.
    /// Returns `(ids, wasMigrated)` so the caller knows whether to
    /// persist the upgraded snapshot.
    private func loadAndMigrate() -> (ids: [String], inProgress: [String: String], masteredUnits: Set<String>, wasMigrated: Bool) {
        // Version 0 = "no version key yet" — pre-migration-support data.
        // Treated as curriculum version 0, so every migration runs.
        let savedVersion = Int(preferences.string(for: versionStorageKey) ?? "") ?? 0
        let currentVersion = MercuriusCurriculum.version

        let decodedIds: [String] = {
            guard let raw = preferences.string(for: storageKey),
                  let data = raw.data(using: .utf8),
                  let decoded = try? JSONDecoder().decode([String].self, from: data)
            else { return [] }
            return decoded
        }()
        let decodedInProgress: [String: String] = {
            guard let raw = preferences.string(for: inProgressStorageKey),
                  let data = raw.data(using: .utf8),
                  let decoded = try? JSONDecoder().decode([String: String].self, from: data)
            else { return [:] }
            return decoded
        }()
        // Unit ids are stable ("unit_1"…"unit_5"), so mastery never migrates —
        // just decode it. Stored as a JSON string array.
        let decodedMastered: Set<String> = {
            guard let raw = preferences.string(for: masteredUnitsStorageKey),
                  let data = raw.data(using: .utf8),
                  let decoded = try? JSONDecoder().decode([String].self, from: data)
            else { return [] }
            return Set(decoded)
        }()

        if savedVersion >= currentVersion {
            return (decodedIds, decodedInProgress, decodedMastered, false)
        }

        let migratedIds = Self.applyMigrations(ids: decodedIds, from: savedVersion, to: currentVersion)
        let migratedInProgress = Self.migrateInProgressKeys(decodedInProgress, from: savedVersion, to: currentVersion)
        return (migratedIds, migratedInProgress, decodedMastered, true)
    }

    /// Rewrite in-progress lesson-id KEYS through the same migration map as
    /// completed ids (conversation-id values are never migrated). If two old ids
    /// map to the same new id, the later one wins.
    static func migrateInProgressKeys(
        _ map: [String: String],
        from: Int,
        to: Int,
        migrationProvider: (Int) -> [String: String] = MercuriusCurriculum.migrations(stepFrom:)
    ) -> [String: String] {
        guard from < to else { return map }
        var current = map
        for step in from..<to {
            let rename = migrationProvider(step)
            if rename.isEmpty { continue }
            var next: [String: String] = [:]
            for (lessonId, convoId) in current {
                next[rename[lessonId] ?? lessonId] = convoId
            }
            current = next
        }
        return current
    }

    /// Apply every migration step from `from` up to `to`, deduping as we
    /// go so users who happened to have both the old and new id end up
    /// with just the new one.
    ///
    /// Exposed as `static internal` so the unit tests can drive it
    /// deterministically without depending on `MercuriusCurriculum.version`.
    static func applyMigrations(
        ids: [String],
        from: Int,
        to: Int,
        migrationProvider: (Int) -> [String: String] = MercuriusCurriculum.migrations(stepFrom:)
    ) -> [String] {
        guard from < to else { return ids }
        var current = ids
        for step in from..<to {
            let map = migrationProvider(step)
            if map.isEmpty { continue }
            var seen = Set<String>()
            var next: [String] = []
            next.reserveCapacity(current.count)
            for id in current {
                let mapped = map[id] ?? id
                if seen.insert(mapped).inserted {
                    next.append(mapped)
                }
            }
            current = next
        }
        return current
    }

    private func save() {
        if let data = try? JSONEncoder().encode(completedIds),
           let string = String(data: data, encoding: .utf8) {
            preferences.set(string, for: storageKey)
        } else {
            preferences.set(nil, for: storageKey)
        }
        if let data = try? JSONEncoder().encode(inProgress),
           let string = String(data: data, encoding: .utf8) {
            preferences.set(string, for: inProgressStorageKey)
        } else {
            preferences.set(nil, for: inProgressStorageKey)
        }
        // Encode as a sorted array for deterministic storage output.
        if let data = try? JSONEncoder().encode(masteredUnits.sorted()),
           let string = String(data: data, encoding: .utf8) {
            preferences.set(string, for: masteredUnitsStorageKey)
        } else {
            preferences.set(nil, for: masteredUnitsStorageKey)
        }
        preferences.set(String(MercuriusCurriculum.version), for: versionStorageKey)
    }
}
