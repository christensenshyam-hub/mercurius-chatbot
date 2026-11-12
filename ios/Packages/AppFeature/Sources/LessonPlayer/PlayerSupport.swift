import SwiftUI
import DesignSystem
import LessonPlayer
import ChatFeature
import NetworkingKit

/// A lesson opened in the player: its id and the model running its attempt.
struct PlayerLaunch {
    let lessonId: String
    let model: LessonPlayerModel
}

/// "Ask Merc" from the lesson player: the app's live tutor (the free chat, in
/// whatever mode it's in, unchanged) in a sheet. Closing it returns the
/// learner to exactly where they were in the lesson.
struct AskMercSheet<Content: View>: View {
    let onClose: () -> Void
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Ask Merc")
                    .font(BrandFont.subheading)
                    .foregroundStyle(BrandColor.text)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                Button("Back to the lesson", action: onClose)
                    .font(BrandFont.bodyEmphasized)
                    .foregroundStyle(BrandColor.accentText)
                    .frame(minHeight: 44)
                    .accessibilityIdentifier("player.askMerc.close")
            }
            .padding(.horizontal, BrandSpacing.lg)
            .padding(.vertical, BrandSpacing.sm)
            content()
        }
        .background(BrandColor.background.ignoresSafeArea())
        .presentationDragIndicator(.visible)
    }
}

/// Short-response evaluation through the server relay
/// (`POST /api/lesson-player/evaluate`, which holds the rubric, gates the call
/// through the kill switch, spend cap and quotas, and validates the result).
/// Every failure becomes an honest "not graded yet" with a reason; the player
/// re-validates any result before showing it.
enum LessonPlayerEvaluation {
    @MainActor
    static func evaluate(_ request: EvaluationRequest, apiClient: APIClient,
                         sessionIdentity: SessionIdentity) async -> EvaluationOutcome {
        if let stub = stubbedOutcome(arguments: AppEnvironment.testHookArguments(ProcessInfo.processInfo.arguments)) {
            try? await Task.sleep(for: .milliseconds(400))
            return stub
        }
        guard let sessionId = try? sessionIdentity.current() else { return .failed(.unavailable) }
        do {
            let check = try await apiClient.checkLessonResponse(
                sessionId: sessionId, lessonId: request.lessonId, contentVersion: request.contentVersion,
                stepId: request.stepId, rubricId: request.rubricId, answer: request.text
            )
            return outcome(for: check)
        } catch is CancellationError {
            return .failed(.interrupted)
        } catch let error as APIError {
            return .failed(reason(for: error))
        } catch {
            return .failed(.unavailable)
        }
    }

    static func outcome(for check: LessonResponseCheck) -> EvaluationOutcome {
        switch check {
        case .crisis:
            return .failed(.support)
        case .evaluated(let status, let feedback, let hint, let flags):
            guard let s = ResponseEvaluation.Status(rawValue: status) else { return .failed(.invalidResult) }
            return .evaluated(ResponseEvaluation(status: s, feedback: feedback, hint: hint, flags: flags))
        }
    }

    /// Why a check failed, in the player's terms. Nothing here is ever a grade.
    static func reason(for error: APIError) -> UngradedReason {
        switch error {
        case .offline, .connectionLost, .unreachableOnThisNetwork: return .offline
        case .timeout, .server(status: 504): return .timeout
        case .cancelled: return .interrupted
        case .invalidModelOutput, .decoding, .unknown(underlying: "HTTP 422"): return .invalidResult
        case .crisisSupport: return .support
        default: return .unavailable
        }
    }

    /// DEBUG builds (UI tests, screenshots): `-LessonPlayerStubGrade meets |
    /// not_yet | offline | timeout | invalid` answers every evaluation without
    /// the network. Release builds never read it (`testHookArguments`).
    static func stubbedOutcome(arguments: [String]) -> EvaluationOutcome? {
        guard let i = arguments.firstIndex(of: "-LessonPlayerStubGrade"), i + 1 < arguments.count else { return nil }
        switch arguments[i + 1] {
        case "meets":
            return .evaluated(ResponseEvaluation(status: .meets, feedback: "That’s the move: you held off on the 22% and went looking for evidence you can check. (Stubbed grade.)"))
        case "not_yet":
            return .evaluated(ResponseEvaluation(status: .notYet, feedback: "Say what you’d do before trusting the number. (Stubbed grade.)", hint: "Where could real evidence come from?"))
        case "offline": return .failed(.offline)
        case "timeout": return .failed(.timeout)
        case "invalid": return .failed(.invalidResult)
        default: return nil
        }
    }
}

/// The practice step's message (Basics 1.1: "send your first message to a
/// chatbot"): sent through the app's existing live tutor, a fresh
/// `ChatViewModel` on a new conversation, so it is the learner's real first
/// chat, saved in History like any other, in the chat's own mode. No new
/// mode, no prompt change. The reply comes back as plain text.
enum LessonPlayerPractice {
    @MainActor
    static func send(_ request: PracticeRequest, makeModel: () -> ChatViewModel) async -> PracticeOutcome {
        if let stub = stubbedOutcome(arguments: AppEnvironment.testHookArguments(ProcessInfo.processInfo.arguments)) {
            try? await Task.sleep(for: .milliseconds(400))
            return stub
        }
        let model = makeModel()
        model.startNewConversation()
        model.draft = request.text
        model.send()
        while !Task.isCancelled {
            switch model.phase {
            case .idle:
                if let reply = model.messages.last(where: { $0.role == .assistant })?.content,
                   !reply.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    return .replied(plainText(reply))
                }
                return .failed(.invalidResult)
            case .failed:
                return .failed(.unavailable)
            case .sending, .streaming:
                try? await Task.sleep(for: .milliseconds(150))
            }
        }
        return .failed(.interrupted)
    }

    /// The reply without the chat's card markers or Markdown, for the player's
    /// plain-text panel.
    static func plainText(_ reply: String) -> String {
        let lines = reply.split(separator: "\n", omittingEmptySubsequences: false)
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("ANS:") }
            .joined(separator: "\n")
        let unmarked = lines.replacingOccurrences(of: #"\[/?[A-Z_]+(:[^\]]*)?\]"#, with: "", options: .regularExpression)
        let parsed = (try? AttributedString(markdown: unmarked,
                                            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
        let text = parsed.map { String($0.characters) } ?? unmarked
        return text.replacingOccurrences(of: #"\n{3,}"#, with: "\n\n", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// DEBUG (UI tests, screenshots): the same `-LessonPlayerStubGrade`
    /// argument answers practice messages without the network.
    static func stubbedOutcome(arguments: [String]) -> PracticeOutcome? {
        guard let i = arguments.firstIndex(of: "-LessonPlayerStubGrade"), i + 1 < arguments.count else { return nil }
        switch arguments[i + 1] {
        case "offline": return .failed(.offline)
        case "timeout": return .failed(.timeout)
        case "invalid": return .failed(.invalidResult)
        default: return .replied("No, I’m not a person. I’m Merc, an AI: a computer program that writes answers. (Stubbed reply.)")
        }
    }
}
