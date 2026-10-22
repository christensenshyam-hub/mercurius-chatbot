#if os(macOS)
import SwiftUI

/// The Page with a Secret on the Mac (u8_l1): Night Studio's lit card in
/// the lesson's reading column, after the first teach reply's example part.
///
/// Wide enough (a 1280 pt window), the loop ring sits at left and the run
/// at right, so the made-up page at step 3 is on the right; narrower, the
/// loop sits above the run. Below 440 pt the shell shows the compact "Try
/// it" card, which opens in place.
///
/// - Keyboard: Next and Back (and → / ← while either has focus), the
///   prediction's chips and the page's toggle (← / → while it has focus)
///   are all in the Tab loop whatever the Full Keyboard Access setting;
///   Space or Return acts. A focused control holds Return, so the lesson's
///   check never locks in from it; A–D, 1–4 and ↑/↓ still answer the check.
/// - In the agent's view the hidden line glows in lumen, in a dashed box
///   tagged HIDDEN (the box and the words say it, not the colour).
/// - Reduce Motion: crossfades only. Increase Contrast and Reduce
///   Transparency: solid edges, no glows (`theme.lit`).
public struct NightPageWithASecretCard: View {
    private let context: InteractiveCardContext
    @State private var width: CGFloat = 0

    /// The content width (inside the card's padding) from which the ring
    /// sits beside the run: its 176 pt column, the gap, and about 300 pt
    /// for the run. A 620 pt reading column leaves 580.
    static let twoColumnsFrom: CGFloat = 500

    public init(_ context: InteractiveCardContext) {
        self.context = context
    }

    public var body: some View {
        let state = context.state { PageWithASecretState(spoiled: $0.spoiled) }
        InteractiveCardShell(id: context.id, title: PageWithASecretCopy.title,
                             summary: PageWithASecretCopy.accessibilitySummary(state.progress),
                             compactLine: PageWithASecretCopy.compactLine) {
            PageWithASecretBody(state: state, twoColumns: width >= Self.twoColumnsFrom)
                .onGeometryChange(for: CGFloat.self) { geo in
                    geo.size.width
                } action: { newWidth in
                    width = newWidth
                }
        }
    }
}
#endif
