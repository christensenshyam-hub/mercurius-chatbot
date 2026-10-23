import SwiftUI
import DesignSystem

/// The winding "Duolingo-blueprint" learning path — the new body of the
/// Curriculum tab. A single vertical scroll of unit checkpoint banners and
/// circular lesson nodes connected by a serpentine trail, auto-scrolled to the
/// learner's current frontier.
///
/// It reads every node's state from `CurriculumProgressStore` (the same store
/// the old list used) and launches lessons / unit tests through the SAME
/// `onStartLesson` / `onStartUnitTest` callbacks — no infrastructure changes,
/// purely a presentation reshape.
struct LearningPathView: View {
    let progress: CurriculumProgressStore
    /// Show only this unit's banner and stops (the Mac sidebar's "Path by
    /// unit"); nil shows the whole path under its header, as on iOS.
    var unitId: String? = nil
    let onStartLesson: (Lesson) -> Void
    let onStartUnitTest: (Unit) -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// A short line Merc "says" when poked on the path — Duolingo-style.
    @State private var mercLine: String?
    @State private var mercLineTask: Task<Void, Never>?

    var body: some View {
        // Compute the frontier once per render; threaded into each node.
        let current = currentStopId
        let elements = buildElements()
        let layout = LearningPathLayout.forSize(dynamicTypeSize)

        // GeometryReader so the path-side Merc can bow out in windows too
        // narrow for him to clear the swaying nodes (iPad Slide Over /
        // one-third Split View) — his tap target must never cover a node.
        GeometryReader { geo in
            let mercFits = geo.size.width >= 360

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 0) {
                        // One unit's page opens on its own banner; the
                        // overall header belongs to the whole path.
                        if unitId == nil {
                            pathHeader
                        }

                        ForEach(Array(elements.enumerated()), id: \.element.id) { index, element in
                            Group {
                                switch layout {
                                case .winding:
                                    row(for: element,
                                        previous: index > 0 ? elements[index - 1] : nil,
                                        current: current,
                                        mercFits: mercFits)
                                case .list:
                                    listRow(for: element, current: current)
                                }
                            }
                            .id(element.id)
                        }

                        Color.clear.frame(height: BrandSpacing.xxl)
                    }
                    .macReadableColumn(MacLayout.pathWidth)
                }
                .scrollContentBackground(.hidden)
                .background(BrandColor.background)
                .onAppear {
                    let opening = PathOpeningScroll.target(
                        frontierID: current,
                        rows: elements.map { (id: $0.id, isBanner: $0.isBanner) })
                    // Defer a frame so the lazy stack has laid out before scrolling.
                    DispatchQueue.main.async {
                        switch opening {
                        case .top:
                            break
                        case .unitBanner(let id):
                            withAnimation(reduceMotion ? nil : .easeInOut) { proxy.scrollTo(id, anchor: .top) }
                        case .centered(let id):
                            withAnimation(reduceMotion ? nil : .easeInOut) { proxy.scrollTo(id, anchor: .center) }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Header

    private var pathHeader: some View {
        let done = progress.totalCompleted()
        let total = progress.totalLessons
        return VStack(spacing: BrandSpacing.sm) {
            // Merc lives IN the path now (beside the current node, Duolingo
            // style) rather than posing in the header. Only when the whole
            // path is finished — no current node for him to stand next to —
            // does he return here, celebrating.
            if currentStopId == nil {
                MercMascot(.celebrate, size: 92, pokeable: true)
                    .accessibilityHidden(true)
            }
            Text("Your learning path")
                .font(BrandFont.roundedTitle)
                .foregroundStyle(BrandColor.text)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            overallProgressBar(done: done, total: total)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, BrandSpacing.xl)
        .padding(.top, BrandSpacing.md)
        .padding(.bottom, BrandSpacing.xs)
    }

    private func overallProgressBar(done: Int, total: Int) -> some View {
        let fraction = total > 0 ? CGFloat(done) / CGFloat(total) : 0
        return VStack(spacing: 4) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(BrandColor.surfaceElevated)
                    Capsule()
                        .fill(BrandGradient.mercHorizontal)
                        // No filled nub at 0% — a brand-new learner sees an empty
                        // track, not a sliver implying progress that doesn't exist.
                        .frame(width: fraction > 0 ? max(8, geo.size.width * fraction) : 0)
                }
            }
            .frame(height: 12)
            Text("\(done) of \(total) lessons complete")
                .font(BrandFont.roundedCaption)
                .foregroundStyle(BrandColor.textSecondary)
        }
        .padding(.horizontal, BrandSpacing.xl)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(done) of \(total) lessons complete")
    }

    // MARK: - Rows

    @ViewBuilder
    private func row(for element: PathElement, previous: PathElement?, current: String?,
                     mercFits: Bool) -> some View {
        switch element {
        case .header(let unit):
            UnitCheckpointHeader(
                unit: unit,
                completed: progress.completedCount(in: unit),
                total: unit.lessons.count,
                mastered: progress.isUnitMastered(unit.id)
            )

        case .lesson(let lesson, let unit, let nodeIndex):
            let status = lessonStatus(lesson, in: unit, current: current)
            // Frontier identity is separate from progress status: a lesson the
            // student is midway through is almost always ALSO the frontier, and
            // must show its .inProgress styling (half ring, "In progress")
            // while still getting the frontier beat (callout, Merc, lead-in).
            let isFrontier = current == PathElement.lessonId(lesson)
            VStack(spacing: 0) {
                if previous?.nodeIndex == nil {
                    // First lesson in a unit: no connector above it (the header is
                    // the break). Reserve a lead-in below the banner — extra when
                    // this is the frontier node so its callout clears the card.
                    Color.clear.frame(height: isFrontier ? 44 : 16)
                } else {
                    connector(before: element, nodeIndex: nodeIndex, previous: previous)
                }
                Button {
                    guard status != .locked else { return }
                    onStartLesson(lesson)
                } label: {
                    LessonNode(lesson: lesson, status: status, labelSide: labelSide(for: nodeIndex),
                               isFrontier: isFrontier)
                }
                .buttonStyle(.plain)
                .lockedNode(status == .locked)
                .offset(x: LearningPathMetrics.offset(for: nodeIndex))
            }
            .overlay(alignment: mercSide(for: nodeIndex)) {
                if isFrontier, mercFits { pathMerc(for: nodeIndex) }
            }

        case .unitTest(let unit, let nodeIndex):
            let status = unitTestStatus(unit, current: current)
            VStack(spacing: 0) {
                connector(before: element, nodeIndex: nodeIndex, previous: previous)
                Button {
                    guard status != .locked else { return }
                    onStartUnitTest(unit)
                } label: {
                    UnitTestNode(unit: unit, status: status, labelSide: labelSide(for: nodeIndex))
                }
                .buttonStyle(.plain)
                .lockedNode(status == .locked)
                .offset(x: LearningPathMetrics.offset(for: nodeIndex))
            }
            .overlay(alignment: mercSide(for: nodeIndex)) {
                if status == .current, mercFits { pathMerc(for: nodeIndex) }
            }
        }
    }

    /// The straight list used at accessibility text sizes (AUD-47): the same
    /// stops, states and callbacks, without the sway, the connectors or the
    /// path-side Merc.
    @ViewBuilder
    private func listRow(for element: PathElement, current: String?) -> some View {
        switch element {
        case .header(let unit):
            UnitCheckpointHeader(
                unit: unit,
                completed: progress.completedCount(in: unit),
                total: unit.lessons.count,
                mastered: progress.isUnitMastered(unit.id)
            )
            .padding(.bottom, BrandSpacing.sm)

        case .lesson(let lesson, let unit, _):
            let status = lessonStatus(lesson, in: unit, current: current)
            Button {
                guard status != .locked else { return }
                onStartLesson(lesson)
            } label: {
                LessonNode(lesson: lesson, status: status, labelSide: .trailing,
                           isFrontier: current == PathElement.lessonId(lesson), layout: .list)
            }
            .buttonStyle(.plain)
            .lockedNode(status == .locked)

        case .unitTest(let unit, _):
            let status = unitTestStatus(unit, current: current)
            Button {
                guard status != .locked else { return }
                onStartUnitTest(unit)
            } label: {
                UnitTestNode(unit: unit, status: status, labelSide: .trailing, layout: .list)
            }
            .buttonStyle(.plain)
            .lockedNode(status == .locked)
        }
    }

    // MARK: - Path-side Merc (the Duolingo beat)

    /// Merc stands on the side the current node sways TOWARD — the label text
    /// sits on the opposite side, so that's where the serpentine leaves open
    /// space for him.
    private func mercSide(for nodeIndex: Int) -> Alignment {
        LearningPathMetrics.offset(for: nodeIndex) <= 0 ? .bottomLeading : .bottomTrailing
    }

    /// Merc living on the path beside the learner's current node: idle antics
    /// every few seconds, a poke reaction + a short encouragement line on tap.
    /// Hidden at accessibility type sizes, where the wrapping labels need the
    /// horizontal room (same convention as the chat avatar).
    ///
    /// Geometry care: the stack is edge-aligned (matching the overlay edge) so
    /// the wider speech capsule grows INWARD while Merc himself never moves —
    /// his tap target stays clear of the node button. The 36pt gap floats the
    /// capsule above the node's START-callout band (it hangs over the mostly
    /// empty connector zone instead), and the capsule doesn't hit-test so it
    /// can never swallow a lesson-start tap.
    @ViewBuilder private func pathMerc(for nodeIndex: Int) -> some View {
        if !dynamicTypeSize.isAccessibilitySize {
            let edge: HorizontalAlignment =
                LearningPathMetrics.offset(for: nodeIndex) <= 0 ? .leading : .trailing
            VStack(alignment: edge, spacing: 36) {
                if let mercLine {
                    Text(mercLine)
                        .font(BrandFont.roundedCaption)
                        .foregroundStyle(BrandColor.text)
                        .lineLimit(1)
                        .padding(.vertical, 6)
                        .padding(.horizontal, 10)
                        .background(
                            Capsule()
                                .fill(BrandColor.surfaceElevated)
                                .overlay(Capsule().strokeBorder(BrandColor.border, lineWidth: 1))
                                .brandShadow(.card)
                        )
                        .allowsHitTesting(false)
                        .transition(.opacity.combined(with: .scale(scale: 0.85, anchor: .bottom)))
                }
                MercMascot(.idle, size: 76, idleAntics: true, pokeable: true,
                           onTap: speakMercLine)
            }
            .padding(.horizontal, BrandSpacing.md)
            // Bottom-aligned to the row; lift so Merc centers on the node circle.
            // (76pt Merc is ~68pt wide: edge padding 12 + 68 = 80pt clears the
            // node's near edge at the deepest sway, 91.5pt, on a 375pt screen —
            // and windows narrower than 360pt drop him entirely via mercFits.)
            .offset(y: -(LearningPathMetrics.nodeCellHeight - 76) / 2)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: mercLine)
            .accessibilityHidden(true)
        }
    }

    private func speakMercLine() {
        mercLineTask?.cancel()
        let lines = ["You've got this!", "Ready when you are!",
                     "One step at a time.", "Let's go!"]
        mercLine = lines.randomElement()
        mercLineTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(2.5))
            guard !Task.isCancelled else { return }
            mercLine = nil
        }
    }

    /// Draw the trail segment leading into a node — but only when the previous
    /// element is itself a node (a header is a visual break, so no connector
    /// crosses it).
    @ViewBuilder
    private func connector(before element: PathElement, nodeIndex: Int, previous: PathElement?) -> some View {
        if let previous, let prevIndex = previous.nodeIndex {
            PathConnector(
                fromOffset: LearningPathMetrics.offset(for: prevIndex),
                toOffset: LearningPathMetrics.offset(for: nodeIndex),
                filled: isStopCompleted(previous)
            )
        }
    }

    private func labelSide(for nodeIndex: Int) -> NodeLabelSide {
        LearningPathMetrics.offset(for: nodeIndex) <= 0 ? .trailing : .leading
    }

    // MARK: - Status derivation

    private func lessonStatus(_ lesson: Lesson, in unit: Unit, current: String?) -> PathNodeStatus {
        let state = progress.state(of: lesson.id)
        if state == .completed { return .completed }
        if !progress.isLessonUnlocked(lesson, in: unit) { return .locked }
        // Progress state outranks frontier identity: the frontier is the first
        // non-completed unlocked lesson, which is exactly where a mid-lesson
        // student sits — it must read "In progress" (half ring, resume), not
        // "Start now". The frontier decorations key off `isFrontier` in `row`.
        if state == .inProgress { return .inProgress }
        if current == PathElement.lessonId(lesson) { return .current }
        return .available
    }

    private func unitTestStatus(_ unit: Unit, current: String?) -> PathNodeStatus {
        if progress.isUnitMastered(unit.id) { return .completed }
        if !progress.isUnitTestUnlocked(unit) { return .locked }
        if current == PathElement.unitTestId(unit) { return .current }
        return .available
    }

    private func isStopCompleted(_ element: PathElement) -> Bool {
        switch element {
        case .lesson(let l, _, _): return progress.state(of: l.id) == .completed
        case .unitTest(let u, _):  return progress.isUnitMastered(u.id)
        case .header:              return false
        }
    }

    /// The row id of the learner's frontier (`CurriculumProgressStore.frontier()`).
    private var currentStopId: String? {
        switch progress.frontier() {
        case .lesson(let lesson): return PathElement.lessonId(lesson)
        case .unitTest(let unit): return PathElement.unitTestId(unit)
        case nil:                 return nil
        }
    }

    // MARK: - Element model

    private func buildElements() -> [PathElement] {
        var out: [PathElement] = []
        var nodeIndex = 0
        for unit in MercuriusCurriculum.units where unitId == nil || unit.id == unitId {
            out.append(.header(unit))
            for lesson in unit.lessons {
                out.append(.lesson(lesson, unit, nodeIndex: nodeIndex))
                nodeIndex += 1
            }
            out.append(.unitTest(unit, nodeIndex: nodeIndex))
            nodeIndex += 1
        }
        return out
    }
}

/// One row on the path: a unit banner, a lesson node, or a unit-test node.
/// `nodeIndex` drives the serpentine sway and is `nil` for headers (which don't
/// participate in the trail). The `id` doubles as the `ScrollViewReader` target.
private enum PathElement: Identifiable {
    case header(Unit)
    case lesson(Lesson, Unit, nodeIndex: Int)
    case unitTest(Unit, nodeIndex: Int)

    static func lessonId(_ lesson: Lesson) -> String { "L_" + lesson.id }
    static func unitTestId(_ unit: Unit) -> String { "T_" + unit.id }

    var id: String {
        switch self {
        case .header(let u):        return "H_" + u.id
        case .lesson(let l, _, _):  return PathElement.lessonId(l)
        case .unitTest(let u, _):   return PathElement.unitTestId(u)
        }
    }

    var isBanner: Bool {
        if case .header = self { return true }
        return false
    }

    var nodeIndex: Int? {
        switch self {
        case .header:                 return nil
        case .lesson(_, _, let i):    return i
        case .unitTest(_, let i):     return i
        }
    }
}

private extension View {
    /// A locked node takes no taps and isn't announced as a button, but
    /// keeps its full colours: `.disabled` dimmed the already-secondary
    /// "Locked" label below a readable contrast (AUD-21). The node's own
    /// accessibility label still says "Locked".
    func lockedNode(_ locked: Bool) -> some View {
        allowsHitTesting(!locked)
            .accessibilityRemoveTraits(locked ? .isButton : [])
    }
}
