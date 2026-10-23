#if os(iOS)
import SwiftUI
import DesignSystem

/// Patch the Reward on the iPhone (U5L1): today's lesson design, Lesson
/// 1.1's night-sky island (`InteractiveCardShell`), with the track at the
/// top at full width and everything else stacked under it: the label, what
/// the picked rule is doing, the rules (one chip each, 44 pt or taller, a
/// selection haptic on each pick), then the reveal.
///
/// - Dynamic Type to AX5 on an SE: the track stays full width (described
///   in words for VoiceOver), the counters become a text table, chips stack
///   their words; decoration (icons, glows, stars) goes, never a word.
/// - Reduce Motion (and VoiceOver): nothing plays by itself; a run's route
///   and result show at once, as a still with numbered arrows.
/// - Increase Contrast and Reduce Transparency: no light, solid edges.
struct PatchTheRewardPhoneCard: View {
    private let context: InteractiveCardContext

    init(_ context: InteractiveCardContext) {
        self.context = context
    }

    var body: some View {
        let state = context.state { PatchTheRewardState(spoiled: $0.spoiled) }
        InteractiveCardShell(id: context.id, title: PatchTheRewardCopy.title,
                             summary: PatchTheRewardCopy.accessibilitySummary(state.summaryState),
                             compactLine: PatchTheRewardCopy.compactLine) {
            PatchTheRewardBody(state: state, wide: false, lit: false)
        }
    }
}
#endif
