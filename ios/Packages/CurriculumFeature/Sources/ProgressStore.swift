import Foundation
import Observation
import SettingsFeature

/// Persists the set of completed lesson ids. Backed by the same
/// `PreferenceStore` abstraction used by theme preferences, so tests
/// can inject an in-memory fake.
///
/// Storage format: a single JSON-encoded `[String]` under one key.
/// We chose a flat array because we only ever query `contains` and
/// the set never exceeds 20 entries (one per lesson).
@MainActor
@Observable
public final class CurriculumProgressStore {

    /// Ordered by insertion — newest first, for future "recently
    /// completed" UI. The public API treats it as a set.
    public private(set) var completedIds: [String] = []

    private let preferences: PreferenceStore
    private let storageKey: String

    public init(
        preferences: PreferenceStore = UserDefaultsPreferenceStore(),
        storageKey: String = "com.mayoailiteracy.mercurius.curriculumProgress"
    ) {
        self.preferences = preferences
        self.storageKey = storageKey
        self.completedIds = load()
    }

    // MARK: - Queries

    public func isCompleted(_ lessonId: String) -> Bool {
        completedIds.contains(lessonId)
    }

    public func completedCount(in unit: Unit) -> Int {
        unit.lessons.reduce(0) { $0 + (isCompleted($1.id) ? 1 : 0) }
    }

    public func totalCompleted() -> Int {
        completedIds.count
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

    private func load() -> [String] {
        guard let raw = preferences.string(for: storageKey),
              let data = raw.data(using: .utf8),
              let decoded = try? JSONDecoder().decode([String].self, from: data)
        else { return [] }
        return decoded
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(completedIds),
              let string = String(data: data, encoding: .utf8)
        else {
            preferences.set(nil, for: storageKey)
            return
        }
        preferences.set(string, for: storageKey)
    }
}
