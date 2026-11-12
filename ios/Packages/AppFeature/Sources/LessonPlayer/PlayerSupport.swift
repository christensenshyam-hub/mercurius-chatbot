import SwiftUI
import DesignSystem
import LessonPlayer
import NetworkingKit
import OSLog

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

/// Short-response evaluation through the server relay (milestone 4 fills this
/// in). Until then every response is "ungraded (unavailable)", which the
/// player shows honestly and never counts as correct.
enum LessonPlayerEvaluation {
    @MainActor
    static func evaluate(_ request: EvaluationRequest, apiClient: APIClient,
                         sessionIdentity: SessionIdentity) async -> EvaluationOutcome {
        if let stub = stubbedOutcome(arguments: AppEnvironment.testHookArguments(ProcessInfo.processInfo.arguments)) {
            try? await Task.sleep(for: .milliseconds(400))
            return stub
        }
        return .failed(.unavailable)
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

/// The player's event sink (milestone 5 documents it): a local debug log only.
@MainActor
final class LessonPlayerTelemetry {
    static let shared = LessonPlayerTelemetry()
    private let log = Logger(subsystem: "com.mayoailiteracy.mercurius", category: "lessonPlayer")

    func record(_ event: LessonPlayerEvent) {
        let fields = event.fields.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: " ")
        log.debug("\(event.name, privacy: .public) \(fields, privacy: .public)")
    }
}
