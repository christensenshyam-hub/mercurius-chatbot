import Foundation
import SwiftData

/// Persisted conversation — a single chronological chat session.
///
/// Relationship rule: deleting a conversation cascades to its
/// messages. Messages are sorted manually by `createdAt` at read
/// time because SwiftData's sort-on-relationship support is still
/// unreliable on iOS 17.
@Model
public final class ConversationRecord {
    /// Stable identifier. Using `UUID` rather than SwiftData's
    /// persistentIdentifier because it keeps DTOs / test fixtures
    /// decoupled from the persistence layer.
    @Attribute(.unique) public var id: UUID
    public var createdAt: Date
    public var updatedAt: Date

    @Relationship(deleteRule: .cascade, inverse: \MessageRecord.conversation)
    public var messages: [MessageRecord]

    public init(
        id: UUID = UUID(),
        createdAt: Date = Date()
    ) {
        self.id = id
        self.createdAt = createdAt
        self.updatedAt = createdAt
        self.messages = []
    }
}
