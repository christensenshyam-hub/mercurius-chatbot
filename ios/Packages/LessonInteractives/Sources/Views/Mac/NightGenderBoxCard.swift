#if os(macOS)
import SwiftUI

/// Delete the Gender Box (U3L1) on the Mac: Night Studio's lit card
/// (`InteractiveCardShell`). From 500 pt of content the 12 past résumés sit
/// left and the weights and the two new résumés right (`GenderBoxColumns`);
/// narrower, they stack. Below the shell's 440 pt it starts as the compact "Try it" card.
///
/// - Keyboard: Tab reaches the guess's chips, then "kept" and "deleted";
///   Space or Return picks; ←/→ flip the gender box while either has focus.
///   A focused control holds Return, so the lesson's check never locks in
///   from it; A–D, 1–4 and ↑/↓ still answer the check.
/// - Deleting the gender box draws a line through its column (a crossfade
///   under Reduce Motion).
struct NightGenderBoxCard: View {
    private let context: InteractiveCardContext

    init(_ context: InteractiveCardContext) {
        self.context = context
    }

    var body: some View {
        let state = context.state { GenderBoxState(spoiled: $0.spoiled) }
        InteractiveCardShell(id: context.id, title: GenderBoxCopy.title, summary: state.summary,
                             compactLine: GenderBoxCopy.compactLine) {
            GenderBoxCardBody(state: state)
        }
    }
}
#endif
