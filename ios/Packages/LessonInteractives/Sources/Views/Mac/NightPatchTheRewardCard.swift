#if os(macOS)
import SwiftUI
import DesignSystem

/// Patch the Reward on the Mac (U5L1), in Night Studio: the lit card
/// (`InteractiveCardShell`, a compact "Try it" card below 440 pt), a larger
/// track at the card's full width with the boat's lit wake on night water
/// (the card's one motion set piece), and, when the card is wide enough,
/// the rules table to the right of what the picked rule is doing.
///
/// - Keyboard: Tab reaches "Play it", the guesses and each rule's chip;
///   Return picks a chip, Space on the picked one plays it again, and ←/→
///   on a chip move to the rule before or after. A focused control keeps
///   Return from the lesson's check; A–D, 1–4 and ↑/↓ still answer it.
/// - Reduce Motion: nothing plays by itself; each run's still and result
///   show at once. Increase Contrast: no glows, solid edges.
struct NightPatchTheRewardCard: View {
    private let context: InteractiveCardContext
    @State private var width: CGFloat = 0

    /// The panel and the rules side by side from this card width up.
    static let sideBySideFrom: CGFloat = 520

    init(_ context: InteractiveCardContext) {
        self.context = context
    }

    var body: some View {
        let state = context.state { PatchTheRewardState(spoiled: $0.spoiled) }
        InteractiveCardShell(id: context.id, title: PatchTheRewardCopy.title,
                             summary: PatchTheRewardCopy.accessibilitySummary(state.summaryState),
                             compactLine: PatchTheRewardCopy.compactLine) {
            PatchTheRewardBody(state: state, wide: width >= Self.sideBySideFrom, lit: true)
                .onGeometryChange(for: CGFloat.self) { geo in
                    geo.size.width
                } action: { newWidth in
                    width = newWidth
                }
        }
    }
}
#endif
