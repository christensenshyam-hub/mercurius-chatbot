import Foundation
import SwiftData

/// Persisted chat message. `role` is stored as a raw string ("user"
/// or "assistant") to match the server contract and stay forward-
/// compatible if we ever add more roles.
@Model
public final class MessageRecord {
    @Attribute(.unique) public var id: UUID
    public var role: String
    public var content: String
    public var createdAt: Date

    public var conversation: ConversationRecord?

    public init(
        id: UUID = UUID(),
        role: String,
        content: String,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.role = role
        self.content = content
        self.createdAt = createdAt
    }
}
