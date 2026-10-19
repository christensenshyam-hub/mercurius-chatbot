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

    /// The node in the straight list (accessibility sizes).
    static let listNodeDiameter: CGFloat = 52
}

/// How the path is drawn. The winding path gives each title a fixed 148 pt
/// beside a fixed-height node, which at accessibility text sizes cut titles
/// to one word ("Few-shot…", "Comple…"), and at xxxLarge still cut them on
/// every phone ("What happens when you type a p…"). From xxxLarge up the
/// path is a straight list whose titles wrap freely (AUD-47).
enum LearningPathLayout: Equatable {
    case winding
    case list

    /// The smallest size drawn as the list.
    static let listFrom: DynamicTypeSize = .xxxLarge

    static func forSize(_ size: DynamicTypeSize) -> LearningPathLayout {
        size >= listFrom ? .list : .winding
    }
}

/// Where the path opens. Centring the frontier node used to cut a unit's
/// banner in half under the pinned streak bar at large text (on the first
/// lesson of a unit the banner sits right above the node), leaving
/// "UNIT 01" and the start of the unit's name hidden.
enum PathOpeningScroll: Equatable {
    /// At the top: nothing to show, or the frontier is the path's first stop,
    /// which the top already shows under "Your learning path".
    case top
    /// The frontier opens its unit: that unit's banner at the top, the node
    /// right below it.
    case unitBanner(id: String)
    /// The frontier node in the middle of the screen.
    case centered(id: String)

    /// - Parameters:
    ///   - frontierID: the row of the learner's next stop, if any.
    ///   - rows: every row of the path, in order; `isBanner` marks a unit banner.
    static func target(frontierID: String?, rows: [(id: String, isBanner: Bool)]) -> PathOpeningScroll {
        guard let frontierID, let index = rows.firstIndex(where: { $0.id == frontierID }) else { return .top }
        guard index > 0, rows[index - 1].isBanner else { return .centered(id: frontierID) }
        return index - 1 == 0 ? .top : .unitBanner(id: rows[index - 1].id)
    }
}

/// What a stop says and shows for its status: shared by the winding node and
/// the list row so the two can't drift.
struct PathStopPresentation: Equatable {
    let systemImage: String
    /// nil for an available lesson, which shows no status line.
    let statusText: String?
    let tone: Tone

    enum Tone: Equatable {
        case done, active, muted
    }

    /// The status line's colour: the text tokens, so "Completed" and
    /// "Start now" read at 4.5:1 or better (AUD-21).
    var statusColor: Color {
        switch tone {
        case .done:   return BrandColor.successText
        case .active: return BrandColor.accentText
        case .muted:  return BrandColor.textSecondary
        }
    }

    static func lesson(_ status: PathNodeStatus) -> PathStopPresentation {
        switch status {
        case .completed:  return .init(systemImage: "checkmark", statusText: "Completed", tone: .done)
        case .current:    return .init(systemImage: "star.fill", statusText: "Start now", tone: .active)
        case .inProgress: return .init(systemImage: "arrow.triangle.2.circlepath", statusText: "In progress", tone: .active)
        case .available:  return .init(systemImage: "book.fill", statusText: nil, tone: .muted)
        case .locked:     return .init(systemImage: "lock.fill", statusText: "Locked", tone: .muted)
        }
    }

    static func unitTest(_ status: PathNodeStatus) -> PathStopPresentation {
        switch status {
        case .completed: return .init(systemImage: "checkmark.seal.fill", statusText: "Mastered", tone: .done)
        case .current:   return .init(systemImage: "crown.fill", statusText: "Take the test", tone: .active)
        case .locked:    return .init(systemImage: "lock.fill", statusText: "Finish the unit first", tone: .muted)
        default:         return .init(systemImage: "crown.fill", statusText: "Ready", tone: .active)
        }
    }

    /// VoiceOver's reading of a lesson stop.
    static func lessonLabel(number: Int, title: String, status: PathNodeStatus) -> String {
        "Lesson \(number): \(title). \(lesson(status).statusText ?? "Available")."
    }

    /// VoiceOver's reading of a unit-test stop.
    static func unitTestLabel(unitNumber: String, status: PathNodeStatus) -> String {
        "Unit \(unitNumber) cumulative test. \(unitTest(status).statusText ?? "Available")."
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
    /// The disc's size: the path's 76 pt, or smaller in the list.
    var diameter: CGFloat = LearningPathMetrics.nodeDiameter

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulse = false

    /// The pulsing halo marks the frontier beat, not a progress state.
    private var showsPulse: Bool { status == .current || isFrontier }

    var body: some View {
        ZStack {
            if showsPulse {
                Circle()
                    .stroke(BrandColor.accent.opacity(0.35), lineWidth: 4)
                    .frame(width: diameter, height: diameter)
                    .scaleEffect(pulse ? 1.24 : 1.0)
                    .opacity(pulse ? 0 : 0.9)
            }

            Circle()
                .trim(from: 0, to: ringTrim)
                .stroke(BrandGradient.mercHorizontal, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .frame(width: diameter + 10, height: diameter + 10)

            Circle()
                .fill(bodyStyle)
                .frame(width: diameter, height: diameter)
                .overlay(
                    Circle().strokeBorder(borderStyle, lineWidth: 1.5)
                )
                .brandShadow(status == .locked ? .card : .node)

            Image(systemName: systemImage)
                .font(.system(size: diameter * 0.37, weight: .bold))
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
    var layout: LearningPathLayout = .winding

    private var presentation: PathStopPresentation { .lesson(status) }

    var body: some View {
        Group {
            switch layout {
            case .winding:
                ZStack {
                    PathNodeCircle(status: status, systemImage: presentation.systemImage, isFrontier: isFrontier)
                        .overlay(alignment: .top) {
                            if isFrontier {
                                StartCallout(title: status == .inProgress ? "RESUME" : "START")
                                    .offset(y: -LearningPathMetrics.calloutLift)
                            }
                        }

                    NodeLabel(title: lesson.title, statusText: presentation.statusText,
                              statusColor: presentation.statusColor, side: labelSide)
                        .offset(x: labelXOffset(for: labelSide))
                }
                .frame(maxWidth: .infinity)
                .frame(height: LearningPathMetrics.nodeCellHeight)
            case .list:
                PathListRow(title: lesson.title, presentation: presentation,
                            status: status, isFrontier: isFrontier)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(PathStopPresentation.lessonLabel(number: lesson.number, title: lesson.title, status: status))
        .accessibilityAddTraits(status == .locked ? [] : .isButton)
    }
}

// MARK: - Unit-test node

/// The cumulative unit-test stop — a "crown" checkpoint at the end of a unit.
struct UnitTestNode: View {
    let unit: Unit
    let status: PathNodeStatus
    let labelSide: NodeLabelSide
    var layout: LearningPathLayout = .winding

    private var presentation: PathStopPresentation { .unitTest(status) }

    var body: some View {
        Group {
            switch layout {
            case .winding:
                ZStack {
                    PathNodeCircle(status: status, systemImage: presentation.systemImage)
                        .overlay(alignment: .top) {
                            if status == .current {
                                StartCallout()
                                    .offset(y: -LearningPathMetrics.calloutLift)
                            }
                        }

                    NodeLabel(title: "Unit \(unit.number) test", statusText: presentation.statusText,
                              statusColor: presentation.statusColor, side: labelSide)
                        .offset(x: labelXOffset(for: labelSide))
                }
                .frame(maxWidth: .infinity)
                .frame(height: LearningPathMetrics.nodeCellHeight)
            case .list:
                PathListRow(title: "Unit \(unit.number) test", presentation: presentation,
                            status: status, isFrontier: status == .current)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(PathStopPresentation.unitTestLabel(unitNumber: unit.number, status: status))
        .accessibilityAddTraits(status == .locked ? [] : .isButton)
    }
}

// MARK: - List row (accessibility sizes)

/// One stop in the straight list: a small node on the left, the whole title
/// wrapping freely beside it, and the status underneath. The row grows with
/// its text instead of holding a fixed height (AUD-47).
private struct PathListRow: View {
    let title: String
    let presentation: PathStopPresentation
    let status: PathNodeStatus
    let isFrontier: Bool

    var body: some View {
        HStack(alignment: .center, spacing: BrandSpacing.md) {
            PathNodeCircle(status: status, systemImage: presentation.systemImage,
                           isFrontier: isFrontier, diameter: LearningPathMetrics.listNodeDiameter)
                .frame(width: LearningPathMetrics.listNodeDiameter + 10,
                       height: LearningPathMetrics.listNodeDiameter + 10)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(BrandFont.roundedBodyEmphasized)
                    .foregroundStyle(BrandColor.text)
                    .fixedSize(horizontal: false, vertical: true)
                if let statusText = presentation.statusText {
                    Text(statusText)
                        .font(BrandFont.roundedCaption)
                        .foregroundStyle(presentation.statusColor)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, BrandSpacing.lg)
        .padding(.vertical, BrandSpacing.sm)
        .frame(maxWidth: .infinity, minHeight: LearningPathMetrics.listNodeDiameter + 20, alignment: .leading)
        .contentShape(Rectangle())
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
            // One word that must never wrap ("STAR/T"); it is decoration on a
            // node whose label already says "Start now", so it stops growing
            // at xxxLarge (AUD-47).
            .lineLimit(1)
            .fixedSize()
            .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
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
