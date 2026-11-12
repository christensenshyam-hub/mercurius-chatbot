import Foundation

/// The lessons the player can run, at every content version still bundled.
/// An attempt resolves its own version here, never "the latest".
public struct LessonLibrary: Sendable {
    public let lessons: [LessonContent]

    public init(_ lessons: [LessonContent]) { self.lessons = lessons }

    public func content(lessonId: String, version: Int) -> LessonContent? {
        lessons.first { $0.lessonId == lessonId && $0.contentVersion == version }
    }

    /// The newest valid version, for starting a new attempt.
    public func latest(lessonId: String) -> LessonContent? {
        lessons.filter { $0.lessonId == lessonId && Self.isUsable($0) }
            .max { $0.contentVersion < $1.contentVersion }
    }

    public var lessonIds: Set<String> { Set(lessons.map(\.lessonId)) }

    /// Content with a validation error never runs; the lesson stays legacy.
    public static func isUsable(_ lesson: LessonContent) -> Bool {
        !LessonValidator.validate(lesson).contains { $0.severity == .error }
    }
}

/// What the host knows about a lesson when the learner opens it.
public struct ExperienceInputs: Equatable, Sendable {
    /// The player flag, as it is right now.
    public var playerEnabled: Bool
    /// The learner's saved player attempt for this lesson, if any.
    public var playerAttempt: LessonAttempt?
    /// A legacy chat thread exists for this lesson (in progress, or kept for
    /// review after completion): `CurriculumProgressStore`'s resume pointer.
    public var hasLegacyConversation: Bool
    /// The lesson is already completed (in either experience).
    public var lessonCompleted: Bool

    public init(playerEnabled: Bool, playerAttempt: LessonAttempt?, hasLegacyConversation: Bool, lessonCompleted: Bool) {
        self.playerEnabled = playerEnabled
        self.playerAttempt = playerAttempt
        self.hasLegacyConversation = hasLegacyConversation
        self.lessonCompleted = lessonCompleted
    }
}

public enum ExperienceDecision: Equatable, Sendable {
    /// Open the existing chat lesson (and its saved thread, if any).
    case legacy
    /// Resume this saved attempt on its pinned content version.
    case resumePlayer(LessonAttempt)
    /// Start a new player attempt on this content version.
    case startPlayer(contentVersion: Int)
}

/// Decides which experience a lesson opens in. The rules, in order:
///
/// 1. An unfinished player attempt resumes in the player, on its own content
///    version, whatever the flag says now (a flag change never swaps a lesson
///    mid-attempt). If its version is no longer bundled, it can't be resumed
///    safely; the lesson falls through to the rules below.
/// 2. A lesson with a legacy chat thread stays legacy: the learner's
///    transcript and its resume point are theirs, and the player doesn't hide
///    them. (Completed legacy progress is never touched.)
/// 3. With the flag on and valid player content, a new attempt starts in the
///    player. This includes replaying a lesson completed earlier in the
///    player: its completion and rewards are already recorded, and the reward
///    ledger stops them being granted twice.
/// 4. Otherwise, legacy: with the flag off, lessons behave as they do today.
public enum ExperienceResolver {
    public static func decide(lessonId: String, inputs: ExperienceInputs, library: LessonLibrary) -> ExperienceDecision {
        if let attempt = inputs.playerAttempt, attempt.lessonId == lessonId, !attempt.isComplete,
           library.content(lessonId: lessonId, version: attempt.contentVersion).map(LessonLibrary.isUsable) == true {
            return .resumePlayer(attempt)
        }
        if inputs.hasLegacyConversation { return .legacy }
        if inputs.playerEnabled, let latest = library.latest(lessonId: lessonId) {
            return .startPlayer(contentVersion: latest.contentVersion)
        }
        return .legacy
    }
}

/// One-time rewards, keyed by lesson (not attempt), so replaying a lesson in
/// the player can never grant them twice. The host persists `granted`.
public struct RewardLedger: Codable, Equatable, Sendable {
    public private(set) var granted: Set<String>

    public init(granted: Set<String> = []) { self.granted = granted }

    public static func completionKey(lessonId: String) -> String { "lesson.complete.\(lessonId)" }

    /// True exactly once per key.
    public mutating func grant(_ key: String) -> Bool { granted.insert(key).inserted }

    public func hasGranted(_ key: String) -> Bool { granted.contains(key) }
}
