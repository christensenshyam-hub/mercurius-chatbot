import Foundation
import NetworkingKit

// MARK: - ModeDescription

/// First-time explainer copy for a single `ChatMode`. Shown the first
/// time a user taps that mode's pill; suppressed thereafter via
/// `ModeDescriptionStore` which persists a per-mode "seen" flag.
///
/// Copy is kept deliberately short — three beats (purpose, when,
/// example) — because the goal is a quick orientation, not a lesson.
/// If a student has to read a paragraph to understand the mode, the
/// mode name is wrong.
public struct ModeDescription: Identifiable, Equatable, Sendable {
    public let mode: ChatMode
    public let title: String
    /// One-sentence framing of what the mode does.
    public let purpose: String
    /// One-sentence guidance on when to use it.
    public let whenToUse: String
    /// A concrete example prompt a student could paste into the chat.
    public let example: String
    /// Optional extra note (e.g. "This mode is currently locked")
    /// that appears below the example when non-nil.
    public let footnote: String?

    public var id: ChatMode { mode }

    public var storageKey: String {
        ModeDescriptionStore.storageKey(for: mode)
    }
}

// MARK: - Catalog

extension ModeDescription {
    /// Static, hand-written copy for every `ChatMode.allCases`.
    /// Declared per-mode rather than computed so the strings are
    /// easy to find and localize later.
    public static let catalog: [ChatMode: ModeDescription] = [
        .socratic: ModeDescription(
            mode: .socratic,
            title: "Socratic",
            purpose: "Mercurius asks questions back instead of handing you the answer.",
            whenToUse: "Use this when you want to learn how to think through a problem, not just get a result.",
            example: "What's the difference between correlation and causation?",
            footnote: nil
        ),
        .direct: ModeDescription(
            mode: .direct,
            title: "Direct",
            purpose: "Mercurius answers your question straight — no back-and-forth.",
            whenToUse: "Use this when you already understand the topic and just need the information fast.",
            example: "Give me the formula for exponential decay.",
            footnote: "Direct is locked until you demonstrate critical thinking in Socratic Mode."
        ),
        .debate: ModeDescription(
            mode: .debate,
            title: "Debate",
            purpose: "Mercurius argues back. You take a side, it pushes the other.",
            whenToUse: "Use this when you want to stress-test an argument or practice defending a position.",
            example: "AI will take all our jobs — change my mind.",
            footnote: nil
        ),
        .discussion: ModeDescription(
            mode: .discussion,
            title: "Discussion",
            purpose: "Mercurius treats you as an intellectual peer — exploring ideas together, not teaching you.",
            whenToUse: "Use this when you want a thoughtful conversation, not a lecture.",
            example: "What does it mean for a machine to 'understand' something?",
            footnote: nil
        ),
    ]

    /// Subscript-style accessor. Always returns a value because the
    /// catalog covers every `ChatMode.allCases` — nil would mean the
    /// catalog is stale and a crash at dev time is the right signal.
    public static func description(for mode: ChatMode) -> ModeDescription {
        guard let description = catalog[mode] else {
            fatalError("ModeDescription catalog is missing an entry for \(mode). Add one to `catalog` in ModeDescription.swift.")
        }
        return description
    }
}

// MARK: - Persistence

/// Persists the "has this user seen the description for this mode?"
/// flag per mode. Uses `UserDefaults.standard` so test launch args
/// like `-seenModeDescription.socratic YES` flip the flag via the
/// argument domain — same pattern as `-hasSeenOnboarding`.
///
/// Deliberately NOT an `ObservableObject`: the only consumer
/// (`ModeSelectorView`) reads the flag at the moment the user taps
/// a pill; it doesn't need to react to external changes. Keeping
/// this an `enum` with static methods avoids needless SwiftUI
/// publisher churn.
public enum ModeDescriptionStore {

    /// UserDefaults key where the per-mode flag lives. Public so UI
    /// tests can pass `-seenModeDescription.<mode> YES` as a launch
    /// argument and match the exact key the runtime reads.
    public static func storageKey(for mode: ChatMode) -> String {
        "seenModeDescription.\(mode.rawValue)"
    }

    /// One-shot launch-arg key that marks every mode seen at once.
    /// Set to `YES` by the UI test harness so existing tests don't
    /// have to dismiss a sheet on every first-mode tap. Read as a
    /// fallback during `hasSeen(...)`.
    public static let globalBypassKey = "seenAllModeDescriptions"

    public static func hasSeen(_ mode: ChatMode, defaults: UserDefaults = .standard) -> Bool {
        if defaults.bool(forKey: globalBypassKey) {
            return true
        }
        return defaults.bool(forKey: storageKey(for: mode))
    }

    public static func markSeen(_ mode: ChatMode, defaults: UserDefaults = .standard) {
        defaults.set(true, forKey: storageKey(for: mode))
    }
}
