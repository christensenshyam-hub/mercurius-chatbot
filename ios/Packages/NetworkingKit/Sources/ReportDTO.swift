import Foundation

/// Why a student is reporting a response. Raw values are the server's
/// `reason` enum for `POST /api/report`.
public enum ReportReason: String, Codable, CaseIterable, Sendable {
    case wrong
    case harmful
    case offTopic = "off_topic"
    case other

    /// Label for the reason picker.
    public var title: String {
        switch self {
        case .wrong: return "Wrong or misleading"
        case .harmful: return "Harmful or inappropriate"
        case .offTopic: return "Off topic"
        case .other: return "Something else"
        }
    }
}

/// Where a report came from, so reviewers can reproduce it. Matches the
/// server's strict `context` object: only these keys, and optional ones are
/// omitted from the JSON (never `null`) when nil.
///
/// - `surface`: `"chat"` or `"lesson"`.
/// - `mode`: the chat mode's raw value (≤ 32 chars).
/// - `lessonId`: the curriculum lesson, on the lesson surface (≤ 64 chars).
/// - `appVersion`: `CFBundleShortVersionString` (≤ 32 chars).
public struct ReportContext: Codable, Sendable, Equatable {
    public var surface: String
    public var mode: String?
    public var lessonId: String?
    public var appVersion: String?

    public init(
        surface: String,
        mode: String? = nil,
        lessonId: String? = nil,
        appVersion: String? = nil
    ) {
        self.surface = surface
        self.mode = mode
        self.lessonId = lessonId
        self.appVersion = appVersion
    }
}
