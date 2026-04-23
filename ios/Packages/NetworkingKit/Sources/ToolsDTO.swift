import Foundation

// MARK: - Quiz

/// A generated quiz returned by `POST /api/quiz`. Four multiple-choice
/// questions by default; fewer if the conversation was short.
public struct Quiz: Decodable, Sendable, Equatable {
    public let title: String
    public let questions: [QuizQuestion]

    public init(title: String, questions: [QuizQuestion]) {
        self.title = title
        self.questions = questions
    }
}

public struct QuizQuestion: Decodable, Sendable, Equatable, Identifiable {
    public let q: String
    public let options: [String]
    /// Single-letter correct answer — "A", "B", "C", or "D".
    public let answer: String
    public let explanation: String

    public var id: String { q }

    public init(q: String, options: [String], answer: String, explanation: String) {
        self.q = q
        self.options = options
        self.answer = answer
        self.explanation = explanation
    }

    /// Returns the option letter ("A", "B", "C", "D") for the given
    /// index. Guards against out-of-range by clamping.
    public static func letter(forIndex index: Int) -> String {
        let letters = ["A", "B", "C", "D"]
        return letters[max(0, min(letters.count - 1, index))]
    }
}

// MARK: - Report Card

/// Result of `POST /api/report-card` — a graded summary of the session.
public struct ReportCard: Decodable, Sendable, Equatable {
    public let overallGrade: String
    public let summary: String
    public let strengths: [String]
    public let areasToRevisit: [String]
    public let conceptsCovered: [String]
    public let criticalThinkingScore: Int
    public let curiosityScore: Int
    public let misconceptionsAddressed: [String]
    public let nextSessionSuggestion: String

    public init(
        overallGrade: String,
        summary: String,
        strengths: [String],
        areasToRevisit: [String],
        conceptsCovered: [String],
        criticalThinkingScore: Int,
        curiosityScore: Int,
        misconceptionsAddressed: [String],
        nextSessionSuggestion: String
    ) {
        self.overallGrade = overallGrade
        self.summary = summary
        self.strengths = strengths
        self.areasToRevisit = areasToRevisit
        self.conceptsCovered = conceptsCovered
        self.criticalThinkingScore = criticalThinkingScore
        self.curiosityScore = curiosityScore
        self.misconceptionsAddressed = misconceptionsAddressed
        self.nextSessionSuggestion = nextSessionSuggestion
    }
}
