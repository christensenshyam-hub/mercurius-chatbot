import Foundation
import Observation

/// Thrown by the injected `gradeDefense` closure when defense grading is not
/// available on the server this build is talking to (e.g. the deployed backend
/// predates the grading endpoint and returns 404). Distinguished from
/// transport failures so the student isn't told to "check your connection"
/// for an error no retry can fix.
public enum DefenseGradingError: Error, Equatable, Sendable {
    case unavailable
}

/// Drives a cumulative unit test: an objective multiple-choice quiz scored
/// on-device, then one open-ended "defense" question graded by the server
/// (injected as `gradeDefense` so this package stays network-free), then a
/// combined result. Passing = MCQ ≥ `mcqPassFraction` AND the defense graded
/// A/B.
@MainActor
@Observable
public final class UnitTestViewModel {

    public enum Phase: Equatable, Sendable {
        /// Answering (and, once submitted, reviewing) the multiple-choice quiz.
        case quiz
        /// Writing the open-ended defense answer.
        case defense
        /// Final pass/fail screen.
        case result
    }

    /// The server's grade of the defense answer, normalized into the package.
    public struct DefenseResult: Equatable, Sendable {
        public let grade: String
        public let pass: Bool
        public let feedback: String

        public init(grade: String, pass: Bool, feedback: String) {
            self.grade = grade
            self.pass = pass
            self.feedback = feedback
        }
    }

    public let unit: Unit
    public let test: UnitTest
    /// Fraction of MCQs that must be correct to pass that half. 0.8 = 80%.
    private let mcqPassFraction: Double
    private let gradeDefense: (String) async throws -> DefenseResult

    public private(set) var phase: Phase = .quiz

    // Quiz state
    /// questionId → selected option letter ("A"–"D").
    public private(set) var selections: [String: String] = [:]
    public private(set) var quizSubmitted = false

    // Defense state
    /// Bound directly by the text editor (settable so SwiftUI can write it).
    public var defenseAnswer: String = ""
    public private(set) var isGrading = false
    public private(set) var defenseResult: DefenseResult?
    public private(set) var defenseError: String?

    public init(
        unit: Unit,
        test: UnitTest,
        mcqPassFraction: Double = 0.8,
        gradeDefense: @escaping (String) async throws -> DefenseResult
    ) {
        self.unit = unit
        self.test = test
        self.mcqPassFraction = mcqPassFraction
        self.gradeDefense = gradeDefense
    }

    // MARK: - Quiz

    public var questions: [UnitTestQuestion] { test.questions }

    public func select(_ letter: String, for questionId: String) {
        guard !quizSubmitted else { return }   // locked once submitted
        selections[questionId] = letter
    }

    public func selectedLetter(for questionId: String) -> String? {
        selections[questionId]
    }

    public var allAnswered: Bool {
        test.questions.allSatisfy { selections[$0.id] != nil }
    }

    /// nil until the quiz is submitted; then whether this question was right.
    public func isCorrect(_ question: UnitTestQuestion) -> Bool? {
        guard quizSubmitted, let selected = selections[question.id] else { return nil }
        return selected.uppercased() == question.answer.uppercased()
    }

    public var mcqScore: Int {
        // Normalize case so an authored lowercase answer (e.g. "b") still scores
        // correctly and stays consistent with the view's highlight logic.
        test.questions.reduce(0) { $0 + (selections[$1.id]?.uppercased() == $1.answer.uppercased() ? 1 : 0) }
    }

    public var mcqTotal: Int { test.questions.count }

    public var mcqPassed: Bool {
        guard mcqTotal > 0 else { return false }
        return Double(mcqScore) / Double(mcqTotal) >= mcqPassFraction
    }

    /// Number of correct answers needed to pass the MCQ half (ceil of the
    /// fraction), for display — "you'll need N correct."
    public var mcqCorrectNeeded: Int {
        Int((mcqPassFraction * Double(mcqTotal)).rounded(.up))
    }

    public func submitQuiz() {
        guard !quizSubmitted, allAnswered else { return }
        quizSubmitted = true
    }

    /// After reviewing the graded quiz: if the MCQ half passed, move on to the
    /// written defense; otherwise the test is already a fail, so skip straight
    /// to the result (no point spending a grade call on a failed attempt).
    public func continueAfterQuiz() {
        guard quizSubmitted else { return }
        phase = mcqPassed ? .defense : .result
    }

    // MARK: - Defense

    public var canSubmitDefense: Bool {
        !defenseAnswer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isGrading
    }

    public func submitDefense() async {
        let answer = defenseAnswer.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !answer.isEmpty, !isGrading else { return }
        isGrading = true
        defenseError = nil
        do {
            let result = try await gradeDefense(answer)
            defenseResult = result
            isGrading = false
            phase = .result
        } catch DefenseGradingError.unavailable {
            // Honest copy: the endpoint doesn't exist on this server, so
            // blaming the student's connection would send them into a
            // retry loop that can never succeed.
            defenseError = "Grading isn't available yet. It's not your connection — please try again after the next app update."
            isGrading = false
        } catch {
            defenseError = "Couldn't grade your answer. Check your connection and try again."
            isGrading = false
        }
    }

    // MARK: - Result

    /// Overall pass requires BOTH halves: the MCQ score and the defense grade.
    public var overallPassed: Bool {
        mcqPassed && (defenseResult?.pass ?? false)
    }

    public func retake() {
        selections = [:]
        quizSubmitted = false
        defenseAnswer = ""
        defenseResult = nil
        defenseError = nil
        isGrading = false
        phase = .quiz
    }

    // MARK: - Display helpers

    /// Option letter ("A"–"D") for a zero-based index.
    public static func optionLetter(_ index: Int) -> String {
        guard index >= 0, index < 26 else { return "?" }
        return String(UnicodeScalar(65 + index)!)
    }
}
