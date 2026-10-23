#if DEBUG
import Testing
import Foundation
@testable import ChatFeature
@testable import NetworkingKit

/// The DEBUG `-LessonReplayNetwork` scenarios go through the real APIClient
/// and ChatViewModel, so their screenshots show what a student would see.
/// One shared URLProtocol scenario, so the suite runs serially.
@Suite("DEBUG network scenarios", .serialized)
@MainActor
struct NetworkScenarioPreviewTests {

    init() { NetworkScenarioProtocol.delay = 0 }

    private func failure(for scenario: NetworkScenario) async throws -> (reason: String, retryable: Bool) {
        let model = ChatViewModel(
            chatClient: scenario.makeClient(),
            modeClient: NoModeChange(),
            sessionIdProvider: { "debug-test" },
            hydrateOnInit: false
        )
        model.draft = "Hello"
        model.send()
        let deadline = ContinuousClock.now.advanced(by: .seconds(10))
        while ContinuousClock.now < deadline {
            if case .failed(let reason, let retryable) = model.phase {
                return (reason.replacingOccurrences(of: "\u{202F}", with: " "), retryable)
            }
            try await Task.sleep(for: .milliseconds(10))
        }
        Issue.record("\(scenario) never failed (phase: \(model.phase))")
        return ("", false)
    }

    @Test("Each scenario ends in the failure its screenshot shows")
    func outcomes() async throws {
        let blocked = try await failure(for: .blockPage)
        #expect(blocked.reason == APIError.unreachableOnThisNetwork.userFacingMessage)
        #expect(blocked.retryable)

        let daily = try await failure(for: .dailyLimit)
        #expect(daily.reason.hasPrefix("You've used today's lesson turns. Try again "))
        #expect(!daily.retryable)

        let newSessions = try await failure(for: .newSessions)
        #expect(newSessions.reason.hasPrefix(
            "Too many new sessions from this network today. Switch to cellular data and try again, or come back "))
        #expect(newSessions.retryable)

        #expect(try await failure(for: .paused) == ("Mercurius is temporarily paused — please try again soon.", false))
        #expect(try await failure(for: .spendCap) == ("Daily usage limit reached — please try again tomorrow.", false))
        #expect(try await failure(for: .busy)
            == ("Mercurius is helping a lot of students right now. Try again in a minute.", true))
    }
}

private struct NoModeChange: ModeChanging {
    func changeMode(to mode: ChatMode, sessionId: String) async throws -> APIClient.ModeChange {
        throw APIError.unknown(underlying: "unused")
    }
}
#endif
