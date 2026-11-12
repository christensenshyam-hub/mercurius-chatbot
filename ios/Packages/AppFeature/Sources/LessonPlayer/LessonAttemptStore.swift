import Foundation
import LessonPlayer
import SettingsFeature

/// The player's on-device records: one saved attempt per lesson, and the
/// one-time reward ledger. Kept in the same preferences suite as lesson
/// progress, so it follows the same rules: on this device only, private
/// under UI tests, never synced, and erased by Settings' "delete my data"
/// (`reset()`, called from `SettingsSheet`'s reset alongside `progress.reset()`).
///
/// A short response's text lives here, inside the attempt, because the
/// learner's answer must survive leaving the lesson. It is never sent
/// anywhere except to be graded, and never logged.
@MainActor
public final class LessonAttemptStore {
    static let attemptsKey = "com.mayoailiteracy.mercurius.lessonPlayer.attempts"
    static let ledgerKey = "com.mayoailiteracy.mercurius.lessonPlayer.rewardLedger"
    /// The last completed attempt per lesson, kept when a replay starts a new
    /// one (its answers and success level aren't lost).
    static let completedKey = "com.mayoailiteracy.mercurius.lessonPlayer.completedAttempts"

    private let preferences: PreferenceStore

    public init(preferences: PreferenceStore) {
        self.preferences = preferences
    }

    /// The saved attempt for a lesson, normalized after a relaunch (a
    /// response that was being graded comes back "ungraded, interrupted").
    /// Nil if there is none, or if it was written by a newer app version.
    public func attempt(for lessonId: String) -> LessonAttempt? {
        guard let raw = rawAttempts()[lessonId], let data = Data(base64Encoded: raw),
              let attempt = LessonAttemptCodec.decode(data), attempt.lessonId == lessonId
        else { return nil }
        return LessonAttemptCodec.normalizedAfterRelaunch(attempt)
    }

    /// Whether the lesson has a saved record this version can't read (written
    /// by a newer build). The app opens the legacy lesson instead, and never
    /// overwrites the record.
    public func hasUnreadableRecord(for lessonId: String) -> Bool {
        guard let raw = rawAttempts()[lessonId] else { return false }
        guard let data = Data(base64Encoded: raw) else { return true }
        return LessonAttemptCodec.decode(data) == nil
    }

    /// Save the attempt as the lesson's current one. Records for other lessons
    /// are left exactly as they are. A record this version can't read is never
    /// replaced. A completed attempt that a new attempt replaces moves to the
    /// completed-attempts history first.
    public func save(_ attempt: LessonAttempt) {
        guard !hasUnreadableRecord(for: attempt.lessonId),
              let data = try? LessonAttemptCodec.encode(attempt) else { return }
        var all = rawAttempts()
        if let raw = all[attempt.lessonId], let old = Data(base64Encoded: raw).flatMap(LessonAttemptCodec.decode),
           old.attemptId != attempt.attemptId, old.isComplete {
            var history = rawMap(Self.completedKey)
            history[attempt.lessonId] = raw
            writeMap(history, Self.completedKey)
        }
        all[attempt.lessonId] = data.base64EncodedString()
        write(all)
    }

    /// The last completed attempt replaced by a replay, if any.
    public func previousCompletedAttempt(for lessonId: String) -> LessonAttempt? {
        guard let raw = rawMap(Self.completedKey)[lessonId], let data = Data(base64Encoded: raw) else { return nil }
        return LessonAttemptCodec.decode(data)
    }

    public var ledger: RewardLedger {
        guard let raw = preferences.string(for: Self.ledgerKey), let data = raw.data(using: .utf8),
              let ledger = try? JSONDecoder().decode(RewardLedger.self, from: data)
        else { return RewardLedger() }
        return ledger
    }

    /// Grant a one-time reward key. True only the first time, ever, for this
    /// learner (until "delete my data").
    public func grantOnce(_ key: String) -> Bool {
        var ledger = self.ledger
        guard ledger.grant(key) else { return false }
        if let data = try? JSONEncoder().encode(ledger) {
            preferences.set(String(decoding: data, as: UTF8.self), for: Self.ledgerKey)
        }
        return true
    }

    /// Whether a player completion should go through the app's completion
    /// path (`handleLessonComplete`): the first time this learner completes
    /// the lesson in the player (the ledger), or whenever progress doesn't
    /// show it complete (so a completion is never lost). A replay of a lesson
    /// already completed grants nothing again.
    public func shouldRecordCompletion(lessonId: String, progressShowsCompleted: Bool) -> Bool {
        let first = grantOnce(RewardLedger.completionKey(lessonId: lessonId))
        return first || !progressShowsCompleted
    }

    /// Erase every attempt and the ledger ("delete my data", a new identity).
    public func reset() {
        preferences.set(nil, for: Self.attemptsKey)
        preferences.set(nil, for: Self.ledgerKey)
        preferences.set(nil, for: Self.completedKey)
    }

    private func rawAttempts() -> [String: String] { rawMap(Self.attemptsKey) }
    private func write(_ all: [String: String]) { writeMap(all, Self.attemptsKey) }

    private func rawMap(_ key: String) -> [String: String] {
        guard let raw = preferences.string(for: key), let data = raw.data(using: .utf8),
              let dict = try? JSONDecoder().decode([String: String].self, from: data)
        else { return [:] }
        return dict
    }

    private func writeMap(_ map: [String: String], _ key: String) {
        guard let data = try? JSONEncoder().encode(map) else { return }
        preferences.set(String(decoding: data, as: UTF8.self), for: key)
    }
}
