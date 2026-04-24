import Testing
import NetworkingKit
@testable import ChatFeature

/// Contract tests for `ModePromptProvider`. The provider is pure
/// data, so these tests are cheap and assert the invariants every
/// mode list must satisfy:
///
/// - Length: 3–5 prompts per the product spec.
/// - Distinctness: no duplicate strings within a single mode (a copy-
///   paste error would make one chip silently shadow another).
/// - Coverage: every `ChatMode.allCases` resolves to a non-empty list
///   (would catch a missing case entry the moment a new mode lands).
/// - Mode-uniqueness: prompt sets don't collide across modes — i.e.,
///   each mode contributes at least one prompt no other mode has.
///   Without this, "switching modes updates prompts" wouldn't be
///   visible to the user.
///
/// Concrete-content assertions (e.g. "Socratic includes 'How does an
/// LLM actually work?'") live in the UI test that anchors on those
/// strings, not here. Keeping content-vs-shape separated means
/// editing prompt copy doesn't churn this file.
@Suite("ModePromptProvider")
struct ModePromptProviderTests {

    @Test("Every ChatMode resolves to a 3-to-5-prompt list")
    func everyModeHasReasonableLength() {
        for mode in ChatMode.allCases {
            let prompts = ModePromptProvider.prompts(for: mode)
            #expect(
                (3...5).contains(prompts.count),
                "Mode \(mode) returned \(prompts.count) prompts; expected 3–5"
            )
        }
    }

    @Test("No prompt is duplicated within a single mode")
    func promptsAreDistinctWithinMode() {
        for mode in ChatMode.allCases {
            let prompts = ModePromptProvider.prompts(for: mode)
            #expect(
                Set(prompts).count == prompts.count,
                "Mode \(mode) has duplicate prompts: \(prompts)"
            )
        }
    }

    @Test("Each mode contributes at least one prompt no other mode has")
    func modeListsAreDistinctFromEachOther() {
        let allLists = ChatMode.allCases.map { ($0, Set(ModePromptProvider.prompts(for: $0))) }

        for (mode, prompts) in allLists {
            // Union of every OTHER mode's prompts.
            let othersUnion = allLists
                .filter { $0.0 != mode }
                .reduce(Set<String>()) { $0.union($1.1) }

            // At least one of `mode`'s prompts must not be in any other
            // mode's list — otherwise switching to this mode is
            // invisible to the user.
            let unique = prompts.subtracting(othersUnion)
            #expect(
                !unique.isEmpty,
                "Mode \(mode) has no prompts unique to it; switching to it wouldn't change the visible chips"
            )
        }
    }

    @Test("Prompts contain no unfilled placeholder tokens like [topic]")
    func promptsHaveNoUnfilledPlaceholders() {
        // Tap-to-send is the current EmptyChatView behavior, so a
        // chip with "[topic]" would send the literal string and
        // confuse the model. Catch any future regression.
        for mode in ChatMode.allCases {
            for prompt in ModePromptProvider.prompts(for: mode) {
                #expect(
                    !prompt.contains("[") && !prompt.contains("]"),
                    "Mode \(mode) has prompt with unfilled placeholder: \(prompt)"
                )
            }
        }
    }
}
