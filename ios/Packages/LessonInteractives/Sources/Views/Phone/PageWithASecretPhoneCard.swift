#if os(iOS)
import SwiftUI

/// The Page with a Secret on the iPhone (u8_l1): today's lesson design, the
/// night-sky island Lesson 1.1's card uses, in the lesson's thread after
/// the first teach reply's example part.
///
/// The run stacks: the task, the loop (a ring with "Now" beside it; a
/// numbered list at the accessibility sizes), then each step as it is
/// reached, with the made-up page inline at step 3 (never a sheet, so focus
/// and the check's targets stay put) and the prediction under it. Next
/// can't leave the page until a guess is locked, and the toggle "What you
/// see | What the agent reads" stays off until then too. Reaching step 6
/// reveals.
///
/// - Targets are 44 pt or taller, and each pick, step and toggle gives a
///   selection haptic (the shared controls).
/// - Dynamic Type to AX5: the ring, the icons and the side-by-side layouts
///   go (decoration); every word stays, and nothing scrolls sideways.
/// - Reduce Motion: the ring never turns, the lit phase crossfades, new
///   steps fade in without sliding, the page's views crossfade.
/// - Increase Contrast and Reduce Transparency: solid edges, no glows.
/// - VoiceOver: the title says the state in one sentence; each step's
///   eyebrow is a header; each step is announced as it arrives ("Step 4 of
///   6: Plan. New line: …"); the page is one element, and once a guess is
///   locked it says the hidden line in either view.
public struct PageWithASecretPhoneCard: View {
    private let context: InteractiveCardContext

    public init(_ context: InteractiveCardContext) {
        self.context = context
    }

    public var body: some View {
        let state = context.state { PageWithASecretState(spoiled: $0.spoiled) }
        InteractiveCardShell(id: context.id, title: PageWithASecretCopy.title,
                             summary: PageWithASecretCopy.accessibilitySummary(state.progress),
                             compactLine: PageWithASecretCopy.compactLine) {
            PageWithASecretBody(state: state, twoColumns: false)
        }
    }
}
#endif
