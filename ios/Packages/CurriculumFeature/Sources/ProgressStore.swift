import Foundation
import Observation
import SettingsFeature

/// Persists the set of completed lesson ids. Backed by the same
/// `PreferenceStore` abstraction used by theme preferences, so tests
/// can inject an in-memory fake.
///
/// Storage format (all strings in the `PreferenceStore`):
/// - `storageKey` — JSON `[String]`, the completed-id list.
/// - `"<storageKey>.version"` — the curriculum version those ids were saved at.
/// - `"<storageKey>.inProgress"` — JSON `[String: String]`, lessonId → conversation UUID.
/// - `"<storageKey>.masteredUnits"` — JSON `[String]`, sorted unit ids.
/// - `"<storageKey>.completedAt"` — JSON `[String: Double]`, lessonId → epoch
///   seconds of the first completion. Absent on installs from before 2.3.0, so
///   lessons finished back then have no date.
/// - `"<storageKey>.lastOpened"` — the lesson id most recently opened.
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

    /// What the server keeps for this learner: completion and mastery only.
    /// In-progress conversations are device-local and never sync.
    public struct Snapshot: Equatable, Sendable {
        public let curriculumVersion: Int
        public let completed: Set<String>
        public let mastered: Set<String>

        public init(curriculumVersion: Int, completed: Set<String>, mastered: Set<String>) {
            self.curriculumVersion = curriculumVersion
            self.completed = completed
            self.mastered = mastered
        }
    }

    /// Ordered by insertion — newest first for local completions; ids first
    /// seen in a server merge are appended at the end. The public API treats
    /// it as a set.
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
    /// an extra checkpoint on top of finishing the unit's lessons.
    public private(set) var masteredUnits: Set<String> = []

    /// Bumped whenever completion, mastery, or the last-opened lesson changes
    /// (`markCompleted`, `markUnitMastered`, a `merge` that added something,
    /// `markOpened`). Not bumped by `markInProgress` or `reset()`, so a host
    /// that pushes on change never uploads an in-progress blip or a wiped
    /// snapshot. In-memory only; starts at 0 for every instance.
    public private(set) var revision: Int = 0

    /// The lesson the student most recently opened, for "pick up where you
    /// left off".
    public private(set) var lastOpenedLessonId: String?

    /// lessonId → epoch seconds of its first completion.
    private var completedAtSeconds: [String: Double] = [:]

    private let preferences: PreferenceStore
    private let storageKey: String
    private let now: () -> Date
    private let migrationProvider: (Int) -> [String: String]
    private var versionStorageKey: String { storageKey + ".version" }
    private var inProgressStorageKey: String { storageKey + ".inProgress" }
    private var masteredUnitsStorageKey: String { storageKey + ".masteredUnits" }
    private var completedAtStorageKey: String { storageKey + ".completedAt" }
    private var lastOpenedStorageKey: String { storageKey + ".lastOpened" }

    public convenience init(
        preferences: PreferenceStore = UserDefaultsPreferenceStore(),
        storageKey: String = "com.mayoailiteracy.mercurius.curriculumProgress",
        now: @escaping () -> Date = Date.init
    ) {
        self.init(
            preferences: preferences,
            storageKey: storageKey,
            now: now,
            migrationProvider: MercuriusCurriculum.migrations(stepFrom:)
        )
    }

    /// Tests inject `migrationProvider` to drive load and merge migrations
    /// without bumping `MercuriusCurriculum.version`.
    init(
        preferences: PreferenceStore,
        storageKey: String = "com.mayoailiteracy.mercurius.curriculumProgress",
        now: @escaping () -> Date = Date.init,
        migrationProvider: @escaping (Int) -> [String: String]
    ) {
        self.preferences = preferences
        self.storageKey = storageKey
        self.now = now
        self.migrationProvider = migrationProvider

        let loaded = loadAndMigrate()
        self.completedIds = loaded.ids
        self.inProgress = loaded.inProgress
        self.masteredUnits = loaded.masteredUnits
        self.completedAtSeconds = loaded.completedAt
        self.lastOpenedLessonId = loaded.lastOpened
        if loaded.wasMigrated {
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

    /// The first actionable stop in path order — the learner's frontier.
    /// Within each unit (in order), the first unlocked lesson that isn't
    /// completed; once all of a unit's lessons are done, its test until it is
    /// mastered. Nil when the whole path is finished.
    public func frontier() -> MercuriusCurriculum.PathStop? {
        for unit in MercuriusCurriculum.units {
            for lesson in unit.lessons where !isCompleted(lesson.id) && isLessonUnlocked(lesson, in: unit) {
                return .lesson(lesson)
            }
            if !isUnitMastered(unit.id), isUnitTestUnlocked(unit) {
                return .unitTest(unit)
            }
        }
        return nil
    }

    // MARK: - Completion dates

    /// When the lesson was first completed, if known. Nil for lessons
    /// completed before this was recorded, and for server-merged lessons the
    /// server had no date for.
    public func completedAt(_ lessonId: String) -> Date? {
        completedAtSeconds[lessonId].map(Date.init(timeIntervalSince1970:))
    }

    /// Completed lesson ids first completed at or after `since`, newest first.
    /// Lessons without a recorded date are never included.
    public func completions(since: Date) -> [String] {
        let threshold = since.timeIntervalSince1970
        return completedAtSeconds
            .filter { $0.value >= threshold && completedIds.contains($0.key) }
            .sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }
            .map(\.key)
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
        completedAtSeconds[lessonId] = now().timeIntervalSince1970
        revision += 1
        save()
    }

    /// Local-only undo. Server progress is forward-only, so the next merge
    /// restores a lesson that was already synced.
    public func markIncomplete(_ lessonId: String) {
        guard let index = completedIds.firstIndex(of: lessonId) else { return }
        completedIds.remove(at: index)
        completedAtSeconds[lessonId] = nil
        save()
    }

    /// Record that the student passed a unit's cumulative test. Idempotent.
    public func markUnitMastered(_ unitId: String) {
        guard !masteredUnits.contains(unitId) else { return }
        masteredUnits.insert(unitId)
        revision += 1
        save()
    }

    /// Record the lesson the student just opened.
    public func markOpened(_ lessonId: String) {
        guard lastOpenedLessonId != lessonId else { return }
        lastOpenedLessonId = lessonId
        revision += 1
        save()
    }

    /// Wipes everything. Deliberately leaves `revision` alone (see its doc).
    public func reset() {
        completedIds = []
        inProgress = [:]
        masteredUnits = []
        completedAtSeconds = [:]
        lastOpenedLessonId = nil
        save()
    }

    // MARK: - Server sync

    public func snapshot() -> Snapshot {
        Snapshot(
            curriculumVersion: MercuriusCurriculum.version,
            completed: Set(completedIds),
            mastered: masteredUnits
        )
    }

    /// Fold server progress into the local store. Forward-only: ids are only
    /// ever added, never removed, and in-progress state is untouched.
    ///
    /// Remote lesson ids (and `remoteUpdatedAt` keys) are first migrated from
    /// `remoteVersion` (nil = 0, like a legacy local install) to the current
    /// curriculum version. Ids from a NEWER curriculum are kept verbatim as
    /// orphans — uncounted today, restored by the app version that knows them.
    /// `remoteUpdatedAt` seeds the completion date only for lessons this merge
    /// adds; a local date is never overwritten.
    ///
    /// Returns whether anything changed; saves (and bumps `revision`) once.
    @discardableResult
    public func merge(
        completed remoteCompleted: [String],
        mastered remoteMastered: [String],
        remoteVersion: Int?,
        remoteUpdatedAt: [String: Date] = [:]
    ) -> Bool {
        let from = remoteVersion ?? 0
        let to = MercuriusCurriculum.version
        let ids = Self.applyMigrations(ids: remoteCompleted, from: from, to: to,
                                       migrationProvider: migrationProvider)
        let dates = Self.migrateKeys(remoteUpdatedAt, from: from, to: to,
                                     migrationProvider: migrationProvider,
                                     uniquingKeysWith: min)

        var changed = false
        var known = Set(completedIds)
        for id in ids where known.insert(id).inserted {
            // Appended, not prepended: server-only ids have no local order and
            // must not jump ahead of this device's recent completions.
            completedIds.append(id)
            if let date = dates[id] {
                completedAtSeconds[id] = date.timeIntervalSince1970
            }
            changed = true
        }
        let newlyMastered = Set(remoteMastered).subtracting(masteredUnits)
        if !newlyMastered.isEmpty {
            masteredUnits.formUnion(newlyMastered)
            changed = true
        }

        guard changed else { return false }
        revision += 1
        save()
        return true
    }

    // MARK: - Persistence

    private struct Loaded {
        var ids: [String]
        var inProgress: [String: String]
        var masteredUnits: Set<String>
        var completedAt: [String: Double]
        var lastOpened: String?
        var wasMigrated: Bool
    }

    /// Decode the stored state, then run any pending migrations from the
    /// stored curriculum version up to `MercuriusCurriculum.version`.
    /// `wasMigrated` tells the caller to persist the upgraded snapshot.
    private func loadAndMigrate() -> Loaded {
        // Version 0 = "no version key yet" — pre-migration-support data.
        // Treated as curriculum version 0, so every migration runs.
        let savedVersion = Int(preferences.string(for: versionStorageKey) ?? "") ?? 0
        let currentVersion = MercuriusCurriculum.version

        let decodedIds = decode([String].self, at: storageKey) ?? []
        let decodedInProgress = decode([String: String].self, at: inProgressStorageKey) ?? [:]
        // Unit ids are stable ("unit_1"…"unit_8"), so mastery never migrates —
        // just decode it. Stored as a JSON string array.
        let decodedMastered = Set(decode([String].self, at: masteredUnitsStorageKey) ?? [])
        let decodedCompletedAt = decode([String: Double].self, at: completedAtStorageKey) ?? [:]
        let decodedLastOpened = preferences.string(for: lastOpenedStorageKey)

        if savedVersion >= currentVersion {
            return Loaded(ids: decodedIds, inProgress: decodedInProgress,
                          masteredUnits: decodedMastered, completedAt: decodedCompletedAt,
                          lastOpened: decodedLastOpened, wasMigrated: false)
        }

        return Loaded(
            ids: Self.applyMigrations(ids: decodedIds, from: savedVersion, to: currentVersion,
                                      migrationProvider: migrationProvider),
            inProgress: Self.migrateInProgressKeys(decodedInProgress, from: savedVersion,
                                                   to: currentVersion,
                                                   migrationProvider: migrationProvider),
            masteredUnits: decodedMastered,
            completedAt: Self.migrateKeys(decodedCompletedAt, from: savedVersion, to: currentVersion,
                                          migrationProvider: migrationProvider,
                                          uniquingKeysWith: min),
            lastOpened: decodedLastOpened.flatMap {
                Self.applyMigrations(ids: [$0], from: savedVersion, to: currentVersion,
                                     migrationProvider: migrationProvider).first
            },
            wasMigrated: true
        )
    }

    private func decode<T: Decodable>(_ type: T.Type, at key: String) -> T? {
        guard let raw = preferences.string(for: key),
              let data = raw.data(using: .utf8)
        else { return nil }
        return try? JSONDecoder().decode(type, from: data)
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
        migrateKeys(map, from: from, to: to, migrationProvider: migrationProvider) { _, later in later }
    }

    /// Rewrite lesson-id KEYS of any per-lesson map through every migration
    /// step in `[from, to)`. Values are never migrated; `combine` resolves two
    /// old ids that map to the same new id.
    static func migrateKeys<Value>(
        _ map: [String: Value],
        from: Int,
        to: Int,
        migrationProvider: (Int) -> [String: String] = MercuriusCurriculum.migrations(stepFrom:),
        uniquingKeysWith combine: (Value, Value) -> Value
    ) -> [String: Value] {
        guard from < to else { return map }
        var current = map
        for step in from..<to {
            let rename = migrationProvider(step)
            if rename.isEmpty { continue }
            current = Dictionary(
                current.map { (rename[$0.key] ?? $0.key, $0.value) },
                uniquingKeysWith: combine
            )
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
        store(completedIds, at: storageKey)
        store(inProgress, at: inProgressStorageKey)
        // Encode as a sorted array for deterministic storage output.
        store(masteredUnits.sorted(), at: masteredUnitsStorageKey)
        store(completedAtSeconds, at: completedAtStorageKey)
        preferences.set(lastOpenedLessonId, for: lastOpenedStorageKey)
        preferences.set(String(MercuriusCurriculum.version), for: versionStorageKey)
    }

    private func store<T: Encodable>(_ value: T, at key: String) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        if let data = try? encoder.encode(value),
           let string = String(data: data, encoding: .utf8) {
            preferences.set(string, for: key)
        } else {
            preferences.set(nil, for: key)
        }
    }
}
