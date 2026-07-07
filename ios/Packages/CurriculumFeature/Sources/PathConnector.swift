import SwiftUI
import DesignSystem

/// The trail segment drawn between two consecutive path nodes.
///
/// It strokes a straight line from directly below the previous node's center to
/// directly above this node's center, so the serpentine reads as one continuous
/// trail even though each node sways to a different horizontal offset. Drawn
/// per-row (no global geometry) so the path reflows cleanly under Dynamic Type —
/// the connector only needs its own row width, read from a local `GeometryReader`.
///
/// `filled` paints the segment in the brand gradient once the trail has been
/// completed up to this point; otherwise it's a faint inactive track.
struct PathConnector: View {
    /// Horizontal offset (points from center) of the node above this segment.
    let fromOffset: CGFloat
    /// Horizontal offset of the node below this segment.
    let toOffset: CGFloat
    /// Whether the previous node is complete — paints the trail as "earned."
    let filled: Bool

    var body: some View {
        GeometryReader { geo in
            let cx = geo.size.width / 2
            Path { path in
                path.move(to: CGPoint(x: cx + fromOffset, y: 0))
                path.addLine(to: CGPoint(x: cx + toOffset, y: geo.size.height))
            }
            .stroke(style: StrokeStyle(lineWidth: 7, lineCap: .round))
            .foregroundStyle(strokeStyle)
        }
        .frame(height: LearningPathMetrics.connectorHeight)
        .accessibilityHidden(true)
    }

    private var strokeStyle: AnyShapeStyle {
        filled
            ? AnyShapeStyle(BrandGradient.mercHorizontal)
            : AnyShapeStyle(BrandColor.border)
    }
}
