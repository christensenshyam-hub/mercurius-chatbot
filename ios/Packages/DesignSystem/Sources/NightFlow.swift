import SwiftUI

/// Wraps its children onto new lines when they run out of width (token
/// chips), with a rounding tolerance so a line measured as one never wraps.
/// Night Studio's on the Mac; the iPhone's night-sky card (Lesson 1.1's
/// interactive) wraps its tokens and numbers with it too.
public struct NightFlow: Layout {
    private let spacing: CGFloat
    private let lineSpacing: CGFloat

    public init(spacing: CGFloat = 8, lineSpacing: CGFloat = 8) {
        self.spacing = spacing
        self.lineSpacing = lineSpacing
    }

    public func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var lineHeight: CGFloat = 0
        var widest: CGFloat = 0
        for subview in subviews {
            let size = Self.size(of: subview, line: maxWidth)
            if x > 0 && x + size.width > maxWidth {
                y += lineHeight + lineSpacing
                x = 0
                lineHeight = 0
            }
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
            widest = max(widest, x - spacing)
        }
        return CGSize(width: min(widest, maxWidth), height: y + lineHeight)
    }

    public func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var lineHeight: CGFloat = 0
        let line = max(proposal.width ?? bounds.width, bounds.width)
        let maxX = bounds.minX + line + 0.5
        for subview in subviews {
            let size = Self.size(of: subview, line: line)
            if x > bounds.minX && x + size.width > maxX {
                y += lineHeight + lineSpacing
                x = bounds.minX
                lineHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
    }

    /// A child's size: its own width, or, when that is wider than a whole
    /// line (a long chip at a large text size on a narrow screen), the
    /// line's width, so its words wrap instead of running past the edge.
    private static func size(of subview: LayoutSubview, line: CGFloat) -> CGSize {
        let ideal = subview.sizeThatFits(.unspecified)
        guard line.isFinite, ideal.width > line + 0.5 else { return ideal }
        return subview.sizeThatFits(ProposedViewSize(width: line, height: nil))
    }
}
