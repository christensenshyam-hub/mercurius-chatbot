import Foundation
import SwiftData
import NetworkingKit

/// Persisted conversation — a single chronological chat session,
/// scoped to one `ChatMode` for its entire lifetime.
///
/// Mode immutability is a product invariant: a Debate conversation
/// stays Debate forever. Switching modes opens a different
/// conversation; it never silently mutates the active one.
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

    /// `ChatMode.rawValue` of the mode this conversation lives in.
    /// Stored as a raw string so unknown / future modes don't crash
    /// hydration — `ChatMode(rawValue:)` validates at the boundary.
    ///
    /// The default value is what SwiftData's lightweight migration
    /// stamps onto records that pre-date this column (i.e., users
    /// upgrading from a build before mode-scoped conversations).
    /// Socratic was the only experience pre-multi-session, so it's
    /// the correct default.
    public var mode: String = ChatMode.socratic.rawValue

    public var createdAt: Date
    public var updatedAt: Date

    @Relationship(deleteRule: .cascade, inverse: \MessageRecord.conversation)
    public var messages: [MessageRecord]

    public init(
        id: UUID = UUID(),
        mode: ChatMode,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.mode = mode.rawValue
        self.createdAt = createdAt
        self.updatedAt = createdAt
        self.messages = []
    }
}
