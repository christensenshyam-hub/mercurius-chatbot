import Foundation
import Observation
import NetworkingKit

/// State machine for the Quiz sheet:
///
///   .loading → .ready → (.answered per question) → .finished
///           ↘ .failed(reason, retryable)
///
/// The view model is `@MainActor` + `@Observable`; all mutation happens
/// on the main thread so SwiftUI bindings observe changes cleanly.
@MainActor
@Observable
public final class QuizViewModel {

    public enum Phase: Equatable, Sendable {
        case loading
        case ready(Quiz)
        case failed(reason: String, isRetryable: Bool)
    }

    public private(set) var phase: Phase = .loading

    /// Per-question selected letter ("A"…"D"), indexed by question id.
    public private(set) var selections: [String: String] = [:]

    /// Whether the user has revealed the answer key + explanations
    /// by tapping "Submit" at the end. Once true, questions show
    /// correct / incorrect markers and explanations.
    public private(set) var isSubmitted: Bool = false

    private let tools: ToolsProviding
    private let sessionIdProvider: @Sendable () throws -> String

    public init(
        tools: ToolsProviding,
        sessionIdProvider: @escaping @Sendable () throws -> String
    ) {
        self.tools = tools
        self.sessionIdProvider = sessionIdProvider
    }

    // MARK: - Actions

    public func load() async {
        phase = .loading
        do {
            let sid = try sessionIdProvider()
            let quiz = try await tools.generateQuiz(sessionId: sid)
            // Defend against an empty or malformed quiz.
            guard !quiz.questions.isEmpty else {
                phase = .failed(
                    reason: "The conversation is too short to generate a quiz yet. Chat a bit more and try again.",
                    isRetryable: false
                )
                return
            }
            phase = .ready(quiz)
            selections = [:]
            isSubmitted = false
        } catch let error as APIError {
            phase = .failed(
                reason: error.userFacingMessage,
                isRetryable: error.isRetryable
            )
        } catch {
            phase = .failed(
                reason: "Couldn't generate a quiz. Try again.",
                isRetryable: true
            )
        }
    }

    /// Record the user's choice for a question. No-op after submit.
    public func select(_ letter: String, for questionId: String) {
        guard !isSubmitted else { return }
        selections[questionId] = letter
    }

    public func submit() {
        guard case .ready(let quiz) = phase else { return }
        guard allAnswered(quiz: quiz) else { return }
        isSubmitted = true
    }

    public func restart() {
        Task { await load() }
    }

    // MARK: - Derived state

    public func allAnswered(quiz: Quiz) -> Bool {
        quiz.questions.allSatisfy { selections[$0.id] != nil }
    }

    public func score(quiz: Quiz) -> Int {
        quiz.questions.reduce(0) { total, question in
            selections[question.id] == question.answer ? total + 1 : total
        }
    }

    public func isCorrect(question: QuizQuestion) -> Bool? {
        guard isSubmitted, let selection = selections[question.id] else { return nil }
        return selection == question.answer
    }
}
