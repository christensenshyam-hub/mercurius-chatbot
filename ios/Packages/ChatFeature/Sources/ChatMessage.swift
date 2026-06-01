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

    /// Local image bytes for an attached photo, shown inline in the bubble.
    /// In-memory only (not persisted), and never part of the wire `dto` — the
    /// image reaches the server out-of-band via the upload pipeline + the
    /// chat request's `imageId`.
    public var imageData: Data?

    public init(
        id: UUID = UUID(),
        role: Role,
        content: String,
        createdAt: Date = Date(),
        status: Status = .idle,
        imageData: Data? = nil
    ) {
        self.id = id
        self.role = role
        self.content = content
        self.createdAt = createdAt
        self.status = status
        self.imageData = imageData
    }

    /// Map to the DTO sent to the server. Text only — the image travels via the
    /// chat request's `imageId`, not the message body.
    public var dto: ChatMessageDTO {
        ChatMessageDTO(role: role.rawValue, content: content)
    }
}
