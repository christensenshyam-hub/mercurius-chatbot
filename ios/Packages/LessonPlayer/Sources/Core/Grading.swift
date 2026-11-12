import Foundation

/// What a learner gave as an answer. Stored in the attempt record.
public enum LearnerResponse: Codable, Equatable, Sendable {
    /// Chosen option ids (single choice, multi-select, claim vs evidence).
    case options(Set<String>)
    /// Chosen claim ids from a passage.
    case claims(Set<String>)
    /// A short original response.
    case text(String)

    /// True when there is nothing to submit yet.
    public var isEmpty: Bool {
        switch self {
        case .options(let ids), .claims(let ids): return ids.isEmpty
        case .text(let text): return text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }
}

public enum Verdict: String, Codable, Sendable {
    case correct
    /// Multi-select only: some right, none wrong, not all.
    case partial
    case incorrect
}

/// The result of grading an objective activity on the device.
public struct ObjectiveGrade: Equatable, Sendable {
    public let verdict: Verdict
    public let feedback: String
}

public enum GradingError: Error, Equatable, Sendable {
    /// Short responses are evaluated by the server, never here.
    case notDeterministic
    /// The response's kind doesn't fit the activity (e.g. claims for a choice).
    case responseMismatch
    case empty
    /// An id the activity doesn't have.
    case unknownId(String)
    /// More than one id for a single-selection activity.
    case tooManySelected
}

/// Deterministic grading for objective activities: instant, offline, and the
/// same every time. No model call.
public enum Grader {
    public static func grade(_ activity: Activity, response: LearnerResponse) -> Result<ObjectiveGrade, GradingError> {
        switch activity.kind {
        case .shortResponse:
            return .failure(.notDeterministic)
        case .choice(let choice):
            guard case .options(let ids) = response else { return .failure(.responseMismatch) }
            let known = Set(choice.options.map(\.id))
            return gradeSet(
                ids, known: known, correct: choice.correct, selection: choice.selection,
                correctFeedback: choice.correctFeedback, partialFeedback: choice.partialFeedback,
                wrongFeedback: { id in choice.options.first { $0.id == id }?.feedback ?? "" }
            )
        case .claimSelection(let sel):
            guard case .claims(let ids) = response else { return .failure(.responseMismatch) }
            let known = Set(sel.claims.compactMap(\.claimId))
            return gradeSet(
                ids, known: known, correct: sel.correct, selection: sel.selection,
                correctFeedback: sel.correctFeedback, partialFeedback: nil,
                wrongFeedback: { id in sel.claimFeedback[id] ?? "" }
            )
        }
    }

    private static func gradeSet(
        _ chosen: Set<String>,
        known: Set<String>,
        correct: Set<String>,
        selection: ChoiceActivity.Selection,
        correctFeedback: String,
        partialFeedback: String?,
        wrongFeedback: (String) -> String
    ) -> Result<ObjectiveGrade, GradingError> {
        guard !chosen.isEmpty else { return .failure(.empty) }
        if let unknown = chosen.subtracting(known).sorted().first { return .failure(.unknownId(unknown)) }
        if selection == .single, chosen.count > 1 { return .failure(.tooManySelected) }

        if chosen == correct {
            return .success(ObjectiveGrade(verdict: .correct, feedback: correctFeedback))
        }
        // A wrong pick: name the misconception behind the first wrong choice
        // (stable order, so the same answer always gets the same feedback).
        if let wrong = chosen.subtracting(correct).sorted().first {
            return .success(ObjectiveGrade(verdict: .incorrect, feedback: wrongFeedback(wrong)))
        }
        // Only right ids, but not all of them.
        return .success(ObjectiveGrade(
            verdict: .partial,
            feedback: partialFeedback ?? "Some of your picks are right, and one is missing."
        ))
    }
}

// MARK: - Server evaluation of short responses

/// The compact result the server returns for a short response. Validated by
/// `EvaluationParser` before the player uses it; rendered with native views.
public struct ResponseEvaluation: Codable, Equatable, Sendable {
    public enum Status: String, Codable, Sendable {
        /// The rubric's core is met.
        case meets
        /// The core is not met yet; the learner revises.
        case notYet = "not_yet"
    }
    public let status: Status
    public let feedback: String
    /// At most one next hint.
    public let hint: String?
    /// Rubric flag ids the response expressed (e.g. a misconception).
    public let flags: [String]

    public init(status: Status, feedback: String, hint: String? = nil, flags: [String] = []) {
        self.status = status
        self.feedback = feedback
        self.hint = hint
        self.flags = flags
    }
}

/// Validates a raw evaluation payload. Anything off-shape is rejected rather
/// than repaired, and the player falls back to its reviewed guidance.
public enum EvaluationParser {
    public static let maxFeedbackCharacters = 400
    public static let maxHintCharacters = 240

    public static func parse(_ data: Data, allowedFlags: Set<String>) -> ResponseEvaluation? {
        guard let raw = try? JSONDecoder().decode(Raw.self, from: data) else { return nil }
        return validate(raw, allowedFlags: allowedFlags)
    }

    static func validate(_ raw: Raw, allowedFlags: Set<String>) -> ResponseEvaluation? {
        guard let status = ResponseEvaluation.Status(rawValue: raw.status) else { return nil }
        let feedback = raw.feedback.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !feedback.isEmpty, feedback.count <= maxFeedbackCharacters, !looksLikeMarkup(feedback) else { return nil }
        var hint = raw.hint?.trimmingCharacters(in: .whitespacesAndNewlines)
        if hint?.isEmpty == true { hint = nil }
        if let h = hint, h.count > maxHintCharacters || looksLikeMarkup(h) { return nil }
        // Unknown flags are dropped, not trusted: only the rubric's own flags
        // have reviewed corrections to show.
        let flags = (raw.flags ?? []).filter { allowedFlags.contains($0) }
        return ResponseEvaluation(status: status, feedback: feedback, hint: hint, flags: flags)
    }

    /// The player renders text, never generated code or HTML.
    static func looksLikeMarkup(_ text: String) -> Bool {
        let lowered = text.lowercased()
        return lowered.contains("<script") || lowered.contains("</") || lowered.contains("```")
            || lowered.range(of: #"<[a-z][a-z0-9]*[\s>/]"#, options: .regularExpression) != nil
    }

    struct Raw: Decodable {
        let status: String
        let feedback: String
        let hint: String?
        let flags: [String]?
    }
}
