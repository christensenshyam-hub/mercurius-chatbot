import Foundation

// The crisis guard: which replies in a thread follow a crisis line. The Mac
// draws those replies plainly (Night Studio), and on both the Mac and the
// iPhone, Lesson 1.1's interactive never sits in such a thread. Pure and
// tested (NightReplyTextTests, TokenizerInteractiveTests).

enum LessonCrisisGuard {
    /// The server's own crisis-reply signal (server.js CRISIS_RESOURCE_RE):
    /// 988 or 741741 as a whole word. On the Mac a reply that carries a
    /// crisis line is drawn as plain reading text: no Your turn card, no
    /// source chips, no serif, no wash. Calm beats styled. On both, no
    /// interactive comes near it (`LessonInteractiveAnchor`).
    static func applies(to reply: String) -> Bool {
        reply.range(of: #"\b988\b|\b741741\b"#, options: .regularExpression) != nil
    }

    /// The thread's replies drawn plainly: once a reply in the thread carried
    /// a crisis line, it and every reply after it. Merc's follow-ups there
    /// rarely repeat the numbers, but the safety core says not to resume
    /// tutoring, so no Your turn card, chip or card frames them either. A
    /// new thread starts clear.
    static func guardedReplies(in messages: [ChatMessage]) -> Set<UUID> {
        guard let first = messages.firstIndex(where: { $0.role == .assistant && applies(to: $0.content) }) else {
            return []
        }
        return Set(messages[first...].filter { $0.role == .assistant }.map(\.id))
    }
}

/// `LessonCrisisGuard.guardedReplies`, worked out once per change of the
/// thread (the list asks for every row, on every streamed delta).
@MainActor
final class LessonCrisisIndex {
    private var ids: [UUID] = []
    private var lengths: [Int] = []
    private var cached: Set<UUID> = []

    func guardedReplies(in messages: [ChatMessage]) -> Set<UUID> {
        let newIds = messages.map(\.id)
        let newLengths = messages.map { $0.content.utf8.count }
        if newIds == ids && newLengths == lengths { return cached }
        ids = newIds
        lengths = newLengths
        cached = LessonCrisisGuard.guardedReplies(in: messages)
        return cached
    }
}
