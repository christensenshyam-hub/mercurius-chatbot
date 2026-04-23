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

    private let preferences: PreferenceStore
    private let storageKey: String
    private var versionStorageKey: String { storageKey + ".version" }

    public init(
        preferences: PreferenceStore = UserDefaultsPreferenceStore(),
        storageKey: String = "com.mayoailiteracy.mercurius.curriculumProgress"
    ) {
        self.preferences = preferences
        self.storageKey = storageKey
        self.completedIds = []  // overwritten below; default keeps init simple

        let (loaded, wasMigrated) = loadAndMigrate()
        self.completedIds = loaded
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

    // MARK: - Mutations

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

    public func reset() {
        completedIds = []
        save()
    }

    // MARK: - Persistence

    /// Decode the stored ids, then run any pending migrations from the
    /// stored curriculum version up to `MercuriusCurriculum.version`.
    /// Returns `(ids, wasMigrated)` so the caller knows whether to
    /// persist the upgraded snapshot.
    private func loadAndMigrate() -> (ids: [String], wasMigrated: Bool) {
        guard let raw = preferences.string(for: storageKey),
              let data = raw.data(using: .utf8),
              let decoded = try? JSONDecoder().decode([String].self, from: data)
        else {
            return ([], false)
        }

        // Version 0 = "no version key yet" — pre-migration-support data.
        // Treated as curriculum version 0, so every migration runs.
        let savedVersion = Int(preferences.string(for: versionStorageKey) ?? "") ?? 0
        let currentVersion = MercuriusCurriculum.version

        if savedVersion >= currentVersion {
            return (decoded, false)
        }

        let migrated = Self.applyMigrations(
            ids: decoded,
            from: savedVersion,
            to: currentVersion
        )
        return (migrated, true)
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
        guard let data = try? JSONEncoder().encode(completedIds),
              let string = String(data: data, encoding: .utf8)
        else {
            preferences.set(nil, for: storageKey)
            preferences.set(nil, for: versionStorageKey)
            return
        }
        preferences.set(string, for: storageKey)
        preferences.set(String(MercuriusCurriculum.version), for: versionStorageKey)
    }
}
