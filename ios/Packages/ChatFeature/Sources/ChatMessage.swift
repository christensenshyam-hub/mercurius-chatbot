import Foundation
import NetworkingKit

/// In-memory chat message model used by the view layer. Distinct from
/// `ChatMessageDTO` (wire format) so the UI layer isn't coupled to
/// server JSON shape.
public struct ChatMessage: Identifiable, Equatable, Sendable {
    public enum Role: String, Sendable {
        case user
        case assistant
    }

    /// Per-message state for progressive disclosure during streaming.
    public enum Status: Equatable, Sendable {
        /// Normal, no streaming in progress.
        case idle
        /// Assistant message is receiving deltas.
        case streaming
        /// A request failed. Error message is shown under the bubble.
        case failed(reason: String)
    }

    public let id: UUID
    public let role: Role
    public var content: String
    public let createdAt: Date
    public var status: Status

    public init(
        id: UUID = UUID(),
        role: Role,
        content: String,
        createdAt: Date = Date(),
        status: Status = .idle
    ) {
        self.id = id
        self.role = role
        self.content = content
        self.createdAt = createdAt
        self.status = status
    }

    /// Map to the DTO sent to the server.
    public var dto: ChatMessageDTO {
        ChatMessageDTO(role: role.rawValue, content: content)
    }
}
