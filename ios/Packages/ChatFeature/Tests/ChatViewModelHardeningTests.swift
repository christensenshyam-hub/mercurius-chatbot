import Testing
import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import SwiftUI
@testable import ChatFeature
@testable import NetworkingKit
@testable import PersistenceKit

// MARK: - Helpers

@MainActor
private func settle(_ model: ChatViewModel, timeout: Duration = .seconds(10)) async {
    let deadline = ContinuousClock.now.advanced(by: timeout)
    while ContinuousClock.now < deadline {
        switch model.phase {
        case .idle, .failed: return
        case .sending, .streaming: try? await Task.sleep(for: .milliseconds(10))
        }
    }
    Issue.record("Timeout waiting for the model to settle (phase: \(model.phase))")
}

@MainActor
private func poll(_ label: String, timeout: Duration = .seconds(10), _ condition: () -> Bool) async {
    let deadline = ContinuousClock.now.advanced(by: timeout)
    while ContinuousClock.now < deadline {
        if condition() { return }
        try? await Task.sleep(for: .milliseconds(10))
    }
    Issue.record("Timeout waiting for: \(label)")
}

private func reply(_ text: String = "ok") -> ChatStreamEvent {
    .complete(ChatResponse(reply: text, mode: "socratic"))
}

private let lessonStarter = "[CURRICULUM: Unit 1, Lesson 1] Teach me what a token is."

private func isRetryableFailure(_ phase: ChatViewModel.Phase) -> Bool {
    if case .failed(_, let isRetryable) = phase { return isRetryable }
    return false
}

// MARK: - Message length

@Suite("ChatViewModel message length")
@MainActor
struct MessageLengthTests {

    @Test("Clamping counts UTF-16 units and never splits a character")
    func clampCountsUTF16() {
        #expect(ChatViewModel.clamped("ab😀c", toUTF16: 3) == "ab")
        #expect(ChatViewModel.clamped("ab😀c", toUTF16: 4) == "ab😀")
        #expect(ChatViewModel.clamped("short", toUTF16: 2_000) == "short")
    }

    @Test("A turn saved over the server's cap is clamped on every later request, and the latest to what the server reads")
    func savedOversizedTurnIsClamped() async {
        let store = InMemoryChatStore()
        let convo = store.createConversation(mode: .socratic)
        let essay = String(repeating: "word ", count: 2_432)   // 12,160 chars
        store.append(StoredMessage(id: UUID(), role: "user", content: essay, createdAt: Date()), to: convo)
        store.append(StoredMessage(id: UUID(), role: "assistant", content: "ok", createdAt: Date()), to: convo)

        let client = FakeChatClient()
        client.outcome = .events([reply()])
        let model = ChatViewModel(chatClient: client, modeClient: FakeModeClient(),
                                  sessionIdProvider: { "s" }, store: store)
        #expect(model.messages.count == 2)

        model.draft = "and now?"
        model.send()
        await settle(model)

        let wire = client.receivedMessages.last ?? []
        #expect(wire.map(\.content.utf16.count) == [10_000, 2, 8])
        #expect(model.phase == .idle)

        client.outcome = .events([reply()])
        model.draft = String(repeating: "x", count: 6_000)
        model.send()
        await settle(model)
        #expect(client.receivedMessages.last?.last?.content.utf16.count == 2_000)
    }

    @Test("A lesson's tagged latest turn fits what the server reads, and the composer allows for the tag")
    func lessonTurnFitsWithTag() async {
        let client = FakeChatClient()
        client.outcome = .events([reply("Here's a token.")])
        let model = ChatViewModel(chatClient: client, modeClient: FakeModeClient(), sessionIdProvider: { "s" })
        #expect(model.draftCharacterLimit == 2_000)
        model.onLessonComplete = {}
        model.beginLessonConversation(starter: lessonStarter, lessonId: "u1_l1")
        await settle(model)

        let tag = "[CURRICULUM: Unit 1, Lesson 1]"
        #expect(model.draftCharacterLimit == 2_000 - tag.utf16.count - 1)

        client.outcome = .events([reply()])
        model.draft = String(repeating: "y", count: model.draftCharacterLimit)
        model.send()
        await settle(model)
        let latest = client.receivedMessages.last?.last?.content ?? ""
        #expect(latest.hasPrefix(tag))
        #expect(latest.utf16.count == 2_000, "nothing the student kept in the composer is cut by the server")
    }

    @Test("The composer note: nothing while short, a counter near the limit, a notice after a cut")
    func composerNote() {
        #expect(ComposerLimit.note(count: 100, limit: 2_000, wasCut: false) == nil)
        #expect(ComposerLimit.note(count: 1_799, limit: 2_000, wasCut: false) == nil)
        #expect(ComposerLimit.note(count: 1_850, limit: 2_000, wasCut: false)?.contains("2,000") == true)
        #expect(ComposerLimit.note(count: 2_000, limit: 2_000, wasCut: true)
                == "Only the first 2,000 characters will be sent.")
    }
}

// MARK: - Interrupted replies

@Suite("ChatViewModel interrupted replies")
@MainActor
struct InterruptedReplyTests {

    @Test("A relaunch after a failed send offers Retry, and Retry re-sends the question")
    func relaunchAfterFailureIsRetryable() async {
        let store = InMemoryChatStore()
        let failing = FakeChatClient()
        failing.outcome = .failure(APIError.connectionLost)
        let first = ChatViewModel(chatClient: failing, modeClient: FakeModeClient(),
                                  sessionIdProvider: { "s" }, store: store)
        first.draft = "Explain RLHF"
        first.send()
        await settle(first)

        let client = FakeChatClient()
        client.outcome = .events([reply("RLHF is…")])
        let relaunched = ChatViewModel(chatClient: client, modeClient: FakeModeClient(),
                                       sessionIdProvider: { "s" }, store: store)
        #expect(relaunched.messages.map(\.role) == [.user])
        #expect(isRetryableFailure(relaunched.phase))

        relaunched.retry()
        await settle(relaunched)
        #expect(client.receivedMessages.count == 1)
        #expect(client.receivedMessages.first?.last?.content == "Explain RLHF")
        #expect(relaunched.messages.last?.content == "RLHF is…")
        #expect(relaunched.phase == .idle)
    }

    @Test("A resumed lesson ending on the student's turn is retryable and replays the whole lesson")
    func resumedLessonIsRetryable() async {
        let store = InMemoryChatStore()
        let convo = store.createCurriculumConversation()
        store.append(StoredMessage(id: UUID(), role: "assistant", content: "A token is… What is one?", createdAt: Date()), to: convo)
        store.append(StoredMessage(id: UUID(), role: "user", content: "a word piece", createdAt: Date()), to: convo)

        let client = FakeChatClient()
        client.outcome = .events([reply("Right.")])
        let model = ChatViewModel(chatClient: client, modeClient: FakeModeClient(),
                                  sessionIdProvider: { "s" }, store: store, hydrateOnInit: false)
        model.onLessonComplete = {}
        let resumed = await model.resumeLesson(conversationId: convo, starter: lessonStarter, lessonId: "u1_l1")
        #expect(resumed)
        #expect(isRetryableFailure(model.phase))

        model.retry()
        await settle(model)
        let wire = client.receivedMessages.last ?? []
        #expect(wire.map(\.role) == ["user", "assistant", "user"])
        #expect(wire.first?.content.hasPrefix(lessonStarter) == true)
        #expect(wire[1].content == "A token is… What is one?")
        #expect(wire.last?.content == "[CURRICULUM: Unit 1, Lesson 1] a word piece")
    }

    @Test("A thread ending on Merc's reply loads idle")
    func answeredThreadLoadsIdle() {
        let store = InMemoryChatStore()
        let convo = store.createConversation(mode: .socratic)
        store.append(StoredMessage(id: UUID(), role: "user", content: "hi", createdAt: Date()), to: convo)
        store.append(StoredMessage(id: UUID(), role: "assistant", content: "hello", createdAt: Date()), to: convo)
        let model = ChatViewModel(chatClient: FakeChatClient(), modeClient: FakeModeClient(),
                                  sessionIdProvider: { "s" }, store: store)
        #expect(model.phase == .idle)
    }

    @Test("A dropped stream keeps the text that had arrived in the failed bubble")
    func failureKeepsStreamedText() async {
        let client = ControllableChatClient()
        let model = ChatViewModel(chatClient: client, modeClient: FakeModeClient(), sessionIdProvider: { "s" })
        model.draft = "Hi"
        model.send()
        await client.emit(.delta(text: "Partial"))
        await client.emit(.delta(text: " answer"))
        await client.fail(with: APIError.connectionLost)
        await settle(model)

        #expect(model.messages.last?.content == "Partial answer")
        #expect(model.messages.last?.status == .failed(reason: APIError.connectionLost.userFacingMessage))
        #expect(isRetryableFailure(model.phase))
    }
}

// MARK: - Streaming

@Suite("ChatViewModel streaming deltas")
@MainActor
struct DeltaCoalescingTests {

    @Test("The first delta shows at once; a burst after it lands whole")
    func burstLandsWhole() async {
        let client = ControllableChatClient()
        let model = ChatViewModel(chatClient: client, modeClient: FakeModeClient(), sessionIdProvider: { "s" })
        model.draft = "Hi"
        model.send()

        await client.emit(.delta(text: "One"))
        await poll("first delta") { model.messages.last?.content == "One" }
        for piece in [" two", " three", " four"] { await client.emit(.delta(text: piece)) }
        await poll("burst flushed") { model.messages.last?.content == "One two three four" }

        await client.finish()
        await settle(model)
        #expect(model.messages.last?.content == "One two three four")
        #expect(model.messages.last?.status == .idle)
    }

    @Test("A pass marker split across deltas still completes a truncated lesson stream, and never shows")
    func splitPassMarker() async {
        let client = ControllableChatClient()
        let model = ChatViewModel(chatClient: client, modeClient: FakeModeClient(), sessionIdProvider: { "s" })
        var completions = 0
        model.onLessonComplete = { completions += 1 }
        model.beginLessonConversation(starter: lessonStarter, lessonId: "u1_l1")

        await client.emit(.delta(text: "Nice work.\n\n[LESSON"))
        await client.emit(.delta(text: "_COMPLETE]"))
        await client.finish()
        await settle(model)

        #expect(completions == 1)
        #expect(model.messages.last?.content == "Nice work.")
    }

    @Test("A split lesson marker is held back while it streams")
    func parserHoldsBackPartialLessonMarker() {
        let blocks = BlockParser.parse("Nice work.\n\n[LESSON")
        #expect(blocks == [.prose("Nice work.\n\n")])
        #expect(!BlockParser.plainText("Done. [TEST_PASS").contains("[TEST"))
    }
}

// MARK: - Lessons on the wire

@Suite("ChatViewModel lesson wire")
@MainActor
struct LessonWireTests {

    @Test("A lesson's second turn replays Merc's first reply after the hidden opener")
    func secondTurnKeepsFirstReply() async {
        let client = FakeChatClient()
        client.outcome = .events([reply("A token is a chunk of text. What's one?")])
        let model = ChatViewModel(chatClient: client, modeClient: FakeModeClient(), sessionIdProvider: { "s" })
        model.onLessonComplete = {}
        model.beginLessonConversation(starter: lessonStarter, lessonId: "u1_l1")
        await settle(model)

        client.outcome = .events([reply("Right.")])
        model.draft = "part of a word"
        model.send()
        await settle(model)

        let wire = client.receivedMessages.last ?? []
        #expect(wire.map(\.role) == ["user", "assistant", "user"])
        #expect(wire[1].content == "A token is a chunk of text. What's one?")
    }

    @Test("A long lesson keeps its opener inside the server's 40-message window")
    func longLessonKeepsOpener() async {
        let store = InMemoryChatStore()
        let convo = store.createCurriculumConversation()
        for index in 0..<45 {
            let role = index.isMultiple(of: 2) ? "assistant" : "user"
            store.append(StoredMessage(id: UUID(), role: role, content: "turn \(index)", createdAt: Date()), to: convo)
        }
        let client = FakeChatClient()
        client.outcome = .events([reply()])
        let model = ChatViewModel(chatClient: client, modeClient: FakeModeClient(),
                                  sessionIdProvider: { "s" }, store: store, hydrateOnInit: false)
        model.onLessonComplete = {}
        _ = await model.resumeLesson(conversationId: convo, starter: lessonStarter, lessonId: "u1_l1")

        model.draft = "one more"
        model.send()
        await settle(model)

        let wire = client.receivedMessages.last ?? []
        #expect(wire.count == 40)
        #expect(wire.first?.content.hasPrefix(lessonStarter) == true)
    }

    @Test("A lesson model won't send before its lesson starts")
    func noSendBeforeLessonStarts() async {
        let client = FakeChatClient()
        client.outcome = .events([reply()])
        let model = ChatViewModel(chatClient: client, modeClient: FakeModeClient(), sessionIdProvider: { "s" })
        model.awaitsLessonStart = true

        model.draft = "hello?"
        model.send()
        #expect(model.messages.isEmpty)
        #expect(client.receivedMessages.isEmpty)

        model.onLessonComplete = {}
        model.beginLessonConversation(starter: lessonStarter, lessonId: "u1_l1")
        await settle(model)
        model.send()
        await settle(model)
        #expect(client.receivedMessages.last?.first?.content.hasPrefix(lessonStarter) == true)
        #expect(client.receivedMessages.last?.last?.content.hasSuffix("hello?") == true)
    }
}

// MARK: - Photos

private final class GatedPreparer: ImagePreparing, @unchecked Sendable {
    let gate = DispatchSemaphore(value: 0)
    func prepare(imageData: Data, fileName: String?) throws -> APIClient.ImageUploadInput {
        gate.wait()
        return APIClient.ImageUploadInput(contentType: "image/jpeg", base64Data: "QUJD")
    }
}

private final class RecordingUploader: ImageUploading, @unchecked Sendable {
    private let lock = NSLock()
    private var _inputs: [APIClient.ImageUploadInput] = []
    var failuresLeft = 0
    var inputs: [APIClient.ImageUploadInput] { lock.withLock { _inputs } }

    func uploadImage(_ input: APIClient.ImageUploadInput, sessionId: String) async throws -> APIClient.ImageUploadResponse {
        let shouldFail: Bool = lock.withLock {
            _inputs.append(input)
            if failuresLeft > 0 { failuresLeft -= 1; return true }
            return false
        }
        if shouldFail { throw APIError.offline }
        return APIClient.ImageUploadResponse(id: "img_1", url: "/api/images/img_1", contentType: "image/jpeg",
                                             fileName: nil, size: 3, createdAt: "2026-09-27T00:00:00.000Z")
    }
}

private func pngData(width: Int, height: Int) throws -> Data {
    let context = try #require(CGContext(
        data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ))
    context.setFillColor(CGColor(red: 0.2, green: 0.4, blue: 0.8, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    let image = try #require(context.makeImage())
    let out = NSMutableData()
    let destination = try #require(CGImageDestinationCreateWithData(out, UTType.png.identifier as CFString, 1, nil))
    CGImageDestinationAddImage(destination, image, nil)
    #expect(CGImageDestinationFinalize(destination))
    return out as Data
}

@Suite("ChatViewModel photo preparation")
@MainActor
struct PhotoPreparationTests {

    @Test("The preview is downsampled to at most 840 px on its longest edge")
    func previewIsDownsampled() throws {
        let image = try ChatImage.prepare(try pngData(width: 3_000, height: 2_000), preparer: JPEGImagePreparer())
        let preview = try #require(image.preview)
        #expect(max(preview.width, preview.height) <= ChatImage.previewMaxPixelSize)
        #expect(max(preview.width, preview.height) == 840)
        #expect(image.upload.contentType == "image/jpeg")
    }

    @Test("A photo still preparing can't be sent; once ready it can")
    func sendWaitsForPreparation() async {
        let preparer = GatedPreparer()
        let client = FakeChatClient()
        client.outcome = .events([reply()])
        let model = ChatViewModel(chatClient: client, modeClient: FakeModeClient(), sessionIdProvider: { "s" },
                                  imageUploader: RecordingUploader(), preparer: preparer)
        model.attachImage(data: Data([0x01]))
        #expect(model.isPreparingAttachment)

        model.draft = "what's this?"
        model.send()
        #expect(model.messages.isEmpty)

        preparer.gate.signal()
        await poll("prepared") { model.pendingImage != nil }
        model.send()
        await settle(model)
        #expect(client.receivedImageIds.last == "img_1")
    }

    @Test("Retry re-uploads the prepared photo; the original bytes aren't needed")
    func retryReusesPreparedUpload() async {
        let uploader = RecordingUploader()
        uploader.failuresLeft = 1
        let client = FakeChatClient()
        client.outcome = .events([reply()])
        let model = ChatViewModel(chatClient: client, modeClient: FakeModeClient(), sessionIdProvider: { "s" },
                                  imageUploader: uploader, preparer: JPEGImagePreparer())
        model.attachImage(data: (try? pngData(width: 400, height: 300)) ?? Data())
        await poll("prepared") { model.pendingImage != nil }
        let prepared = model.pendingImage

        model.send()
        await settle(model)
        #expect(isRetryableFailure(model.phase))

        model.retry()
        await settle(model)
        #expect(model.phase == .idle)
        #expect(uploader.inputs.count == 2)
        #expect(uploader.inputs.first == uploader.inputs.last)
        #expect(model.messages.first?.image === prepared)
    }

    @Test("An unreadable pick says why in the composer instead of failing the send")
    func unreadablePickSurfacesError() async {
        let model = ChatViewModel(chatClient: FakeChatClient(), modeClient: FakeModeClient(),
                                  sessionIdProvider: { "s" }, preparer: JPEGImagePreparer())
        model.attachImage(data: Data([0x01, 0x02]))
        await poll("prepared") { !model.isPreparingAttachment }
        #expect(model.pendingImage == nil)
        #expect(model.attachmentError == ImagePreparationError.unreadableImage.userMessage)

        model.clearAttachment()
        #expect(model.attachmentError == nil)
    }
}

// MARK: - Rendering

@Suite("Chat rendering inputs")
@MainActor
struct ChatRenderingTests {

    @Test("Bubbles compare by content, not by their closures")
    func bubbleEquality() {
        let message = ChatMessage(role: .assistant, content: "Hello")
        let a = MessageBubbleView(message: message, onReport: { _ in })
        let b = MessageBubbleView(message: message, onReport: { _ in print("different closure") })
        #expect(a == b)

        var edited = message
        edited.content = "Hello, world"
        #expect(a != MessageBubbleView(message: edited))
        #expect(a != MessageBubbleView(message: message, avatarActivity: .aiSpeaking))
        #expect(a != MessageBubbleView(message: message, avatarIdleLife: false))
    }

    @Test("The coach's progress line follows the share of the unit done")
    func coachProgressCopy() {
        #expect(CurriculumLessonView.progressCopy(completed: 1, total: 4) == "Nice start. You've got the core idea.")
        #expect(CurriculumLessonView.progressCopy(completed: 2, total: 4) == "Halfway there — keep it going.")
        #expect(CurriculumLessonView.progressCopy(completed: 3, total: 4) == "Almost done — one lesson to go.")
        #expect(CurriculumLessonView.progressCopy(completed: 2, total: 5) == "2 down, 3 to go.")
        #expect(CurriculumLessonView.progressCopy(completed: 5, total: 5).hasPrefix("Unit complete"))
    }
}
