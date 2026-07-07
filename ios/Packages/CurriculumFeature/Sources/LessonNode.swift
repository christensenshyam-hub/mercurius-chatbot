import SwiftUI
import DesignSystem

/// Shared geometry for the winding learning path. Node diameters are FIXED in
/// points (the node is a graphic), so they don't balloon at accessibility text
/// sizes — only the side labels scale and wrap. The sway offsets are relative
/// (points from center), never absolute coordinates, so the column reflows
/// cleanly as it grows vertically.
enum LearningPathMetrics {
    static let nodeDiameter: CGFloat = 76
    static let nodeRadius: CGFloat = 38
    static let nodeCellHeight: CGFloat = 92
    static let connectorHeight: CGFloat = 30
    static let labelGap: CGFloat = 16
    static let labelWidth: CGFloat = 148

    /// How far the START callout sits above the node center. Kept small so the
    /// bubble HUGS its node (pointer touching the disc) and stays within the
    /// connector gap — it must not reach up into the previous node or the unit
    /// banner. First-lesson clearance below a banner is handled in LearningPathView.
    static let calloutLift: CGFloat = 26

    /// The serpentine — a gentle S the nodes follow as you scroll.
    static let swayOffsets: [CGFloat] = [-30, 30, 58, 30, -30, -58]

    static func offset(for nodeIndex: Int) -> CGFloat {
        let n = swayOffsets.count
        return swayOffsets[((nodeIndex % n) + n) % n]
    }
}

/// The visual state of a single node, derived from `CurriculumProgressStore`.
/// The frontier beat (callout, pulse, path-side Merc) is keyed to frontier
/// IDENTITY separately (`isFrontier`), because the frontier is usually the
/// in-progress lesson — status carries the progress semantics only.
enum PathNodeStatus: Equatable {
    case locked       // a prior lesson isn't finished yet
    case available    // unlocked, not yet the frontier
    case current      // the frontier, not yet started — "Start now"
    case inProgress   // started, resumable
    case completed    // finished (lesson) or mastered (unit test)
}

enum NodeLabelSide { case leading, trailing }

// MARK: - Node circle

/// The circular node graphic — a gradient disc (or a muted disc when locked),
/// a progress ring, a glyph, and — for the current node — a pulsing halo.
struct PathNodeCircle: View {
    let status: PathNodeStatus
    let systemImage: String
    /// The learner's frontier node keeps its pulsing halo even when its status
    /// is `.inProgress` (the common mid-lesson case). Defaults off so non-path
    /// callers (unit-test nodes) are unchanged.
    var isFrontier: Bool = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulse = false

    /// The pulsing halo marks the frontier beat, not a progress state.
    private var showsPulse: Bool { status == .current || isFrontier }

    var body: some View {
        ZStack {
            if showsPulse {
                Circle()
                    .stroke(BrandColor.accent.opacity(0.35), lineWidth: 4)
                    .frame(width: LearningPathMetrics.nodeDiameter, height: LearningPathMetrics.nodeDiameter)
                    .scaleEffect(pulse ? 1.24 : 1.0)
                    .opacity(pulse ? 0 : 0.9)
            }

            Circle()
                .trim(from: 0, to: ringTrim)
                .stroke(BrandGradient.mercHorizontal, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .frame(width: LearningPathMetrics.nodeDiameter + 10, height: LearningPathMetrics.nodeDiameter + 10)

            Circle()
                .fill(bodyStyle)
                .frame(width: LearningPathMetrics.nodeDiameter, height: LearningPathMetrics.nodeDiameter)
                .overlay(
                    Circle().strokeBorder(borderStyle, lineWidth: 1.5)
                )
                .brandShadow(status == .locked ? .card : .node)

            Image(systemName: systemImage)
                .font(.system(size: 28, weight: .bold))
                .foregroundStyle(iconColor)
        }
        .onAppear {
            guard showsPulse, !reduceMotion else { return }
            withAnimation(.easeOut(duration: 1.4).repeatForever(autoreverses: false)) { pulse = true }
        }
        // LazyVStack preserves @State across scroll-out, but the repeatForever
        // animation dies with the view — reset so reappearing re-arms it
        // instead of freezing at the peak frame.
        .onDisappear { pulse = false }
    }

    private var ringTrim: CGFloat {
        switch status {
        case .completed:  return 1
        case .inProgress: return 0.5
        default:          return 0
        }
    }

    private var bodyStyle: AnyShapeStyle {
        status == .locked ? AnyShapeStyle(BrandColor.surfaceElevated) : AnyShapeStyle(BrandGradient.merc)
    }

    /// Locked discs use the adaptive border token so their edge stays visible in
    /// dark mode (where the muted fill is only ~1.2:1 against the page); active
    /// discs keep a soft white inner highlight on the gradient.
    private var borderStyle: AnyShapeStyle {
        status == .locked ? AnyShapeStyle(BrandColor.border) : AnyShapeStyle(Color.white.opacity(0.25))
    }

    private var iconColor: Color {
        status == .locked ? BrandColor.textSecondary : .white
    }
}

// MARK: - Lesson node

/// A lesson stop on the path: the circular node, a side label, and (when it's
/// the frontier) a START callout. Purely visual — the host wraps it in a Button.
struct LessonNode: View {
    let lesson: Lesson
    let status: PathNodeStatus
    let labelSide: NodeLabelSide
    /// The frontier node carries the callout + pulse regardless of whether it
    /// is untouched (.current, "START") or midway (.inProgress, "RESUME").
    var isFrontier: Bool = false

    var body: some View {
        ZStack {
            PathNodeCircle(status: status, systemImage: icon, isFrontier: isFrontier)
                .overlay(alignment: .top) {
                    if isFrontier {
                        StartCallout(title: status == .inProgress ? "RESUME" : "START")
                            .offset(y: -LearningPathMetrics.calloutLift)
                    }
                }

            NodeLabel(title: lesson.title, statusText: statusText, statusColor: statusColor, side: labelSide)
                .offset(x: labelXOffset(for: labelSide))
        }
        .frame(maxWidth: .infinity)
        .frame(height: LearningPathMetrics.nodeCellHeight)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Lesson \(lesson.number): \(lesson.title). \(statusText ?? "Available").")
        .accessibilityAddTraits(status == .locked ? [] : .isButton)
    }

    private var icon: String {
        switch status {
        case .completed:  return "checkmark"
        case .current:    return "star.fill"
        case .inProgress: return "arrow.triangle.2.circlepath"
        case .available:  return "book.fill"
        case .locked:     return "lock.fill"
        }
    }

    private var statusText: String? {
        switch status {
        case .completed:  return "Completed"
        case .current:    return "Start now"
        case .inProgress: return "In progress"
        case .locked:     return "Locked"
        case .available:  return nil
        }
    }

    private var statusColor: Color {
        switch status {
        case .completed:  return BrandColor.success
        case .current:    return BrandColor.accent
        case .inProgress: return BrandColor.accent
        case .locked:     return BrandColor.textSecondary
        case .available:  return BrandColor.textSecondary
        }
    }
}

// MARK: - Unit-test node

/// The cumulative unit-test stop — a "crown" checkpoint at the end of a unit.
struct UnitTestNode: View {
    let unit: Unit
    let status: PathNodeStatus
    let labelSide: NodeLabelSide

    var body: some View {
        ZStack {
            PathNodeCircle(status: status, systemImage: icon)
                .overlay(alignment: .top) {
                    if status == .current {
                        StartCallout()
                            .offset(y: -LearningPathMetrics.calloutLift)
                    }
                }

            NodeLabel(title: "Unit \(unit.number) test", statusText: statusText, statusColor: statusColor, side: labelSide)
                .offset(x: labelXOffset(for: labelSide))
        }
        .frame(maxWidth: .infinity)
        .frame(height: LearningPathMetrics.nodeCellHeight)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Unit \(unit.number) cumulative test. \(statusText ?? "Available").")
        .accessibilityAddTraits(status == .locked ? [] : .isButton)
    }

    private var icon: String {
        switch status {
        case .completed: return "checkmark.seal.fill"
        case .current:   return "crown.fill"
        case .locked:    return "lock.fill"
        default:         return "crown.fill"
        }
    }

    private var statusText: String? {
        switch status {
        case .completed: return "Mastered"
        case .current:   return "Take the test"
        case .locked:    return "Finish the unit first"
        default:         return "Ready"
        }
    }

    private var statusColor: Color {
        switch status {
        case .completed: return BrandColor.success
        case .locked:    return BrandColor.textSecondary
        default:         return BrandColor.accent
        }
    }
}

// MARK: - Shared label + callout

/// Title + optional status caption placed beside a node. Sized to a fixed width
/// and allowed to wrap, but rendered as a sibling that doesn't change the node
/// cell's fixed height, so Dynamic Type growth can't break the path's rhythm.
private struct NodeLabel: View {
    let title: String
    let statusText: String?
    let statusColor: Color
    let side: NodeLabelSide

    var body: some View {
        VStack(alignment: side == .trailing ? .leading : .trailing, spacing: 2) {
            Text(title)
                .font(BrandFont.roundedBodyEmphasized)
                .foregroundStyle(BrandColor.text)
                // Bound the label so it can't grow past the fixed node cell and
                // bleed into neighbouring nodes at large Dynamic Type sizes.
                .lineLimit(3)
                .minimumScaleFactor(0.7)
                .truncationMode(.tail)
            if let statusText {
                Text(statusText)
                    .font(BrandFont.roundedCaption)
                    .foregroundStyle(statusColor)
            }
        }
        .multilineTextAlignment(side == .trailing ? .leading : .trailing)
        .frame(width: LearningPathMetrics.labelWidth, alignment: side == .trailing ? .leading : .trailing)
    }
}

/// Horizontal offset that places a label just beside the node on the given side.
private func labelXOffset(for side: NodeLabelSide) -> CGFloat {
    let magnitude = LearningPathMetrics.nodeRadius + LearningPathMetrics.labelGap + LearningPathMetrics.labelWidth / 2
    return side == .trailing ? magnitude : -magnitude
}

/// The bouncing "START" (or "RESUME", for a mid-lesson frontier) bubble above
/// the frontier node.
private struct StartCallout: View {
    var title: String = "START"

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var bob = false

    var body: some View {
        Text(title)
            .font(.system(.caption, design: .rounded, weight: .heavy))
            .foregroundStyle(.white)
            .padding(.horizontal, BrandSpacing.md)
            .padding(.vertical, 6)
            .background(BrandGradient.merc, in: Capsule())
            .overlay(alignment: .bottom) {
                DownPointer()
                    .fill(BrandColor.mercViolet)
                    .frame(width: 14, height: 7)
                    .offset(y: 6)
            }
            .brandShadow(.node)
            .offset(y: bob ? -3 : 0)
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true)) { bob = true }
            }
            // Reset on scroll-out so a lazy-container reappearance re-arms
            // the bob instead of freezing at the lifted frame.
            .onDisappear { bob = false }
            .accessibilityHidden(true)
    }
}

/// A small downward triangle that anchors the START bubble to its node.
private struct DownPointer: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        p.closeSubpath()
        return p
    }
}
