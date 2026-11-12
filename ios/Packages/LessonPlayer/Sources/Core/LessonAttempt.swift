import Foundation

/// Which lesson experience an attempt uses. The flag decides this for a NEW
/// attempt only; an attempt keeps its experience for its whole life.
public enum Experience: String, Codable, Sendable {
    /// The existing model-taught chat lesson.
    case legacy
    /// The interactive lesson player.
    case player
}

/// Why a short response has no grade (yet). Never treated as correct.
public enum UngradedReason: String, Codable, Sendable {
    case offline
    case timeout
    /// The server answered, but not with a valid evaluation.
    case invalidResult
    /// The server refused (budget, kill switch, quota) or failed.
    case unavailable
    /// The learner cancelled, or the app was closed while it was being graded.
    case interrupted
    /// The answer read as a crisis: the player shows support, never a grade.
    case support
}

public enum GradingStatus: Codable, Equatable, Sendable {
    case graded(Verdict)
    /// Sent to the server; no result yet.
    case pending
    case ungraded(UngradedReason)

    public var verdict: Verdict? {
        if case .graded(let v) = self { return v }
        return nil
    }
}

/// One submitted answer and what came of it.
public struct Submission: Codable, Equatable, Sendable {
    public let index: Int
    public let response: LearnerResponse
    public var status: GradingStatus
    public var feedback: String?
    public var hint: String?
    public var flags: [String]
    public let submittedAt: Date
    /// Hints the learner had seen when they submitted (independent vs assisted).
    public let hintsSeen: Int
    /// Matches the evaluation request in flight, so a late or stale result
    /// for an earlier request is ignored.
    public var evaluationToken: Int
}

public enum StepPhase: String, Codable, Sendable {
    /// Reading, choosing or writing.
    case viewing
    /// A short response is with the server.
    case awaitingGrade
    /// The result is on screen.
    case feedback
    case done
}

/// Everything about one step in one attempt.
public struct StepRecord: Codable, Equatable, Sendable {
    public var draft: LearnerResponse?
    public var submissions: [Submission] = []
    public var hintsShown = 0
    /// Objective: the right answer was shown after repeated misses.
    /// Short response: the exemplar was shown after repeated "not yet".
    public var revealed = false
    public var depthOpened: Set<String> = []
    public var phase: StepPhase = .viewing

    public init() {}

    public var lastSubmission: Submission? { submissions.last }
}

/// How well the lesson's objective was demonstrated. Kept apart from
/// completion: a Basics lesson can complete with a wrong check
/// (`notDemonstrated`), and no lesson ever grants unit mastery (that's the
/// unit check's, unchanged).
public enum SuccessLevel: String, Codable, Sendable {
    /// Every graded activity right on the first try, with no hints or reveals.
    case independent
    /// Succeeded, with retries, hints or a reveal.
    case assisted
    /// Completed, but a graded activity ended wrong (allowed only where the
    /// lesson's completion rule says an answer is enough).
    case notDemonstrated
}

public struct CompletionRecord: Codable, Equatable, Sendable {
    public let completedAt: Date
    public let success: SuccessLevel
}

/// One run through one lesson at one content version: a single serializable
/// value, saved after every change.
public struct LessonAttempt: Codable, Equatable, Sendable {
    /// Bump when this record's shape changes; `LessonAttemptCodec` decides
    /// what an older record becomes.
    public static let currentRecordVersion = 1

    public var recordVersion: Int
    public let attemptId: UUID
    public let lessonId: String
    /// Pinned at start: a content update or a flag change never swaps it.
    public let contentVersion: Int
    public let schemaVersion: Int
    public let experience: Experience
    public var currentStepId: String
    public var records: [String: StepRecord]
    public let startedAt: Date
    public var lastActiveAt: Date
    /// Foreground time on the lesson, in seconds.
    public var activeSeconds: Double
    public var completion: CompletionRecord?
    /// How many times this attempt was resumed after leaving it.
    public var resumeCount: Int

    public init(lesson: LessonContent, attemptId: UUID = UUID(), now: Date) {
        recordVersion = LessonAttempt.currentRecordVersion
        self.attemptId = attemptId
        lessonId = lesson.lessonId
        contentVersion = lesson.contentVersion
        schemaVersion = lesson.schemaVersion
        experience = .player
        currentStepId = lesson.steps.first?.id ?? ""
        records = [:]
        startedAt = now
        lastActiveAt = now
        activeSeconds = 0
        completion = nil
        resumeCount = 0
    }

    public var isComplete: Bool { completion != nil }

    public func record(_ stepId: String) -> StepRecord { records[stepId] ?? StepRecord() }
}

/// Encodes and decodes attempt records, and normalizes a record loaded after
/// the app was closed.
public enum LessonAttemptCodec {
    public static func encode(_ attempt: LessonAttempt) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(attempt)
    }

    /// Nil for unreadable data or a record from a newer app version (left
    /// untouched by the caller, never overwritten with a guess).
    public static func decode(_ data: Data) -> LessonAttempt? {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        guard let attempt = try? decoder.decode(LessonAttempt.self, from: data) else { return nil }
        guard attempt.recordVersion <= LessonAttempt.currentRecordVersion else { return nil }
        return attempt
    }

    /// After a relaunch, nothing is in flight: a response that was being graded
    /// becomes "ungraded (interrupted)" with the learner's answer kept, so the
    /// player offers Retry instead of waiting forever.
    public static func normalizedAfterRelaunch(_ attempt: LessonAttempt) -> LessonAttempt {
        var copy = attempt
        for (id, var record) in copy.records where record.phase == .awaitingGrade {
            if var last = record.submissions.last, last.status == .pending {
                last.status = .ungraded(.interrupted)
                record.submissions[record.submissions.count - 1] = last
            }
            record.phase = .feedback
            copy.records[id] = record
        }
        return copy
    }
}
