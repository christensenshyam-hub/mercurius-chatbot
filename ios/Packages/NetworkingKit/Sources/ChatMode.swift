import Foundation

/// The four teaching modes Mercurius supports.
///
/// The raw string matches the server contract (`mode` field in
/// `POST /api/chat` and `POST /api/mode`).
public enum ChatMode: String, CaseIterable, Sendable, Identifiable, Codable {
    case socratic
    case direct
    case debate
    case discussion

    public var id: String { rawValue }

    /// User-facing display name.
    public var displayName: String {
        switch self {
        case .socratic: return "Socratic"
        case .direct: return "Direct"
        case .debate: return "Debate"
        case .discussion: return "Discussion"
        }
    }

    /// One-line description for accessibility and optional UI hinting.
    public var blurb: String {
        switch self {
        case .socratic: return "Questions that push your thinking."
        case .direct: return "Substantive answers, still critical."
        case .debate: return "Mercurius argues a position. Your move."
        case .discussion: return "Your reasoning, scored."
        }
    }

    /// Whether this mode requires passing the Socratic comprehension
    /// test before the server will allow it.
    public var requiresUnlock: Bool {
        self == .direct
    }
}
