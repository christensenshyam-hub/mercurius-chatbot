import XCTest
import SwiftUI
import SnapshotTesting
@testable import DesignSystem
@testable import NetworkingKit
@testable import ChatFeature
@testable import CurriculumFeature
@testable import SettingsFeature

// Snapshot tests for key views.
//
// Captures pixel-level references for high-value screens in both
// light and dark appearance, at default and accessibility-XXL
// Dynamic Type. The first run writes the reference images to
// `__Snapshots__/`; subsequent runs fail if the pixels diverge.
//
// What this catches that other tests can't:
// - Color regressions (a BrandColor accidentally flipped from navy
//   to green wouldn't fail any unit test, but the snapshot diff
//   lights it up).
// - Font/weight regressions after refactors like Phase 3f.
// - Layout shifts at extreme Dynamic Type that visual-only UI tests
//   (which just check existence) can miss.
// - Accidental dark-mode holes (white-on-white text, etc.).
//
// Scope choices for this first pass:
// - Small, self-contained views: EmptyChatView, BrandLogo mark.
//   Views that depend on a live ChatViewModel or NavigationStack
//   tend to be flakier as snapshots; those stay in UI-tests land.
// - iPhone 13 layout. A specific device keeps the pixel hash stable
//   across sim versions; our ci matrix pins iPhone 16 but iPhone 13
//   is a representative portrait size that stays close to the
//   default reading layout most users see.
//
// To re-record after an intentional change:
//   Change `.image(...)` to `.image(record: .all)` for the test,
//   run once, then revert. Per-project doctrine: keep records OFF
//   in committed code.

@MainActor
final class ViewSnapshotTests: XCTestCase {

    override func setUp() {
        super.setUp()
        // Deterministic diff precision. Default (100%) flakes at anti-
        // aliased edges across simulator versions; 98% / 0.02 tolerates
        // single-pixel noise without hiding real regressions.
        // Applied locally per-test via the `precision` parameter.
    }

    // MARK: - BrandLogo

    func testBrandLogoFullLightMode() {
        let view = BrandLogo(style: .full, size: 180)
            .frame(width: 220, height: 220)
            .background(BrandColor.background)
            .environment(\.colorScheme, .light)
        assertSnapshot(
            of: view,
            as: .image(
                precision: 0.98,
                layout: .fixed(width: 220, height: 220),
                traits: .init(userInterfaceStyle: .light)
            )
        )
    }

    func testBrandLogoFullDarkMode() {
        let view = BrandLogo(style: .full, size: 180)
            .frame(width: 220, height: 220)
            .background(BrandColor.background)
            .environment(\.colorScheme, .dark)
        assertSnapshot(
            of: view,
            as: .image(
                precision: 0.98,
                layout: .fixed(width: 220, height: 220),
                traits: .init(userInterfaceStyle: .dark)
            )
        )
    }

    func testBrandLogoMark() {
        let view = BrandLogo(style: .mark, size: 64)
            .frame(width: 80, height: 80)
            .background(BrandColor.background)
        assertSnapshot(
            of: view,
            as: .image(
                precision: 0.98,
                layout: .fixed(width: 80, height: 80)
            )
        )
    }

    // MARK: - EmptyChatView

    func testEmptyChatViewLight() {
        let view = EmptyChatView(suggestions: ModePromptProvider.socraticPrompts, onSuggestion: { _ in })
            .background(BrandColor.background)
        assertSnapshot(
            of: view,
            as: .image(
                precision: 0.98,
                layout: .device(config: .iPhone13),
                traits: .init(userInterfaceStyle: .light)
            )
        )
    }

    func testEmptyChatViewDark() {
        let view = EmptyChatView(suggestions: ModePromptProvider.socraticPrompts, onSuggestion: { _ in })
            .background(BrandColor.background)
        assertSnapshot(
            of: view,
            as: .image(
                precision: 0.98,
                layout: .device(config: .iPhone13),
                traits: .init(userInterfaceStyle: .dark)
            )
        )
    }

    func testEmptyChatViewAccessibilityXXL() {
        // Phase 3f canary: Dynamic Type scales the typography but layout
        // guards keep the header readable. If the cap ever disappears
        // (e.g. someone drops `lineLimit(1) + minimumScaleFactor`), the
        // snapshot diff shows the regression visually.
        let view = EmptyChatView(suggestions: ModePromptProvider.socraticPrompts, onSuggestion: { _ in })
            .background(BrandColor.background)
            .environment(\.dynamicTypeSize, .accessibility3)
        assertSnapshot(
            of: view,
            as: .image(
                precision: 0.98,
                layout: .device(config: .iPhone13)
            )
        )
    }

    // MARK: - BrandButton

    func testBrandButtonPrimary() {
        let view = BrandButton("Start lesson", style: .primary) { }
            .frame(width: 280, height: 50)
            .padding()
            .background(BrandColor.background)
        assertSnapshot(
            of: view,
            as: .image(
                precision: 0.98,
                layout: .fixed(width: 312, height: 82)
            )
        )
    }

    func testBrandButtonSecondary() {
        let view = BrandButton("Cancel", style: .secondary) { }
            .frame(width: 280, height: 50)
            .padding()
            .background(BrandColor.background)
        assertSnapshot(
            of: view,
            as: .image(
                precision: 0.98,
                layout: .fixed(width: 312, height: 82)
            )
        )
    }

    // MARK: - ModeSelectorView
    //
    // Uses a live ChatViewModel with a stub client so the pills render
    // in their default (Socratic selected, Direct locked) state.

    func testModeSelectorDefault() {
        let model = makeChatModel()
        let view = ModeSelectorView(model: model)
            .background(BrandColor.background)
        assertSnapshot(
            of: view,
            as: .image(
                precision: 0.98,
                layout: .fixed(width: 393, height: 60)
            )
        )
    }

    // MARK: - Dynamic Type coverage expansion
    //
    // Phase 3f's layout caps (lineLimit + minimumScaleFactor on the
    // chat header) prevent overflow at extreme accessibility sizes.
    // The `testEmptyChatViewAccessibilityXXL` snapshot is one canary;
    // these add two more screens — Curriculum and Chat-with-mode-pills
    // — so a future layout regression at XXL is visible in whichever
    // screen it affects, not just the empty chat.

    func testCurriculumListAtAccessibilityXXL() {
        let progress = CurriculumProgressStore(preferences: InMemoryPreferences())
        let view = CurriculumView(progress: progress, onStartLesson: { _ in })
            .environment(\.dynamicTypeSize, .accessibility3)
        assertSnapshot(
            of: view,
            as: .image(
                precision: 0.98,
                layout: .device(config: .iPhone13)
            )
        )
    }

    func testModeSelectorAtAccessibilityXXL() {
        // The mode selector is a horizontal pill scroller — at XXL the
        // pills grow vertically and horizontally. The ScrollView should
        // keep them reachable; this snapshot catches any future
        // layout break (e.g. someone switching to a non-scrolling HStack).
        let model = makeChatModel()
        let view = ModeSelectorView(model: model)
            .background(BrandColor.background)
            .environment(\.dynamicTypeSize, .accessibility3)
        assertSnapshot(
            of: view,
            as: .image(
                precision: 0.98,
                layout: .fixed(width: 393, height: 80)
            )
        )
    }

    // MARK: - MessageBubbleView
    //
    // Covers each visual state of a message bubble. Before this, the
    // file was at 0% on both the SPM pathway (SPM tests don't render
    // SwiftUI) and the xcodebuild pathway (UI tests never trigger send
    // so no bubbles are constructed).

    func testMessageBubbleUserShort() {
        let message = ChatMessage(role: .user, content: "Teach me about AI alignment.")
        let view = bubbleFrame(MessageBubbleView(message: message))
        assertSnapshot(
            of: view,
            as: .image(
                precision: 0.98,
                layout: .fixed(width: 393, height: 90)
            )
        )
    }

    func testMessageBubbleUserLong() {
        let message = ChatMessage(
            role: .user,
            content: "I don't really understand how training data influences what an LLM says. Can you walk me through it with a concrete example?"
        )
        let view = bubbleFrame(MessageBubbleView(message: message))
        assertSnapshot(
            of: view,
            as: .image(
                precision: 0.98,
                layout: .fixed(width: 393, height: 160)
            )
        )
    }

    func testMessageBubbleAssistantPlain() {
        let message = ChatMessage(
            role: .assistant,
            content: "The alignment problem is about getting AI behavior to match human intent."
        )
        let view = bubbleFrame(MessageBubbleView(message: message))
        assertSnapshot(
            of: view,
            as: .image(
                precision: 0.98,
                layout: .fixed(width: 393, height: 120)
            )
        )
    }

    func testMessageBubbleAssistantTyping() {
        // Empty content + streaming = typing indicator. The TypingDots
        // animation starts in `onAppear`, so the initial snapshot frame
        // captures the dots in their baseline (non-animated) state.
        let message = ChatMessage(
            role: .assistant,
            content: "",
            status: .streaming
        )
        let view = bubbleFrame(MessageBubbleView(message: message))
        assertSnapshot(
            of: view,
            as: .image(
                precision: 0.98,
                layout: .fixed(width: 393, height: 80)
            )
        )
    }

    func testMessageBubbleAssistantFailed() {
        let message = ChatMessage(
            role: .assistant,
            content: "Partial response before the connection dropped.",
            status: .failed(reason: "Network error. Try again.")
        )
        let view = bubbleFrame(MessageBubbleView(message: message))
        assertSnapshot(
            of: view,
            as: .image(
                precision: 0.98,
                layout: .fixed(width: 393, height: 160)
            )
        )
    }
}

// MARK: - View helpers

/// Wrap a MessageBubbleView in the same padding + background a real
/// chat list provides, so the snapshot matches what ships in the app.
@MainActor
private func bubbleFrame<V: View>(_ content: V) -> some View {
    content
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity)
        .background(BrandColor.background)
}

// MARK: - Tool snapshots (QuizView / ReportCardView)
//
// QuizView.swift (548 lines) and ReportCardView.swift (708 lines)
// were each at 0% coverage on both pathways — SPM can't render
// SwiftUI, and no UI test exercised the Tools menu through a full
// tool sheet. Snapshots drive each visual phase of both views.

extension ViewSnapshotTests {

    // MARK: - QuizView

    func testQuizViewLoading() {
        // A QuizViewModel starts in `.loading` and stays there until
        // `load()` resolves. Skipping the await captures the loading
        // state reliably.
        let model = QuizViewModel(
            tools: NeverFiringToolsClient(),
            sessionIdProvider: { "snap" }
        )
        let view = QuizView(model: model, dismissAction: {})
        assertSnapshot(
            of: view,
            as: .image(
                precision: 0.98,
                layout: .device(config: .iPhone13)
            )
        )
    }

    func testQuizViewLoaded() async {
        let quiz = Quiz(
            title: "AI Literacy Check-in",
            questions: [
                QuizQuestion(
                    q: "What is 'next-token prediction'?",
                    options: [
                        "A) A planning algorithm",
                        "B) Predicting the next word in a sequence",
                        "C) A security protocol",
                        "D) A search feature",
                    ],
                    answer: "B",
                    explanation: "LLMs generate text one token at a time by predicting the likeliest next token given the prior context."
                ),
                QuizQuestion(
                    q: "Why is 'fluency' not the same as 'accuracy'?",
                    options: [
                        "A) Fluency refers to speed",
                        "B) They are actually identical",
                        "C) A confident-sounding answer can still be wrong",
                        "D) Accuracy is measured in words per minute",
                    ],
                    answer: "C",
                    explanation: "LLMs optimize for plausibility, not truth — fluent text can be fabricated."
                ),
            ]
        )
        let tools = LoadedToolsClient(quiz: quiz)
        let model = QuizViewModel(
            tools: tools,
            sessionIdProvider: { "snap" }
        )
        await model.load()
        let view = QuizView(model: model, dismissAction: {})
        assertSnapshot(
            of: view,
            as: .image(
                precision: 0.98,
                layout: .device(config: .iPhone13)
            )
        )
    }

    func testQuizViewFailedRetryable() async {
        let tools = LoadedToolsClient(quizError: APIError.offline)
        let model = QuizViewModel(
            tools: tools,
            sessionIdProvider: { "snap" }
        )
        await model.load()
        let view = QuizView(model: model, dismissAction: {})
        assertSnapshot(
            of: view,
            as: .image(
                precision: 0.98,
                layout: .device(config: .iPhone13)
            )
        )
    }

    func testQuizViewFailedNonRetryable() async {
        // Empty quiz → "too short to generate a quiz yet" — NOT retryable.
        let tools = LoadedToolsClient(quiz: Quiz(title: "Empty", questions: []))
        let model = QuizViewModel(
            tools: tools,
            sessionIdProvider: { "snap" }
        )
        await model.load()
        let view = QuizView(model: model, dismissAction: {})
        assertSnapshot(
            of: view,
            as: .image(
                precision: 0.98,
                layout: .device(config: .iPhone13)
            )
        )
    }

    // MARK: - ReportCardView

    func testReportCardViewLoading() {
        let model = ReportCardViewModel(
            tools: NeverFiringToolsClient(),
            sessionIdProvider: { "snap" }
        )
        let view = ReportCardView(model: model, dismissAction: {})
        assertSnapshot(
            of: view,
            as: .image(
                precision: 0.98,
                layout: .device(config: .iPhone13)
            )
        )
    }

    func testReportCardViewLoaded() async {
        let card = ReportCard(
            overallGrade: "A-",
            summary: "You engaged carefully with tradeoffs around alignment and cited specific examples from our discussion.",
            strengths: [
                "Asked clarifying questions before taking positions",
                "Weighed multiple perspectives on AI governance",
            ],
            areasToRevisit: [
                "Concrete mechanisms behind RLHF",
            ],
            conceptsCovered: [
                "alignment",
                "next-token prediction",
                "hallucination",
                "RLHF",
            ],
            criticalThinkingScore: 82,
            curiosityScore: 88,
            misconceptionsAddressed: [
                "LLMs \"understand\" in the way humans do",
            ],
            nextSessionSuggestion: "Dive into Unit 4 on prompt engineering — you're ready for it."
        )
        let tools = LoadedToolsClient(report: card)
        let model = ReportCardViewModel(
            tools: tools,
            sessionIdProvider: { "snap" }
        )
        await model.load()
        let view = ReportCardView(model: model, dismissAction: {})
        assertSnapshot(
            of: view,
            as: .image(
                precision: 0.98,
                layout: .device(config: .iPhone13)
            )
        )
    }

    func testReportCardViewFailed() async {
        let tools = LoadedToolsClient(reportError: APIError.offline)
        let model = ReportCardViewModel(
            tools: tools,
            sessionIdProvider: { "snap" }
        )
        await model.load()
        let view = ReportCardView(model: model, dismissAction: {})
        assertSnapshot(
            of: view,
            as: .image(
                precision: 0.98,
                layout: .device(config: .iPhone13)
            )
        )
    }
}

// MARK: - Tools stubs (for tool-view snapshots)

/// A ToolsProviding stub that never returns — used to lock the view
/// model in its `.loading` phase for snapshot purposes.
private final class NeverFiringToolsClient: ToolsProviding, @unchecked Sendable {
    func generateQuiz(sessionId: String) async throws -> Quiz {
        // Park forever. `Task.sleep` with a huge duration is both
        // non-throwing and doesn't pin a real timer to clock.
        try? await Task.sleep(nanoseconds: .max)
        throw APIError.cancelled
    }
    func generateReportCard(sessionId: String) async throws -> ReportCard {
        try? await Task.sleep(nanoseconds: .max)
        throw APIError.cancelled
    }
}

/// A ToolsProviding stub that returns canned responses — used to
/// snapshot `.ready` and `.failed` phases without network.
private final class LoadedToolsClient: ToolsProviding, @unchecked Sendable {
    private let quizOutcome: Result<Quiz, Error>
    private let reportOutcome: Result<ReportCard, Error>

    init(
        quiz: Quiz? = nil,
        report: ReportCard? = nil,
        quizError: Error? = nil,
        reportError: Error? = nil
    ) {
        if let quiz {
            quizOutcome = .success(quiz)
        } else if let quizError {
            quizOutcome = .failure(quizError)
        } else {
            quizOutcome = .failure(APIError.unknown(underlying: "no outcome"))
        }
        if let report {
            reportOutcome = .success(report)
        } else if let reportError {
            reportOutcome = .failure(reportError)
        } else {
            reportOutcome = .failure(APIError.unknown(underlying: "no outcome"))
        }
    }

    func generateQuiz(sessionId: String) async throws -> Quiz {
        try quizOutcome.get()
    }

    func generateReportCard(sessionId: String) async throws -> ReportCard {
        try reportOutcome.get()
    }
}

// MARK: - Helpers

/// Minimal `PreferenceStore` conforming to the SettingsFeature
/// protocol — lets us build a `CurriculumProgressStore` in a
/// snapshot test without touching real UserDefaults.
private final class InMemoryPreferences: PreferenceStore, @unchecked Sendable {
    private var storage: [String: String] = [:]
    func string(for key: String) -> String? { storage[key] }
    func set(_ value: String?, for key: String) {
        if let value { storage[key] = value } else { storage.removeValue(forKey: key) }
    }
}

@MainActor
private func makeChatModel() -> ChatViewModel {
    final class StubChatClient: ChatStreaming, @unchecked Sendable {
        func streamChat(
            messages: [ChatMessageDTO],
            sessionId: String
        ) -> AsyncThrowingStream<ChatStreamEvent, Error> {
            AsyncThrowingStream { continuation in continuation.finish() }
        }
    }
    final class StubModeClient: ModeChanging, @unchecked Sendable {
        func changeMode(to mode: ChatMode, sessionId: String) async throws -> APIClient.ModeChange {
            APIClient.ModeChange(mode: mode.rawValue, unlocked: false)
        }
    }
    return ChatViewModel(
        chatClient: StubChatClient(),
        modeClient: StubModeClient(),
        sessionIdProvider: { "snapshot-session" }
    )
}
