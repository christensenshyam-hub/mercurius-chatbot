#if os(iOS)
import SwiftUI

/// Delete the Gender Box (U3L1) on the iPhone: today's lesson design, the
/// night-sky island Lesson 1.1's card uses (`InteractiveCardShell`), with
/// the pieces stacked: the 12 past résumés, what the toy learned, the two
/// new résumés, the guess, "Gender box: kept | deleted", and the reveal.
///
/// - Targets are 44 pt or taller; a guess and each flip give a selection
///   haptic (the shared chips).
/// - Dynamic Type to AX5: at the accessibility sizes the résumé table goes
///   behind "Show all 12" (its summary stays), the weight bars become rows
///   of text and the two test résumés stack. Decoration goes, never a word.
/// - Reduce Motion: the strike-through, bars and scores crossfade.
/// - VoiceOver: the title says the card's state; the résumés, weights and
///   test résumés are one element each; a flip says the new weights and
///   both scores.
struct GenderBoxPhoneCard: View {
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
