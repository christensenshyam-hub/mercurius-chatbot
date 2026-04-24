import Foundation
import NetworkingKit

/// Mode-keyed starter prompts surfaced in `EmptyChatView`. Each mode
/// gets its own short list of student-facing prompts that match the
/// mode's pedagogical posture:
///
/// - **Socratic** — exploratory, mechanism-curious. The default
///   Mercurius experience.
/// - **Direct** — fact-fast, definitional. For when a student knows
///   what they want and wants it concise.
/// - **Debate** — adversarial, position-taking. The student picks a
///   side; Mercurius pushes the other.
/// - **Discussion** — collaborative, perspective-taking. Both parties
///   are exploring, not teacher-student.
///
/// Edit prompts here; views pull from `prompts(for:)` so changes
/// propagate without view edits. New modes added to `ChatMode` will
/// fail compilation until they have an entry, which is the right
/// failure mode — silent fallback to a generic list would mask a
/// missing mode.
public struct ModePromptProvider {

    // MARK: - Per-mode prompts
    //
    // Each list is intentionally concrete (no "[topic]" placeholders).
    // Tapping a chip in EmptyChatView sends the prompt immediately, so
    // a placeholder would be sent literally and confuse the model. If
    // we ever change tap behavior to "fill, then user edits, then
    // sends," placeholders become viable — until then, prompts must
    // be self-contained and ready to fire.

    /// Default mode. Open-ended, mechanism-focused — invites the
    /// student to think about how AI works, not just what it produces.
    /// The first two strings are anchors for `MercuriusUITests/
    /// testStarterPromptsPresentInEmptyChat` — keep them stable.
    public static let socraticPrompts: [String] = [
        "How does an LLM actually work?",
        "Is AI biased? Where does the bias come from?",
        "When should I NOT use AI?",
        "How do I write a better prompt?",
    ]

    /// Locked until the student demonstrates critical thinking; the
    /// prompts here are still accurate previews of the mode's
    /// posture for users who haven't unlocked it yet.
    public static let directPrompts: [String] = [
        "Define what an LLM is in plain language.",
        "List the main risks of using AI for homework.",
        "Summarize how training data shapes a model.",
        "Compare AI 'thinking' vs. human thinking.",
    ]

    /// Adversarial. The student takes a position; Mercurius pushes
    /// back. Prompts here name the position the student wants to
    /// defend or attack — Mercurius will argue the opposite.
    public static let debatePrompts: [String] = [
        "Argue against the claim that AI will replace teachers.",
        "Make the strongest case that AI is overhyped.",
        "Defend the view that students should never use AI for essays.",
        "Stress-test this: AI helps everyone learn faster.",
    ]

    /// Peer-to-peer exploration. Mercurius treats the student as a
    /// thinking partner. Prompts invite a back-and-forth rather than
    /// a lecture.
    public static let discussionPrompts: [String] = [
        "Walk me through what makes a question 'good' for an LLM.",
        "What perspectives matter most when thinking about AI bias?",
        "Why does it matter whether I learn to code if AI can do it?",
        "Help me think about when AI confidence equals AI accuracy.",
    ]

    // MARK: - Lookup

    /// The starter-prompt list for `mode`. Always non-empty — every
    /// `ChatMode.allCases` is covered.
    public static func prompts(for mode: ChatMode) -> [String] {
        switch mode {
        case .socratic:   return socraticPrompts
        case .direct:     return directPrompts
        case .debate:     return debatePrompts
        case .discussion: return discussionPrompts
        }
    }
}
