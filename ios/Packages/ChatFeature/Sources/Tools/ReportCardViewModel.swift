import Foundation
import Observation
import NetworkingKit

@MainActor
@Observable
public final class ReportCardViewModel {

    public enum Phase: Equatable, Sendable {
        case loading
        case ready(ReportCard)
        case failed(reason: String, isRetryable: Bool)
    }

    public private(set) var phase: Phase = .loading

    private let tools: ToolsProviding
    private let sessionIdProvider: @Sendable () throws -> String

    public init(
        tools: ToolsProviding,
        sessionIdProvider: @escaping @Sendable () throws -> String
    ) {
        self.tools = tools
        self.sessionIdProvider = sessionIdProvider
    }

    public func load() async {
        phase = .loading
        do {
            let sid = try sessionIdProvider()
            let card = try await tools.generateReportCard(sessionId: sid)
            phase = .ready(card)
        } catch let error as APIError {
            phase = .failed(
                reason: error.userFacingMessage,
                isRetryable: error.isRetryable
            )
        } catch {
            phase = .failed(
                reason: "Couldn't generate a report card. Try again.",
                isRetryable: true
            )
        }
    }
}
