import Foundation

/// The player's measurement events (docs/lesson-player-pilot/METRICS.md).
///
/// Ids, versions, step ids, interaction types, counts, statuses and times
/// only: no answer text, no option text, no chat content, ever. The host
/// adds the app version and the pseudonymous install id when it records
/// them.
public enum LessonPlayerEvent: Equatable, Sendable {
    public struct Context: Equatable, Sendable {
        /// Random per attempt; not linked to the session id.
        public let attemptId: UUID
        public let lessonId: String
        public let contentVersion: Int
        public let experience: Experience
        /// Foreground seconds in this attempt so far.
        public let activeSeconds: Int
    }

    public enum Interaction: String, Sendable {
        case singleChoice = "single_choice"
        case multiSelect = "multi_select"
        case claimSelection = "claim_selection"
        case claimVersusEvidence = "claim_vs_evidence"
        case shortResponse = "short_response"
        case teach
    }

    public enum Help: String, Sendable {
        case hint
        case askMerc = "ask_merc"
    }

    case lessonStarted(Context)
    case lessonResumed(Context)
    case stepViewed(Context, stepId: String)
    /// `attemptIndex` is 0 for the first submission on the step.
    case answerSubmitted(Context, stepId: String, attemptIndex: Int, interaction: Interaction)
    case feedbackShown(Context, stepId: String, status: GradingStatus)
    /// Why?, Show an example, or a Go deeper stage.
    case explanationExpanded(Context, stepId: String, depthId: String)
    case helpUsed(Context, stepId: String, kind: Help)
    case lessonCompleted(Context, success: SuccessLevel)
    /// An evaluation that failed (`kind` is an `UngradedReason`), or invalid content.
    case lessonError(Context, stepId: String?, kind: String)

    public var name: String {
        switch self {
        case .lessonStarted: return "lesson_start"
        case .lessonResumed: return "lesson_resumed"
        case .stepViewed: return "step_viewed"
        case .answerSubmitted: return "answer_submitted"
        case .feedbackShown: return "feedback_shown"
        case .explanationExpanded: return "explanation_expanded"
        case .helpUsed: return "help_used"
        case .lessonCompleted: return "lesson_completed"
        case .lessonError: return "lesson_error"
        }
    }

    public var context: Context {
        switch self {
        case .lessonStarted(let c), .lessonResumed(let c), .stepViewed(let c, _),
             .answerSubmitted(let c, _, _, _), .feedbackShown(let c, _, _),
             .explanationExpanded(let c, _, _), .helpUsed(let c, _, _),
             .lessonCompleted(let c, _), .lessonError(let c, _, _):
            return c
        }
    }

    /// Flat, text-free fields for a sink (values are ids, enums and numbers).
    public var fields: [String: String] {
        let c = context
        var f: [String: String] = [
            "attempt_id": c.attemptId.uuidString,
            "lesson_id": c.lessonId,
            "content_version": String(c.contentVersion),
            "experience": c.experience.rawValue,
            "active_seconds": String(c.activeSeconds),
        ]
        switch self {
        case .lessonStarted, .lessonResumed: break
        case .stepViewed(_, let step): f["step_id"] = step
        case .answerSubmitted(_, let step, let index, let interaction):
            f["step_id"] = step; f["attempt_index"] = String(index); f["interaction"] = interaction.rawValue
        case .feedbackShown(_, let step, let status):
            f["step_id"] = step; f["grading_status"] = Self.describe(status)
        case .explanationExpanded(_, let step, let depth):
            f["step_id"] = step; f["depth_id"] = depth
        case .helpUsed(_, let step, let kind):
            f["step_id"] = step; f["help"] = kind.rawValue
        case .lessonCompleted(_, let success): f["success"] = success.rawValue
        case .lessonError(_, let step, let kind):
            if let step { f["step_id"] = step }
            f["error"] = kind
        }
        return f
    }

    public static func describe(_ status: GradingStatus) -> String {
        switch status {
        case .graded(let v): return "graded_\(v.rawValue)"
        case .pending: return "pending"
        case .ungraded(let r): return "ungraded_\(r.rawValue)"
        }
    }
}
