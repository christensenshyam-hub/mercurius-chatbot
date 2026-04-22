import Testing
import Foundation
@testable import ChatFeature
@testable import NetworkingKit

// MARK: - Fake mode client

final class FakeModeClient: ModeChanging, @unchecked Sendable {
    enum Outcome {
        case success(APIClient.ModeChange)
        case failure(Error)
    }
    var outcome: Outcome = .success(APIClient.ModeChange(mode: "socratic", unlocked: false))
    var calls: [(mode: ChatMode, sessionId: String)] = []

    func changeMode(to mode: ChatMode, sessionId: String) async throws -> APIClient.ModeChange {
        calls.append((mode, sessionId))
        switch outcome {
        case .success(let change): return change
        case .failure(let error): throw error
        }
    }
}

@MainActor
private func makeModel(
    chat: FakeChatClient = FakeChatClient(),
    mode: FakeModeClient = FakeModeClient(),
    sessionId: String = "test-session"
) -> ChatViewModel {
    ChatViewModel(
        chatClient: chat,
        modeClient: mode,
        sessionIdProvider: { sessionId }
    )
}

@Suite("ChatViewModel mode switching")
@MainActor
struct ChatViewModelModeTests {

    @Test("Starts in socratic mode and locked")
    func defaults() {
        let model = makeModel()
        #expect(model.currentMode == .socratic)
        #expect(!model.isUnlocked)
    }

    @Test("Switching to same mode is a no-op")
    func noOpSameMode() async {
        let mode = FakeModeClient()
        let model = makeModel(mode: mode)
        let result = await model.switchMode(to: .socratic)
        #expect(result == true)
        #expect(mode.calls.isEmpty)
    }

    @Test("Successful switch updates currentMode and clears inFlight")
    func successfulSwitch() async {
        let mode = FakeModeClient()
        mode.outcome = .success(.init(mode: "debate", unlocked: false))
        let model = makeModel(mode: mode)

        let result = await model.switchMode(to: .debate)

        #expect(result == true)
        #expect(model.currentMode == .debate)
        #expect(model.modeSwitchInFlight == nil)
        #expect(mode.calls.count == 1)
        #expect(mode.calls[0].mode == .debate)
        #expect(mode.calls[0].sessionId == "test-session")
    }

    @Test("Direct when locked is rejected client-side — no API call")
    func directLockedClientSide() async {
        let mode = FakeModeClient()
        let model = makeModel(mode: mode)

        let result = await model.switchMode(to: .direct)

        #expect(result == false)
        #expect(model.currentMode == .socratic)
        #expect(model.modeSwitchError != nil)
        #expect(mode.calls.isEmpty, "Should not even call the server")
    }

    @Test("Direct when unlocked is allowed and hits the server")
    func directUnlockedAllowed() async {
        let mode = FakeModeClient()
        mode.outcome = .success(.init(mode: "direct", unlocked: true))
        let model = makeModel(mode: mode)
        // Simulate prior unlock (normally comes from a streamed reply)
        model.unsafelyMarkUnlockedForTesting()

        let result = await model.switchMode(to: .direct)

        #expect(result == true)
        #expect(model.currentMode == .direct)
        #expect(mode.calls.count == 1)
    }

    @Test("Server 401 surfaces the 'complete the test' message")
    func serverRejects() async {
        let mode = FakeModeClient()
        mode.outcome = .failure(APIError.unauthorized)
        let model = makeModel(mode: mode)
        model.unsafelyMarkUnlockedForTesting()  // bypass client check

        let result = await model.switchMode(to: .direct)

        #expect(result == false)
        #expect(model.modeSwitchError != nil)
        #expect(model.currentMode == .socratic)
    }

    @Test("Transport error sets a retryable user-facing message")
    func transportError() async {
        let mode = FakeModeClient()
        mode.outcome = .failure(APIError.offline)
        let model = makeModel(mode: mode)

        let result = await model.switchMode(to: .debate)

        #expect(result == false)
        #expect(model.modeSwitchError == APIError.offline.userFacingMessage)
    }

    @Test("clearModeSwitchError resets the error")
    func clearError() async {
        let mode = FakeModeClient()
        mode.outcome = .failure(APIError.offline)
        let model = makeModel(mode: mode)
        _ = await model.switchMode(to: .debate)
        #expect(model.modeSwitchError != nil)
        model.clearModeSwitchError()
        #expect(model.modeSwitchError == nil)
    }
}

// MARK: - Test-only hook

@MainActor
private extension ChatViewModel {
    /// Forces `isUnlocked` true for test setup only. The production
    /// API only flips this flag via streamed `complete` events or the
    /// server's 200 response to `switchMode`.
    func unsafelyMarkUnlockedForTesting() {
        // We can't touch a private(set) property from an extension in
        // another file — so we reach in via the designated path: simulate
        // a mode-change server response that sets unlocked=true. But the
        // simplest test-only accessor is just a mutating helper that we
        // add here via a package-scoped test hook.
        //
        // Implementation lives in ChatViewModel+TestSupport.swift.
        _testing_markUnlocked()
    }
}
