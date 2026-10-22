#if os(iOS)
import SwiftUI

/// The Citation That Wasn't on the iPhone (U1L3), in today's lesson design:
/// Lesson 1.1's night-sky island (`InteractiveCardShell`), the iPhone's
/// type and spacing, and 44 pt targets with a selection haptic on each
/// guess, step and rewrite. A vertical list: the example reply on top, its
/// reference growing as the slots fill, and under it one slot's three
/// candidates at a time as rows.
///
/// At the accessibility sizes the bars go (each chance is printed), the
/// step strip goes (the step's heading says "Step 2 of 5 · Year"), the
/// guess's hand glyph goes, and every word stays. Reduce Motion: pieces
/// crossfade in. Increase Contrast and Reduce Transparency: no stars or
/// glows, solid edges.
struct CitationPhoneCard: View {
    private let context: InteractiveCardContext

    init(_ context: InteractiveCardContext) {
        self.context = context
    }

    var body: some View {
        let state = context.state { CitationState(spoiled: $0.spoiled) }
        InteractiveCardShell(id: context.id, title: CitationCopy.title, summary: state.summary,
                             compactLine: CitationCopy.compactLine) {
            CitationCardBody(state: state)
        }
    }
}
#endif
