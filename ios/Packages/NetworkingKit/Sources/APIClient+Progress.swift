import Foundation

// MARK: - Wire enums (mirror of lib/schemas.js ProgressItemType / ProgressStatus)

/// What a synced progress item refers to. Raw values are the server's
/// `type` enum for `PUT /api/progress/:sessionId`.
public enum ProgressItemType: String, Codable, Sendable {
    case lesson
    case unit
}

/// The statuses the client can push. The server ranks them forward-only
/// (`completed` < `mastered`) and never downgrades a stored item.
public enum ProgressStatus: String, Codable, Sendable {
    case completed
    case mastered
}

// MARK: - DTOs

/// One item of server-held progress. `status` stays a raw `String` so a
/// status this build does not know cannot fail the whole snapshot decode —
/// callers compare against `ProgressStatus` raw values.
public struct ProgressItemDTO: Decodable, Sendable, Equatable {
    public let id: String
    public let status: String
    /// When the server first stored this status. Decoded leniently: the
    /// server's BIGINT `updated_at` arrives as epoch milliseconds (a number
    /// from SQLite, a string from node-postgres' int8 handling), and the
    /// decoder also accepts epoch seconds and ISO 8601 text. Anything else
    /// degrades to nil rather than failing the decode.
    public let updatedAt: Date?

    public init(id: String, status: String, updatedAt: Date?) {
        self.id = id
        self.status = status
        self.updatedAt = updatedAt
    }

    private enum CodingKeys: String, CodingKey {
        case id, status, updatedAt
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        status = try container.decode(String.self, forKey: .status)
        updatedAt = Self.date(in: container, forKey: .updatedAt)
    }

    private static func date(
        in container: KeyedDecodingContainer<CodingKeys>,
        forKey key: CodingKeys
    ) -> Date? {
        if let number = try? container.decode(Double.self, forKey: key) {
            return epochDate(number)
        }
        if let text = try? container.decode(String.self, forKey: key) {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if let number = Double(trimmed) {
                return epochDate(number)
            }
            return isoDate(trimmed)
        }
        return nil
    }

    /// Epoch milliseconds or seconds. 1e11 seconds is the year 5138, so any
    /// value at or past it can only be milliseconds.
    private static func epochDate(_ value: Double) -> Date? {
        guard value.isFinite, value > 0 else { return nil }
        let seconds = value >= 1e11 ? value / 1000 : value
        return Date(timeIntervalSince1970: seconds)
    }

    private static func isoDate(_ text: String) -> Date? {
        // Formatters are built per call: ISO8601DateFormatter is not
        // Sendable, and a snapshot holds at most a few dozen items.
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = withFraction.date(from: text) { return date }
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        return plain.date(from: text)
    }
}

/// `GET /api/progress/:sessionId` (and the `PUT` reply): the merged state
/// the server holds for a session. Empty for a session it has never seen.
public struct ProgressSnapshotDTO: Decodable, Sendable, Equatable {
    /// The highest `curriculumVersion` any stored item was written under;
    /// nil when the server holds nothing for this session.
    public let curriculumVersion: Int?
    public let lessons: [ProgressItemDTO]
    public let units: [ProgressItemDTO]

    public init(curriculumVersion: Int?, lessons: [ProgressItemDTO] = [], units: [ProgressItemDTO] = []) {
        self.curriculumVersion = curriculumVersion
        self.lessons = lessons
        self.units = units
    }

    private enum CodingKeys: String, CodingKey {
        case curriculumVersion, lessons, units
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let number = try? container.decodeIfPresent(Int.self, forKey: .curriculumVersion) {
            curriculumVersion = number
        } else if let text = try? container.decode(String.self, forKey: .curriculumVersion) {
            curriculumVersion = Int(text.trimmingCharacters(in: .whitespacesAndNewlines))
        } else {
            curriculumVersion = nil
        }
        lessons = try container.decodeIfPresent([ProgressItemDTO].self, forKey: .lessons) ?? []
        units = try container.decodeIfPresent([ProgressItemDTO].self, forKey: .units) ?? []
    }
}

/// One item the client pushes. Encodes to exactly `{ id, type, status }` —
/// the server's item schema is strict, so no other key may ever appear.
public struct ProgressPutItem: Encodable, Sendable, Equatable {
    public let id: String
    public let type: ProgressItemType
    public let status: ProgressStatus

    public init(id: String, type: ProgressItemType, status: ProgressStatus) {
        self.id = id
        self.type = type
        self.status = status
    }
}

// MARK: - Client

extension APIClient {
    /// Server-side caps on `PUT /api/progress/:sessionId` (Zod `.max(200)`
    /// on `items`, `1 … INT4_MAX` on `curriculumVersion`). The whole
    /// curriculum is ~43 items, so the item cap only matters if a future
    /// curriculum outgrows it.
    static let progressItemLimit = 200
    static let progressVersionRange = 1...2_147_483_647

    /// Read the progress the server holds for a session. Empty arrays for
    /// a session it has never seen; 400 (`invalid_session`) for a bad id.
    public func fetchProgress(sessionId: String) async throws -> ProgressSnapshotDTO {
        try await send(
            method: "GET",
            path: "/api/progress/\(sessionId)",
            body: Optional<Empty>.none
        )
    }

    /// Push the items this device holds and receive the merged state back.
    /// The server merges forward-only (`completed` < `mastered`) and never
    /// deletes, so pushing the full local snapshot is always safe.
    ///
    /// An empty `items` is a server no-op that would only echo the merged
    /// state, so it is answered with a plain GET instead. Items past the
    /// server's cap of 200 are dropped from the request (never a 400); an
    /// out-of-range `curriculumVersion` is refused before any request is
    /// made, because the server would reject the whole push.
    public func putProgress(
        sessionId: String,
        curriculumVersion: Int,
        items: [ProgressPutItem]
    ) async throws -> ProgressSnapshotDTO {
        guard !items.isEmpty else {
            return try await fetchProgress(sessionId: sessionId)
        }
        guard Self.progressVersionRange.contains(curriculumVersion) else {
            throw APIError.invalidRequest(
                reason: "curriculumVersion \(curriculumVersion) is outside 1…\(Self.progressVersionRange.upperBound)"
            )
        }
        struct Body: Encodable {
            let curriculumVersion: Int
            let items: [ProgressPutItem]
        }
        return try await send(
            method: "PUT",
            path: "/api/progress/\(sessionId)",
            body: Body(
                curriculumVersion: curriculumVersion,
                items: Array(items.prefix(Self.progressItemLimit))
            )
        )
    }
}

/// Narrow protocol so the sync coordinator depends on this instead of the
/// concrete `APIClient` and tests can inject a stub — mirrors `Reporting`.
public protocol ProgressSyncing: Sendable {
    func fetchProgress(sessionId: String) async throws -> ProgressSnapshotDTO
    func putProgress(
        sessionId: String,
        curriculumVersion: Int,
        items: [ProgressPutItem]
    ) async throws -> ProgressSnapshotDTO
}

extension APIClient: ProgressSyncing {}
