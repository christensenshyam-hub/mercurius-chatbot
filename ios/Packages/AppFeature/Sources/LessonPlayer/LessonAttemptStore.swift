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

    /// Save the attempt as the lesson's current one. Records for other lessons,
    /// including any this version can't read, are left exactly as they are.
    public func save(_ attempt: LessonAttempt) {
        guard let data = try? LessonAttemptCodec.encode(attempt) else { return }
        var all = rawAttempts()
        all[attempt.lessonId] = data.base64EncodedString()
        write(all)
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

    /// Erase every attempt and the ledger ("delete my data", a new identity).
    public func reset() {
        preferences.set(nil, for: Self.attemptsKey)
        preferences.set(nil, for: Self.ledgerKey)
    }

    private func rawAttempts() -> [String: String] {
        guard let raw = preferences.string(for: Self.attemptsKey), let data = raw.data(using: .utf8),
              let dict = try? JSONDecoder().decode([String: String].self, from: data)
        else { return [:] }
        return dict
    }

    private func write(_ all: [String: String]) {
        guard let data = try? JSONEncoder().encode(all) else { return }
        preferences.set(String(decoding: data, as: UTF8.self), for: Self.attemptsKey)
    }
}
