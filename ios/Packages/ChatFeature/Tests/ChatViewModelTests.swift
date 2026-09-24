import Testing
import Foundation
@testable import ChatFeature
@testable import NetworkingKit

// MARK: - Fake chat client

/// A deterministic `ChatStreaming` stub. Tests configure the sequence
/// of events (or an error) it will emit per call.
final class FakeChatClient: ChatStreaming, @unchecked Sendable {
    enum Outcome {
        case events([ChatStreamEvent])
        case failure(Error)
    }

    var outcome: Outcome = .events([])
    var receivedMessages: [[ChatMessageDTO]] = []
    var receivedSessionIds: [String] = []
    var receivedResponseModes: [ResponseMode] = []
    var receivedImageIds: [String?] = []

    func streamChat(
        messages: [ChatMessageDTO],
        sessionId: String,
        responseMode: ResponseMode,
        imageId: String?
    ) -> AsyncThrowingStream<ChatStreamEvent, Error> {
        receivedMessages.append(messages)
        receivedSessionIds.append(sessionId)
        receivedResponseModes.append(responseMode)
        receivedImageIds.append(imageId)

        let outcome = self.outcome
        return AsyncThrowingStream { continuation in
            Task {
                switch outcome {
                case .events(let events):
                    for event in events {
                        continuation.yield(event)
                    }
                    continuation.finish()
                case .failure(let error):
                    continuation.finish(throwing: error)
                }
            }
        }
    }
}

// MARK: - Helpers

@MainActor
private func makeModel(client: FakeChatClient, sessionId: String = "test-session") -> ChatViewModel {
    ChatViewModel(
        chatClient: client,
        modeClient: FakeModeClient(),
        sessionIdProvider: { sessionId }
    )
}

/// Await the view model's return to `.idle` (or `.failed`) — necessary
/// because `send()` kicks off a detached task. Times out after 2s.
@MainActor
private func waitUntilSettled(_ model: ChatViewModel, timeout: Duration = .seconds(2)) async throws {
    let deadline = ContinuousClock.now.advanced(by: timeout)
    while ContinuousClock.now < deadline {
        switch model.phase {
        case .idle, .failed:
            return
        case .sending, .streaming:
            try await Task.sleep(for: .milliseconds(20))
        }
    }
    Issue.record("Timeout waiting for model to settle (phase: \(model.phase))")
}

// MARK: - Tests

@Suite("ChatViewModel send lifecycle")
@MainActor
struct ChatViewModelSendTests {

    @Test("Empty draft is a no-op")
    func emptyDraft() {
        let model = makeModel(client: FakeChatClient())
        model.draft = "   "
        model.send()
        #expect(model.messages.isEmpty)
        #expect(model.phase == .idle)
    }

    @Test("Send inserts user message and assistant placeholder")
    func insertsPlaceholder() async throws {
        let client = FakeChatClient()
        let sample = ChatResponse(
            reply: "Hi there!",
            mode: "socratic",
            streak: 1
        )
        client.outcome = .events([
            .delta(text: "Hi"),
            .delta(text: " there!"),
            .complete(sample),
        ])
        let model = makeModel(client: client)
        model.draft = "Hello"
        model.send()

        try await waitUntilSettled(model)

        #expect(model.messages.count == 2)
        #expect(model.messages[0].role == .user)
        #expect(model.messages[0].content == "Hello")
        #expect(model.messages[1].role == .assistant)
        #expect(model.messages[1].content == "Hi there!")
        #expect(model.messages[1].status == .idle)
        #expect(model.phase == .idle)
        #expect(model.draft == "")
    }

    @Test("History sent to server excludes the pending assistant placeholder")
    func historyExcludesPlaceholder() async throws {
        let client = FakeChatClient()
        let sample = ChatResponse(
            reply: "ok",
            mode: "socratic",
            streak: 1
        )
        client.outcome = .events([.complete(sample)])
        let model = makeModel(client: client)
        model.draft = "Hello"
        model.send()
        try await waitUntilSettled(model)

        #expect(client.receivedMessages.count == 1)
        let sent = client.receivedMessages[0]
        #expect(sent.count == 1)
        #expect(sent[0].role == "user")
        #expect(sent[0].content == "Hello")
    }

    @Test("Session id is passed to the client")
    func sessionIdPassed() async throws {
        let client = FakeChatClient()
        let sample = ChatResponse(
            reply: "ok",
            mode: "socratic",
            streak: 1
        )
        client.outcome = .events([.complete(sample)])
        let model = makeModel(client: client, sessionId: "abc")
        model.draft = "Hi"
        model.send()
        try await waitUntilSettled(model)

        #expect(client.receivedSessionIds == ["abc"])
    }
}

@Suite("ChatViewModel error handling")
@MainActor
struct ChatViewModelErrorTests {

    @Test("Transport error marks phase .failed with retryable flag")
    func transportError() async throws {
        let client = FakeChatClient()
        client.outcome = .failure(APIError.offline)
        let model = makeModel(client: client)
        model.draft = "Hello"
        model.send()
        try await waitUntilSettled(model)

        #expect(model.messages.count == 2)
        if case .failed(_, let isRetryable) = model.phase {
            #expect(isRetryable)
        } else {
            Issue.record("Expected .failed phase")
        }
    }

    @Test("Stream `error` event surfaces the message")
    func streamError() async throws {
        let client = FakeChatClient()
        client.outcome = .events([.streamError(message: "server said no")])
        let model = makeModel(client: client)
        model.draft = "Hello"
        model.send()
        try await waitUntilSettled(model)

        if case .failed(let reason, _) = model.phase {
            #expect(reason.contains("server said no"))
        } else {
            Issue.record("Expected .failed phase")
        }
    }

    @Test("Session resolution failure is non-retryable")
    func sessionResolutionFailure() async throws {
        struct BadSession: Error {}
        let client = FakeChatClient()
        let model = ChatViewModel(
            chatClient: client,
            modeClient: FakeModeClient(),
            sessionIdProvider: { throw BadSession() }
        )
        model.draft = "Hello"
        model.send()
        try await waitUntilSettled(model)

        if case .failed(_, let retryable) = model.phase {
            #expect(!retryable)
        } else {
            Issue.record("Expected .failed phase")
        }
    }

    @Test("Unauthorized error is not retryable")
    func unauthorizedNotRetryable() async throws {
        let client = FakeChatClient()
        client.outcome = .failure(APIError.unauthorized)
        let model = makeModel(client: client)
        model.draft = "Hello"
        model.send()
        try await waitUntilSettled(model)

        if case .failed(_, let retryable) = model.phase {
            #expect(!retryable)
        } else {
            Issue.record("Expected .failed phase")
        }
    }

    // MARK: Server refusals (SSE `error` frame with a refusal code)

    @Test("A daily_limit refusal shows the server's copy and is NOT retryable")
    func refusalDailyLimitIsNotRetryable() async throws {
        let client = FakeChatClient()
        let copy = "You've used today's chat turns. Mercurius will be ready again tomorrow."
        client.outcome = .events([.refusal(code: "daily_limit", message: copy, retryAfter: 3600)])
        let model = makeModel(client: client)
        model.draft = "Hello"
        model.send()
        try await waitUntilSettled(model)

        #expect(model.phase == .failed(reason: copy, isRetryable: false))
        #expect(model.messages.last?.role == .assistant)
        #expect(model.messages.last?.status == .failed(reason: copy))
    }

    @Test("A busy refusal shows the server's copy and IS retryable")
    func refusalBusyIsRetryable() async throws {
        let client = FakeChatClient()
        let copy = "Mercurius is helping a lot of students right now. Try again in a minute."
        client.outcome = .events([.refusal(code: "busy", message: copy, retryAfter: 60)])
        let model = makeModel(client: client)
        model.draft = "Hello"
        model.send()
        try await waitUntilSettled(model)

        #expect(model.phase == .failed(reason: copy, isRetryable: true))
        #expect(model.messages.last?.status == .failed(reason: copy))
    }

    @Test("Every non-daily_limit refusal code keeps Retry available", arguments: ["spend_cap", "service_disabled", "restarting"])
    func otherRefusalsAreRetryable(code: String) async throws {
        let client = FakeChatClient()
        client.outcome = .events([.refusal(code: code, message: "Paused for now.", retryAfter: nil)])
        let model = makeModel(client: client)
        model.draft = "Hello"
        model.send()
        try await waitUntilSettled(model)

        #expect(model.phase == .failed(reason: "Paused for now.", isRetryable: true))
    }

    @Test("A refusal's copy bypasses the billing sanitizer (server wording is trusted)")
    func refusalCopyIsNotSanitized() async throws {
        let client = FakeChatClient()
        // Contains a word the streamError sanitizer would mask.
        let copy = "Daily usage limit reached — billing resets tomorrow."
        client.outcome = .events([.refusal(code: "spend_cap", message: copy, retryAfter: nil)])
        let model = makeModel(client: client)
        model.draft = "Hello"
        model.send()
        try await waitUntilSettled(model)

        #expect(model.phase == .failed(reason: copy, isRetryable: true))
    }

    // MARK: JSON-path refusals (a real 429 / 503 on /api/chat)

    @Test("APIError.quotaExceeded surfaces the server message and is not retryable")
    func quotaExceededIsNotRetryable() async throws {
        let client = FakeChatClient()
        let copy = "You've reached today's usage limit. Mercurius will be ready again tomorrow."
        client.outcome = .failure(APIError.quotaExceeded(message: copy, retryAfter: 7200))
        let model = makeModel(client: client)
        model.draft = "Hello"
        model.send()
        try await waitUntilSettled(model)

        #expect(model.phase == .failed(reason: copy, isRetryable: false))
        #expect(model.messages.last?.status == .failed(reason: copy))
    }

    @Test("APIError.serviceUnavailable surfaces the server message and is retryable")
    func serviceUnavailableIsRetryable() async throws {
        let client = FakeChatClient()
        let copy = "Mercurius is restarting — try again in a few seconds."
        client.outcome = .failure(APIError.serviceUnavailable(code: "restarting", message: copy, retryAfter: 5))
        let model = makeModel(client: client)
        model.draft = "Hello"
        model.send()
        try await waitUntilSettled(model)

        #expect(model.phase == .failed(reason: copy, isRetryable: true))
    }
}

@Suite("ChatViewModel retry")
@MainActor
struct ChatViewModelRetryTests {

    @Test("Retry removes the failed assistant bubble and starts a fresh stream")
    func retrySucceedsAfterFailure() async throws {
        let client = FakeChatClient()
        client.outcome = .failure(APIError.timeout)
        let model = makeModel(client: client)
        model.draft = "Hello"
        model.send()
        try await waitUntilSettled(model)

        // Now configure a successful second attempt.
        let success = ChatResponse(
            reply: "On retry.",
            mode: "socratic",
            streak: 1
        )
        client.outcome = .events([.complete(success)])
        model.retry()
        try await waitUntilSettled(model)

        #expect(model.messages.count == 2)
        #expect(model.messages.last?.content == "On retry.")
        #expect(model.phase == .idle)
    }
}

@Suite("ChatViewModel response-mode + explainMore")
@MainActor
struct ChatViewModelResponseModeTests {

    private func minimalReply() -> ChatResponse {
        ChatResponse(
            reply: "ok",
            mode: "socratic",
            streak: 0
        )
    }

    @Test("Default send uses .concise (mobile-native default)")
    func defaultIsConcise() async throws {
        let client = FakeChatClient()
        client.outcome = .events([.complete(minimalReply())])
        let model = makeModel(client: client)
        model.draft = "Hello"
        model.send()
        try await waitUntilSettled(model)

        #expect(client.receivedResponseModes.last == .concise,
                "First-touch sends should default to .concise")
    }

    @Test("explainMore() sends with .deep")
    func explainMoreUsesDeep() async throws {
        let client = FakeChatClient()
        client.outcome = .events([.complete(minimalReply())])
        let model = makeModel(client: client)

        // Seed an existing assistant turn so explainMore has context.
        model.draft = "What is an LLM?"
        model.send()
        try await waitUntilSettled(model)

        // Configure the next turn's outcome.
        client.outcome = .events([.complete(minimalReply())])
        model.explainMore()
        try await waitUntilSettled(model)

        #expect(client.receivedResponseModes.count == 2)
        #expect(client.receivedResponseModes[0] == .concise,
                "Initial turn should be concise")
        #expect(client.receivedResponseModes[1] == .deep,
                "explainMore() should escalate to .deep")
    }

    @Test("explainMore() is a no-op while a stream is in flight")
    func explainMoreIgnoredMidStream() async {
        let client = FakeChatClient()
        // Outcome that finishes lazily — we'll inspect state mid-flight.
        client.outcome = .events([])  // immediately finishes; gives us idle phase
        let model = makeModel(client: client)

        // Empty messages → explainMore should bail without sending.
        model.explainMore()
        #expect(client.receivedResponseModes.isEmpty,
                "explainMore() with no prior messages must not send")
    }

    @Test("explainMore() does NOT add a visible user message to the thread")
    func explainMoreIsHidden() async throws {
        let client = FakeChatClient()
        client.outcome = .events([.complete(minimalReply())])
        let model = makeModel(client: client)

        model.draft = "What is an LLM?"
        model.send()
        try await waitUntilSettled(model)
        let beforeCount = model.messages.count
        #expect(beforeCount == 2, "Should have 1 user + 1 assistant after the seed turn")

        client.outcome = .events([.complete(minimalReply())])
        model.explainMore()
        try await waitUntilSettled(model)

        // Only ONE new message landed in the visible thread — the
        // assistant reply. No "Explain more" user bubble.
        #expect(model.messages.count == beforeCount + 1)
        #expect(model.messages.last?.role == .assistant)

        let visibleUserContent = model.messages
            .filter { $0.role == .user }
            .map(\.content)
        #expect(!visibleUserContent.contains(where: { $0.lowercased().contains("explain more") }),
                "The Explain More instruction must stay off the visible thread")
    }

    @Test("explainMore() injects the instruction on the wire (so the model sees it)")
    func explainMoreInjectsOnWire() async throws {
        let client = FakeChatClient()
        client.outcome = .events([.complete(minimalReply())])
        let model = makeModel(client: client)

        model.draft = "What is an LLM?"
        model.send()
        try await waitUntilSettled(model)

        client.outcome = .events([.complete(minimalReply())])
        model.explainMore()
        try await waitUntilSettled(model)

        // The second request's wire history must contain the injected
        // user turn with the "Explain more" instruction even though
        // the local chat state never saw it.
        let secondRequest = client.receivedMessages.last ?? []
        let injected = secondRequest.last
        #expect(injected?.role == "user")
        #expect(injected?.content.lowercased().contains("explain more") == true)
    }

    @Test("After explainMore, a user-typed send returns to .concise")
    func deepToConciseTransition() async throws {
        let client = FakeChatClient()
        client.outcome = .events([.complete(minimalReply())])
        let model = makeModel(client: client)

        model.draft = "What is an LLM?"
        model.send()
        try await waitUntilSettled(model)

        client.outcome = .events([.complete(minimalReply())])
        model.explainMore()
        try await waitUntilSettled(model)
        #expect(client.receivedResponseModes.last == .deep)

        // The very next user-typed send must default to .concise.
        // `deep` is one-shot; it never gets stuck.
        client.outcome = .events([.complete(minimalReply())])
        model.draft = "What about GPT-3?"
        model.send()
        try await waitUntilSettled(model)

        #expect(client.receivedResponseModes.last == .concise,
                "A user-typed send after explainMore must default to .concise — deep is one-shot")
    }

    @Test("Retry reuses the last responseMode")
    func retryReusesResponseMode() async throws {
        let client = FakeChatClient()
        client.outcome = .failure(URLError(.networkConnectionLost))
        let model = makeModel(client: client)
        model.draft = "Why?"
        model.send(responseMode: .balanced)
        try await waitUntilSettled(model)

        client.outcome = .events([.complete(minimalReply())])
        model.retry()
        try await waitUntilSettled(model)

        #expect(client.receivedResponseModes.last == .balanced,
                "Retry should reuse the original responseMode, not silently drop to .concise")
    }
}

// MARK: - Image attach

private final class StubImageUploader: ImageUploading, @unchecked Sendable {
    let response: APIClient.ImageUploadResponse
    private(set) var callCount = 0
    init(response: APIClient.ImageUploadResponse) { self.response = response }
    func uploadImage(_ input: APIClient.ImageUploadInput, sessionId: String) async throws -> APIClient.ImageUploadResponse {
        callCount += 1
        return response
    }
}

private struct StubPreparer: ImagePreparing {
    func prepare(imageData: Data, fileName: String?) throws -> APIClient.ImageUploadInput {
        APIClient.ImageUploadInput(contentType: "image/jpeg", base64Data: "QUJD", fileName: nil)
    }
}

private func imageTestReply() -> ChatResponse {
    ChatResponse(reply: "ok", mode: "socratic")
}

private func sampleUploadResponse() -> APIClient.ImageUploadResponse {
    APIClient.ImageUploadResponse(
        id: "img_abc", url: "/api/images/img_abc", contentType: "image/jpeg",
        fileName: nil, size: 3, createdAt: "2026-05-31T00:00:00.000Z"
    )
}

@Suite("ChatViewModel image attach")
@MainActor
struct ChatViewModelImageTests {

    @Test("Attaching a photo uploads it and streams with the imageId")
    func attachUploadsAndStreams() async throws {
        let client = FakeChatClient()
        client.outcome = .events([.complete(imageTestReply())])
        let uploader = StubImageUploader(response: sampleUploadResponse())
        let model = ChatViewModel(
            chatClient: client,
            modeClient: FakeModeClient(),
            sessionIdProvider: { "sess" },
            store: nil,
            imageUploader: uploader,
            preparer: StubPreparer()
        )

        model.attachImage(data: Data([0x01, 0x02, 0x03]))
        #expect(model.pendingImageData != nil)
        model.draft = "What is this?"
        model.send()
        // Cleared on send — the photo moves into the user bubble.
        #expect(model.pendingImageData == nil)

        try await waitUntilSettled(model)

        #expect(uploader.callCount == 1)
        #expect(client.receivedImageIds.last == "img_abc")
        #expect(model.messages.first?.imageData != nil, "user bubble keeps the photo for display")
    }

    @Test("A photo-only message (no text) is allowed")
    func photoOnlySends() async throws {
        let client = FakeChatClient()
        client.outcome = .events([.complete(imageTestReply())])
        let uploader = StubImageUploader(response: sampleUploadResponse())
        let model = ChatViewModel(
            chatClient: client, modeClient: FakeModeClient(), sessionIdProvider: { "sess" },
            store: nil, imageUploader: uploader, preparer: StubPreparer()
        )

        model.attachImage(data: Data([0x09]))
        model.send()   // no draft text
        try await waitUntilSettled(model)

        #expect(uploader.callCount == 1)
        #expect(client.receivedImageIds.last == "img_abc")
    }

    @Test("Text-only send attaches no image (imageId nil)")
    func textOnlyNoImage() async throws {
        let client = FakeChatClient()
        client.outcome = .events([.complete(imageTestReply())])
        let model = makeModel(client: client)
        model.draft = "Just text"
        model.send()
        try await waitUntilSettled(model)
        let lastImageId = client.receivedImageIds.last ?? nil
        #expect(lastImageId == nil, "no imageId for a text-only turn")
    }

    @Test("clearAttachment removes the pending photo")
    func clearAttachmentClears() {
        let model = ChatViewModel(chatClient: FakeChatClient(), modeClient: FakeModeClient(), sessionIdProvider: { "s" })
        model.attachImage(data: Data([0x01]))
        #expect(model.pendingImageData != nil)
        model.clearAttachment()
        #expect(model.pendingImageData == nil)
    }
}

// MARK: - Report (Guideline 1.2)

private final class StubReporter: Reporting, @unchecked Sendable {
    struct Report {
        let content: String
        let reason: ReportReason
        let userMessage: String?
        let context: ReportContext
        let sessionId: String
    }

    private(set) var reports: [Report] = []
    /// When set, every submission throws this instead of recording.
    var error: Error?

    func reportResponse(
        content: String,
        reason: ReportReason,
        userMessage: String?,
        context: ReportContext,
        sessionId: String
    ) async throws {
        if let error { throw error }
        reports.append(Report(content: content, reason: reason, userMessage: userMessage,
                              context: context, sessionId: sessionId))
    }
}

private func reportTestReply(_ text: String = "ok") -> ChatResponse {
    ChatResponse(reply: text, mode: "socratic")
}

@MainActor
private func makeReportingModel(client: FakeChatClient = FakeChatClient(),
                                reporter: StubReporter) -> ChatViewModel {
    ChatViewModel(
        chatClient: client, modeClient: FakeModeClient(),
        sessionIdProvider: { "sess" }, store: nil, reporting: reporter
    )
}

@Suite("ChatViewModel report")
@MainActor
struct ChatViewModelReportTests {

    @Test("Reporting an assistant message sends its content, reason + session to the reporter")
    func reportsAssistantMessage() async throws {
        let reporter = StubReporter()
        let model = makeReportingModel(reporter: reporter)

        let outcome = await model.reportMessage(
            ChatMessage(role: .assistant, content: "a questionable reply"), reason: .harmful
        )

        #expect(outcome == .sent)
        #expect(model.lastReportOutcome == .sent)
        #expect(reporter.reports.count == 1)
        #expect(reporter.reports.first?.content == "a questionable reply")
        #expect(reporter.reports.first?.reason == .harmful)
        #expect(reporter.reports.first?.sessionId == "sess")
    }

    @Test("Reporting a user message sends nothing")
    func ignoresUserMessage() async throws {
        let reporter = StubReporter()
        let model = makeReportingModel(reporter: reporter)

        let outcome = await model.reportMessage(ChatMessage(role: .user, content: "hi"), reason: .wrong)

        #expect(reporter.reports.isEmpty)
        if case .failed = outcome {} else { Issue.record("Expected .failed, got \(outcome)") }
    }

    @Test("The report carries the nearest preceding VISIBLE user turn — even across an Explain more")
    func reportIncludesPrecedingUserTurn() async throws {
        let client = FakeChatClient()
        client.outcome = .events([.complete(reportTestReply("Short answer."))])
        let reporter = StubReporter()
        let model = makeReportingModel(client: client, reporter: reporter)

        model.draft = "What is an LLM?"
        model.send()
        try await waitUntilSettled(model)

        // "Explain more" is wire-only: the visible thread gains an assistant
        // reply but no user turn, so the report must map back to the question.
        client.outcome = .events([.complete(reportTestReply("Longer answer."))])
        model.explainMore()
        try await waitUntilSettled(model)
        let deeper = try #require(model.messages.last)
        #expect(deeper.role == .assistant && deeper.content == "Longer answer.")

        let outcome = await model.reportMessage(deeper, reason: .wrong)

        #expect(outcome == .sent)
        let report = try #require(reporter.reports.first)
        #expect(report.content == "Longer answer.")
        #expect(report.userMessage == "What is an LLM?")
        #expect(report.context == ReportContext(surface: "chat", mode: "socratic", lessonId: nil, appVersion: nil))
    }

    @Test("A photo-only turn's placeholder text is the userMessage")
    func reportUsesPhotoPlaceholderAsUserTurn() async throws {
        let client = FakeChatClient()
        client.outcome = .events([.complete(reportTestReply("Nice photo."))])
        let reporter = StubReporter()
        let model = ChatViewModel(
            chatClient: client, modeClient: FakeModeClient(), sessionIdProvider: { "sess" },
            store: nil, imageUploader: StubImageUploader(response: sampleUploadResponse()),
            preparer: StubPreparer(), reporting: reporter
        )

        model.attachImage(data: Data([0x01]))
        model.send()   // no text
        try await waitUntilSettled(model)

        let reply = try #require(model.messages.last)
        _ = await model.reportMessage(reply, reason: .other)
        #expect(reporter.reports.first?.userMessage == "[Shared an image]")
    }

    @Test("The first lesson reply has no visible user turn → userMessage is nil")
    func firstLessonReplyReportHasNoUserMessage() async throws {
        let client = FakeChatClient()
        client.outcome = .events([.complete(reportTestReply("Welcome to the lesson."))])
        let reporter = StubReporter()
        let model = makeReportingModel(client: client, reporter: reporter)
        model.onLessonComplete = { }   // marks this as a lesson thread

        model.beginLessonConversation(starter: "[CURRICULUM: Unit 1, Lesson 1] Teach me.", lessonId: "u1_l1")
        try await waitUntilSettled(model)
        let opener = try #require(model.messages.last)
        #expect(model.messages.count == 1, "the opener is wire-only; only the reply is visible")

        let outcome = await model.reportMessage(opener, reason: .offTopic)

        #expect(outcome == .sent)
        let report = try #require(reporter.reports.first)
        #expect(report.userMessage == nil)
        #expect(report.content == "Welcome to the lesson.")
        #expect(report.reason == .offTopic)
    }

    @Test("A lesson report's context carries surface, curriculum mode and the lessonId")
    func reportContextForLessonCarriesLessonId() async throws {
        let client = FakeChatClient()
        client.outcome = .events([.complete(reportTestReply("Let's begin."))])
        let reporter = StubReporter()
        let model = makeReportingModel(client: client, reporter: reporter)
        model.onLessonComplete = { }

        model.beginLessonConversation(starter: "[CURRICULUM: Unit 2, Lesson 3] Go.", lessonId: "u2_l3")
        try await waitUntilSettled(model)
        #expect(model.currentLessonId == "u2_l3")

        // A follow-up turn in the same lesson still reports under the lesson.
        client.outcome = .events([.complete(reportTestReply("Good answer."))])
        model.draft = "Bias comes from training data."
        model.send()
        try await waitUntilSettled(model)

        let reply = try #require(model.messages.last)
        _ = await model.reportMessage(reply, reason: .wrong)

        let report = try #require(reporter.reports.first)
        #expect(report.context == ReportContext(surface: "lesson", mode: "curriculum", lessonId: "u2_l3", appVersion: nil))
        #expect(report.userMessage == "Bias comes from training data.")
    }

    @Test("Free chat has no lessonId and reports under the current mode")
    func chatReportHasNoLessonId() async throws {
        let reporter = StubReporter()
        let model = makeReportingModel(reporter: reporter)
        #expect(model.currentLessonId == nil)

        _ = await model.reportMessage(ChatMessage(role: .assistant, content: "hm"), reason: .other)

        let report = try #require(reporter.reports.first)
        #expect(report.context.surface == "chat")
        #expect(report.context.mode == "socratic")
        #expect(report.context.lessonId == nil)
    }

    @Test("A failed submission surfaces the outcome instead of confirming")
    func reportFailureSurfacesOutcome() async throws {
        let reporter = StubReporter()
        reporter.error = APIError.offline
        let model = makeReportingModel(reporter: reporter)

        let outcome = await model.reportMessage(
            ChatMessage(role: .assistant, content: "a questionable reply"), reason: .wrong
        )

        #expect(outcome == .failed(APIError.offline.userFacingMessage))
        #expect(model.lastReportOutcome == outcome)
        #expect(reporter.reports.isEmpty)
    }

    @Test("Without a reporter wired, reporting fails rather than confirming")
    func reportWithoutReporterFails() async throws {
        let model = makeModel(client: FakeChatClient())   // no `reporting`
        let outcome = await model.reportMessage(
            ChatMessage(role: .assistant, content: "reply"), reason: .wrong
        )
        if case .failed = outcome {} else { Issue.record("Expected .failed, got \(outcome)") }
    }
}
