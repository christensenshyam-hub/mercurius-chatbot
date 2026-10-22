import SwiftUI
import DesignSystem

// The Page with a Secret's pieces, drawn on both platforms with the card's
// theme (`\.interactiveTheme`): the iPhone's night-sky island and type, or
// Night Studio's tokens and ramp on the Mac. The platform cards
// (`PageWithASecretPhoneCard`, `NightPageWithASecretCard`) put them in the
// shell; `PageWithASecretBody` is the card's content on both.

/// The card's content, in order: the task, the "example run" label, the
/// loop, the run (stacked, step by step, the page inline at step 3 with the
/// prediction under it), Back/Next, the reveal, and the labels a guess
/// unlocks.
///
/// `twoColumns` (the Mac, wide enough): the loop ring at left, the run (and
/// so the page) at right. Otherwise the loop sits above the run.
struct PageWithASecretBody: View {
    let state: PageWithASecretState
    let twoColumns: Bool
    @Environment(\.interactiveTheme) private var theme

    private typealias Copy = PageWithASecretCopy

    var body: some View {
        VStack(alignment: .leading, spacing: theme.sectionSpacing) {
            PageTaskBubble()
            LabelLine(Copy.exampleLabelLead)
            if twoColumns {
                HStack(alignment: .top, spacing: theme.sectionSpacing) {
                    PageLoopPanel(step: state.steps.index, stacked: true)
                        .frame(width: PageLoopGeometry.macColumnWidth, alignment: .leading)
                    PageRunLog(state: state)
                }
            } else {
                PageLoopPanel(step: state.steps.index, stacked: false)
                PageRunLog(state: state)
            }
            controls
            if state.machine.isRevealed {
                RevealBox(state.revealLines, takeaway: Copy.takeaway)
                    .id(InteractiveScrollID.reveal)
                    .transition(theme.transition())
            }
            if state.canSwitchView {
                VStack(alignment: .leading, spacing: theme.rowSpacing) {
                    LabelLine(Copy.exampleLabelRest)
                    LabelLine(Copy.madeUpLabel)
                }
                .transition(theme.transition())
            }
        }
        .animation(theme.animation(InteractiveMotion.change), value: state.steps.furthest)
        .animation(theme.animation(InteractiveMotion.change), value: state.machine.isRevealed)
        .animation(theme.animation(InteractiveMotion.change), value: state.canSwitchView)
    }

    private var controls: some View {
        StepControls(state.steps, onBack: {
            if state.back() { InteractiveAccessibility.announce(state.stepAnnouncement) }
        }, onNext: {
            guard state.next() else { return }
            var said = state.stepAnnouncement
            if state.steps.isLast && state.machine.isRevealed {
                said += " " + state.revealLines.spoken + " " + Copy.takeaway
            }
            InteractiveAccessibility.announce(said)
        })
    }
}

// MARK: - The task

/// What the student asks the agent, as the student's own turn: trailing,
/// in their bubble (the iPhone's student hues, white words at 5.5:1 or
/// better; on the Mac, Night's student wash with ink).
struct PageTaskBubble: View {
    @Environment(\.interactiveTheme) private var theme

    var body: some View {
        let phone = theme.platform == .phone
        let radius: CGFloat = phone ? BrandRadius.xl : 14
        let tail: CGFloat = phone ? BrandRadius.sm : 4
        let shape = UnevenRoundedRectangle(topLeadingRadius: radius, bottomLeadingRadius: radius,
                                           bottomTrailingRadius: tail, topTrailingRadius: radius, style: .continuous)
        VStack(alignment: .trailing, spacing: phone ? BrandSpacing.xs : 6) {
            Text(PageWithASecretCopy.taskLead)
                .interactiveText(.caption)
                .foregroundStyle(theme.ink2)
            Text(PageWithASecretContent.task)
                .interactiveText(.body)
                .foregroundStyle(phone ? Color.white : theme.ink)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.vertical, phone ? BrandSpacing.md : 9)
                .padding(.horizontal, phone ? BrandSpacing.lg : 14)
                .background {
                    if phone {
                        shape.fill(LinearGradient(colors: [BrandColor.accentDark, BrandColor.mercViolet],
                                                  startPoint: .topLeading, endPoint: .bottomTrailing))
                    } else {
                        shape.fill(theme.wash(0.16))
                    }
                }
                .overlay {
                    if theme.increasedContrast {
                        shape.strokeBorder(phone ? Color.white.opacity(0.6) : theme.hairline, lineWidth: 1)
                    } else if !phone {
                        shape.strokeBorder(theme.wash(0.3), lineWidth: 1)
                    }
                }
        }
        .padding(.leading, theme.usesTables ? 0 : 24)
        .frame(maxWidth: .infinity, alignment: .trailing)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(PageWithASecretCopy.taskAccessibility)
    }
}

// MARK: - The loop

/// Where the ring's pieces go: three phases on a circle (Plan at the top,
/// Act at lower right, Observe at lower left), an arrowhead between each
/// pair pointing the way round, all inside a box that fits them. Pure, so
/// the tests can hold its bounds.
struct PageLoopGeometry: Equatable {
    let radius: CGFloat
    let node: CGSize
    let arrow: CGFloat

    /// The Mac's left column (the ring and "Now").
    static let macColumnWidth: CGFloat = 176

    /// The ring at `scale` (1 on the Mac; the iPhone's Dynamic Type step,
    /// relative to its caption).
    static func standard(scale: CGFloat) -> PageLoopGeometry {
        PageLoopGeometry(radius: 58 * scale, node: CGSize(width: 72 * scale, height: 26 * scale), arrow: 9 * scale)
    }

    /// Degrees, clockwise from 3 o'clock: the phases at -90°, 30°, 150°.
    static func nodeAngle(_ index: Int) -> Double { -90 + 120 * Double(index) }
    /// Half way to the next phase.
    static func arrowAngle(_ index: Int) -> Double { nodeAngle(index) + 60 }

    /// A point on the circle, from its centre.
    func offset(_ degrees: Double) -> CGPoint {
        let radians = degrees * Double.pi / 180
        return CGPoint(x: radius * CGFloat(cos(radians)), y: radius * CGFloat(sin(radians)))
    }

    /// Everything the ring draws, from its centre: the nodes, the
    /// arrowheads, and the circle's own extremes.
    private var extents: (minX: CGFloat, maxX: CGFloat, minY: CGFloat, maxY: CGFloat) {
        var rects: [CGRect] = []
        for index in 0..<3 {
            let point = offset(Self.nodeAngle(index))
            rects.append(CGRect(x: point.x - node.width / 2, y: point.y - node.height / 2,
                                width: node.width, height: node.height))
            let tip = offset(Self.arrowAngle(index))
            rects.append(CGRect(x: tip.x - arrow, y: tip.y - arrow, width: 2 * arrow, height: 2 * arrow))
        }
        rects.append(CGRect(x: -radius - 1, y: -radius - 1, width: 2 * radius + 2, height: 2 * radius + 2))
        return (rects.map(\.minX).min() ?? 0, rects.map(\.maxX).max() ?? 0,
                rects.map(\.minY).min() ?? 0, rects.map(\.maxY).max() ?? 0)
    }

    /// The box the ring needs.
    var size: CGSize {
        let box = extents
        return CGSize(width: ceil(box.maxX - box.minX), height: ceil(box.maxY - box.minY))
    }

    /// The circle's centre in that box.
    var center: CGPoint {
        let box = extents
        return CGPoint(x: -box.minX, y: -box.minY)
    }

    func point(_ degrees: Double) -> CGPoint {
        let point = offset(degrees)
        return CGPoint(x: center.x + point.x, y: center.y + point.y)
    }
}

/// Plan → Act → Observe → repeat, drawn as a ring with the current phase
/// lit (filled, white words, a glow when the card is lit). The ring never
/// turns: only the lit phase changes, and under Reduce Motion it
/// crossfades. One VoiceOver element: the loop and where the run is.
struct PageLoopRing: View {
    let step: Int
    @Environment(\.interactiveTheme) private var theme
    @ScaledMetric(relativeTo: .caption) private var scale: CGFloat = 1

    private var current: PageWithASecretContent.Phase { PageWithASecretContent.steps[step].phase }

    var body: some View {
        // The ring is drawn only below the accessibility sizes (a list
        // replaces it there), so its growth is capped where a list takes over.
        let geometry = PageLoopGeometry.standard(scale: theme.platform == .phone ? min(scale, 1.5) : 1)
        let size = geometry.size
        ZStack {
            Circle()
                .stroke(theme.increasedContrast ? theme.hairline : theme.wash(0.45), lineWidth: 2)
                .frame(width: 2 * geometry.radius, height: 2 * geometry.radius)
                .position(geometry.center)
            ForEach(0..<3, id: \.self) { index in
                let angle = PageLoopGeometry.arrowAngle(index)
                Image(systemName: "arrowtriangle.right.fill")
                    .font(.system(size: geometry.arrow, weight: .bold))
                    .foregroundStyle(theme.increasedContrast ? theme.ink2 : theme.accentText)
                    .rotationEffect(.degrees(angle + 90))
                    .position(geometry.point(angle))
            }
            VStack(spacing: 2) {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 11 * (theme.platform == .phone ? min(scale, 1.5) : 1), weight: .semibold))
                Text(PageWithASecretCopy.repeatWord)
                    .interactiveText(.caption)
            }
            .foregroundStyle(theme.ink2)
            .position(geometry.center)
            ForEach(Array(PageWithASecretContent.loop.enumerated()), id: \.offset) { index, phase in
                node(phase, size: geometry.node)
                    .position(geometry.point(PageLoopGeometry.nodeAngle(index)))
            }
        }
        .frame(width: size.width, height: size.height)
        .animation(theme.animation(InteractiveMotion.change), value: current)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(PageWithASecretCopy.loopAccessibility(step: step))
    }

    private func node(_ phase: PageWithASecretContent.Phase, size: CGSize) -> some View {
        let lit = phase == current
        let shape = Capsule()
        return Text(PageWithASecretCopy.phaseName(phase))
            .interactiveText(lit ? .calloutStrong : .caption)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .foregroundStyle(lit ? Color.white : theme.ink)
            .frame(width: size.width, height: size.height)
            .background {
                shape.fill(lit ? theme.prominent : theme.raised)
            }
            .overlay {
                if lit {
                    if theme.increasedContrast { shape.strokeBorder(Color.white.opacity(0.9), lineWidth: 1) }
                } else {
                    shape.strokeBorder(theme.wellEdge, lineWidth: 1)
                }
            }
            .shadow(color: lit && theme.lit ? theme.lumen.opacity(0.55) : .clear, radius: 8)
    }
}

/// The loop with words beside (or under) the ring: "Now" and the phase, so
/// the lit phase isn't told by colour alone. At the accessibility sizes the
/// ring goes and a numbered list says the loop.
struct PageLoopPanel: View {
    let step: Int
    /// The Mac's left column: the ring over its words.
    let stacked: Bool
    @Environment(\.interactiveTheme) private var theme

    private var current: PageWithASecretContent.Phase { PageWithASecretContent.steps[step].phase }

    var body: some View {
        if theme.usesTables {
            list
        } else if stacked {
            VStack(alignment: .leading, spacing: theme.rowSpacing) {
                PageLoopRing(step: step)
                nowLine
            }
        } else {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .center, spacing: theme.sectionSpacing) {
                    PageLoopRing(step: step)
                    nowLine.fixedSize()
                }
                VStack(alignment: .leading, spacing: theme.rowSpacing) {
                    PageLoopRing(step: step)
                    nowLine
                }
            }
        }
    }

    private var nowLine: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(PageWithASecretCopy.now.uppercased())
                .interactiveText(.eyebrow)
                .foregroundStyle(theme.accentText)
            Text(PageWithASecretCopy.phaseName(current))
                .interactiveText(.heading)
                .foregroundStyle(theme.ink)
                .contentTransition(.identity)
        }
        // The ring already says where the run is.
        .accessibilityHidden(true)
    }

    /// The accessibility sizes: "1. Plan", "2. Act · now", "3. Observe",
    /// "Then repeat."
    private var list: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(PageWithASecretCopy.loopCaption)
                .interactiveText(.heading)
                .foregroundStyle(theme.ink)
                .fixedSize(horizontal: false, vertical: true)
            ForEach(Array(PageWithASecretContent.loop.enumerated()), id: \.offset) { index, phase in
                let lit = phase == current
                Text(PageWithASecretCopy.loopListItem(index, isCurrent: lit))
                    .interactiveText(lit ? .calloutStrong : .callout)
                    .foregroundStyle(lit ? theme.accentText : theme.ink2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text(PageWithASecretCopy.loopListEnd)
                .interactiveText(.callout)
                .foregroundStyle(theme.ink2)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(PageWithASecretCopy.loopAccessibility(step: step))
    }
}

// MARK: - The run

/// The run so far, one step under another (every step up to the furthest
/// reached; Back moves the marker, never hides a step). The current step has
/// a bar at its leading edge: a shape, not only a colour.
struct PageRunLog: View {
    let state: PageWithASecretState
    @Environment(\.interactiveTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: theme.sectionSpacing) {
            ForEach(0...state.steps.furthest, id: \.self) { index in
                PageStepRow(index: index, isCurrent: index == state.steps.index) {
                    if index == PageWithASecretContent.gate {
                        // Until the reveal box arrives, the page is the
                        // card's reveal (what the agent reads): DEBUG
                        // `-InteractiveScroll reveal` brings it into view.
                        PageWebPanel(state: state)
                            .id(state.machine.isRevealed ? "page-with-a-secret-page" : InteractiveScrollID.reveal)
                        prediction
                    }
                }
                .transition(theme.transition(edge: .top))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder private var prediction: some View {
        if state.machine.asksForPrediction {
            PredictChips(PageWithASecretCopy.predictPrompt, machine: state.machine,
                         title: PageWithASecretCopy.choice) { guess in
                if state.lock(guess) {
                    InteractiveAccessibility.announce(
                        "\(InteractiveShellCopy.lockedValue): \(PageWithASecretCopy.choice(guess)). "
                        + PageWithASecretCopy.switchPromptSpoken)
                }
            }
            if state.mustSwitch {
                PageSwitchPrompt(text: PageWithASecretCopy.switchPrompt)
                    .transition(theme.transition())
            }
        } else if state.mustSwitch {
            PageSwitchPrompt(text: PageWithASecretCopy.spoiledLead)
        }
    }
}

/// What to do once the guess is locked (or in spoiled mode): switch the
/// page to what the agent reads. Next waits for it. Accent words, with an
/// arrow up to the toggle that goes at the accessibility sizes.
struct PageSwitchPrompt: View {
    let text: String
    @Environment(\.interactiveTheme) private var theme

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            if !theme.usesTables {
                Image(systemName: "arrow.up")
                    .font(.system(size: theme.platform == .phone ? 13 : 12, weight: .bold))
                    .accessibilityHidden(true)
            }
            Text(text)
                .interactiveText(.calloutStrong)
                .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(theme.accentText)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(PageWithASecretCopy.switchPromptSpoken)
    }
}

/// One step: "STEP 4 · PLAN" (a header), what it does, and what it made.
struct PageStepRow<Extra: View>: View {
    let index: Int
    let isCurrent: Bool
    let extra: Extra
    @Environment(\.interactiveTheme) private var theme

    init(index: Int, isCurrent: Bool, @ViewBuilder extra: () -> Extra) {
        self.index = index
        self.isCurrent = isCurrent
        self.extra = extra()
    }

    private var step: PageWithASecretContent.Step { PageWithASecretContent.steps[index] }

    /// The bar's width and the gap after it.
    private let inset = PageMetrics.stepInset

    var body: some View {
        VStack(alignment: .leading, spacing: theme.rowSpacing) {
            VStack(alignment: .leading, spacing: 2) {
                Text(PageWithASecretCopy.stepHeading(index).uppercased())
                    .interactiveText(.eyebrow)
                    .foregroundStyle(theme.accentText)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityLabel(PageWithASecretCopy.stepHeadingSpoken(index))
                    .accessibilityAddTraits(.isHeader)
                Text(step.line)
                    .interactiveText(.body)
                    .foregroundStyle(theme.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }
            detail
            extra
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.leading, inset)
        // The current step's bar, as tall as the step.
        .background(alignment: .leading) {
            Capsule()
                .fill(isCurrent ? (theme.increasedContrast ? theme.accentText : theme.lumen) : Color.clear)
                .frame(width: 3)
                .accessibilityHidden(true)
        }
    }

    @ViewBuilder private var detail: some View {
        switch step.detail {
        case .plan(let lines):
            PageLines(lines: lines, style: .numbered)
        case .search(let words):
            PageSearchField(words: words)
        case .page:
            EmptyView()
        case .list(let lines):
            PageLines(lines: lines, style: .bulleted)
        case .email(let email):
            PageEmailDraft(email: email)
        }
    }
}

/// A plan (numbered), a list (bulleted) or an email's lines (plain). A NEW
/// line is bold and carries the NEW tag (words, not only colour); in the
/// plan, "You never asked for this." goes under it. One VoiceOver element.
struct PageLines: View {
    enum Style { case numbered, bulleted, plain }

    let lines: [PageWithASecretContent.Line]
    let style: Style
    @Environment(\.interactiveTheme) private var theme

    private var numbered: Bool { style == .numbered }

    var body: some View {
        VStack(alignment: .leading, spacing: theme.platform == .phone ? BrandSpacing.xs + 2 : 6) {
            ForEach(Array(lines.enumerated()), id: \.offset) { index, line in
                row(index, line)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(PageWithASecretCopy.linesAccessibility(lines, numbered: numbered))
    }

    private func row(_ index: Int, _ line: PageWithASecretContent.Line) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: PageMetrics.markerSpacing) {
            if style != .plain {
                Group {
                    if line.isDone {
                        Image(systemName: "checkmark")
                            .font(.system(size: theme.platform == .phone ? 12 : 11, weight: .bold))
                    } else if numbered {
                        Text("\(index + 1).")
                            .monospacedDigit()
                    } else {
                        Text("\u{2022}")
                    }
                }
                .interactiveText(.callout)
                .foregroundStyle(line.isNew ? theme.accentText : theme.ink2)
            }
            VStack(alignment: .leading, spacing: 4) {
                lineText(line)
                if line.isNew && numbered {
                    Text(PageWithASecretCopy.neverAsked)
                        .interactiveText(.caption)
                        .foregroundStyle(theme.accentText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    @ViewBuilder private func lineText(_ line: PageWithASecretContent.Line) -> some View {
        let words = Text(PageWithASecretContent.breakable(line.text))
            .interactiveText(line.isNew ? .calloutStrong : .callout)
            .foregroundStyle(line.isNew ? theme.ink : (line.isDone ? theme.ink2 : theme.ink))
            .fixedSize(horizontal: false, vertical: true)
        if line.isDone {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                words
                Text(PageWithASecretCopy.doneTag)
                    .interactiveText(.caption)
                    .foregroundStyle(theme.ink2)
            }
        } else if line.isNew {
            // The tag leads its words (they wrap beside it), or sits above
            // them at the accessibility sizes.
            if theme.usesTables {
                VStack(alignment: .leading, spacing: 4) {
                    PageNewTag()
                    words
                }
            } else {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    PageNewTag()
                    words
                }
            }
        } else {
            words
        }
    }
}

/// "NEW": white on the prominent fill. The words around it say "New line"
/// to VoiceOver.
struct PageNewTag: View {
    @Environment(\.interactiveTheme) private var theme

    var body: some View {
        Text(PageWithASecretCopy.newTag)
            .interactiveText(.eyebrow)
            .foregroundStyle(Color.white)
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(theme.prominent, in: Capsule())
            .overlay {
                if theme.increasedContrast { Capsule().strokeBorder(Color.white.opacity(0.9), lineWidth: 1) }
            }
            .fixedSize()
            .accessibilityHidden(true)
    }
}

/// The search the agent runs, as a search field.
struct PageSearchField: View {
    let words: String
    @Environment(\.interactiveTheme) private var theme

    var body: some View {
        // A capsule, or at the accessibility sizes (where the words take
        // three lines) a rounded box, so it doesn't swell into an oval.
        let shape = RoundedRectangle(cornerRadius: theme.usesTables ? 12 : 999, style: .continuous)
        HStack(spacing: 8) {
            if !theme.usesTables {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: theme.platform == .phone ? 13 : 12, weight: .semibold))
                    .foregroundStyle(theme.ink2)
            }
            Text(words)
                .interactiveText(theme.pageMachineRole)
                .foregroundStyle(theme.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, PageMetrics.searchPadding)
        .padding(.vertical, 8)
        .background(theme.raised, in: shape)
        .overlay(shape.strokeBorder(theme.wellEdge, lineWidth: 1))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(PageWithASecretCopy.searchAccessibility(words))
    }
}

/// The draft email: "DRAFT · not sent", who it's to, its lines (the last
/// one NEW).
struct PageEmailDraft: View {
    let email: PageWithASecretContent.Email
    @Environment(\.interactiveTheme) private var theme

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: theme.platform == .phone ? BrandRadius.lg : 12, style: .continuous)
        VStack(alignment: .leading, spacing: theme.platform == .phone ? BrandSpacing.sm : 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                if !theme.usesTables {
                    Image(systemName: "envelope")
                        .font(.system(size: theme.platform == .phone ? 12 : 11, weight: .semibold))
                }
                Text(PageWithASecretCopy.draftTag)
                    .interactiveText(.eyebrow)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .foregroundStyle(theme.accentText)
            Text(PageWithASecretCopy.draftTo)
                .interactiveText(.caption)
                .foregroundStyle(theme.ink2)
            Rectangle()
                .fill(theme.increasedContrast ? theme.hairline : theme.wellEdge)
                .frame(height: 1)
            PageLines(lines: email.lines, style: .plain)
                .accessibilityHidden(true)
        }
        .padding(theme.platform == .phone ? PageMetrics.phoneWellPadding(theme) : 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.raised, in: shape)
        .overlay(shape.strokeBorder(theme.wellEdge, lineWidth: 1))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(PageWithASecretCopy.emailAccessibility(email))
    }
}

// MARK: - The page

/// The made-up recipe page the agent read, with the card's one control:
/// "You see | The agent reads" ("What you see", "What the agent reads" to
/// VoiceOver). Not drawn until a guess is locked: before that the page is
/// just a page, as a student would meet it.
///
/// - You see: the page as a browser draws it, in its own white styling.
///   The hidden line is there, white on white, small and fixed in size.
/// - What the agent reads: the page's text, as text, with the hidden line
///   in a dashed box tagged HIDDEN (a shape and words, not only colour),
///   lit in lumen when the card is lit.
struct PageWebPanel: View {
    let state: PageWithASecretState
    @Environment(\.interactiveTheme) private var theme

    private typealias Copy = PageWithASecretCopy

    var body: some View {
        let phone = theme.platform == .phone
        let shape = RoundedRectangle(cornerRadius: phone ? BrandRadius.lg : 12, style: .continuous)
        VStack(alignment: .leading, spacing: theme.rowSpacing) {
            addressBar
            // Not drawn before the guess: a toggle to "what the agent
            // reads" would tell the student it reads something else.
            if state.canSwitchView {
                InteractiveSegmented(Copy.toggleName, options: PageWithASecretContent.PageView.allCases,
                                     selection: state.view, title: Copy.viewName,
                                     accessibilityTitle: Copy.viewNameSpoken) { view in
                    if state.show(view) {
                        InteractiveAccessibility.announce(Copy.pageAccessibility(view, saysHidden: true))
                    }
                }
                .transition(theme.transition())
            }
            ZStack(alignment: .topLeading) {
                if state.view == .youSee {
                    PagePaper()
                        .transition(.opacity)
                } else {
                    PageAgentText()
                        .transition(.opacity)
                }
            }
            .animation(theme.animation(InteractiveMotion.crossfade), value: state.view)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Copy.pageAccessibility(state.view, saysHidden: state.canSwitchView))
        }
        .padding(phone ? PageMetrics.phoneWellPadding(theme) : 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.raised, in: shape)
        .overlay(shape.strokeBorder(theme.wellEdge, lineWidth: 1))
        .animation(theme.animation(InteractiveMotion.change), value: state.canSwitchView)
    }

    /// The address and "made-up page": side by side, or stacked at the
    /// accessibility sizes (both wrap; nothing scrolls sideways).
    private var addressBar: some View {
        let layout = theme.usesTables
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4))
            : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: 8))
        return layout {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                if !theme.usesTables {
                    Image(systemName: "globe")
                        .font(.system(size: theme.platform == .phone ? 12 : 11, weight: .semibold))
                        .foregroundStyle(theme.ink2)
                }
                Text(PageWithASecretContent.breakable(PageWithASecretContent.page.address))
                    .interactiveText(theme.pageMachineRole)
                    .foregroundStyle(theme.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if theme.usesTables {
                // Words only: the capsule is decoration, and at AX5 on an SE
                // a capsule that can't wrap is wider than the page.
                Text(Copy.pageTag)
                    .interactiveText(.caption)
                    .foregroundStyle(theme.ink2)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text(Copy.pageTag)
                    .interactiveText(.caption)
                    .foregroundStyle(theme.ink2)
                    .fixedSize()
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .overlay(Capsule().strokeBorder(theme.wellEdge, lineWidth: 1))
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(PageWithASecretContent.page.address), \(Copy.pageTag)")
    }
}

/// The page's own styling (a picture of a made-up web page, not the app):
/// white, with dark brown words and a brown name. Its words read at 6.8:1
/// or better (`PageWithASecretTests`); the hidden line is the page's own
/// white, so it shows as a gap.
enum PagePaperStyle {
    static let paper = Shade(0xFFFFFF)
    static let ink = Shade(0x2B2118)
    static let muted = Shade(0x5B4636)
    static let brand = Shade(0x8A4A12)
    /// The hidden line's fixed size, in points.
    static let hiddenSize: CGFloat = 9

    struct Shade: Equatable {
        let hex: UInt32
        init(_ hex: UInt32) { self.hex = hex }

        var components: (red: Double, green: Double, blue: Double) {
            (Double((hex >> 16) & 0xFF) / 255, Double((hex >> 8) & 0xFF) / 255, Double(hex & 0xFF) / 255)
        }

        var color: Color {
            let parts = components
            return Color(.sRGB, red: parts.red, green: parts.green, blue: parts.blue, opacity: 1)
        }

        /// WCAG relative luminance.
        var luminance: Double {
            func linear(_ value: Double) -> Double {
                value <= 0.03928 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
            }
            let parts = components
            return 0.2126 * linear(parts.red) + 0.7152 * linear(parts.green) + 0.0722 * linear(parts.blue)
        }

        func contrast(with other: Shade) -> Double {
            let pair = [luminance, other.luminance].sorted()
            return (pair[1] + 0.05) / (pair[0] + 0.05)
        }
    }
}

struct PagePaper: View {
    @Environment(\.interactiveTheme) private var theme

    var body: some View {
        let page = PageWithASecretContent.page
        let shape = RoundedRectangle(cornerRadius: 8, style: .continuous)
        VStack(alignment: .leading, spacing: 6) {
            // At the accessibility sizes the callout (as the page's other
            // words), so "Whiskwren" fits an SE's page whole.
            Text(page.siteName)
                .interactiveText(theme.usesTables ? .calloutStrong : .heading)
                .foregroundStyle(PagePaperStyle.brand.color)
                .fixedSize(horizontal: false, vertical: true)
            Rectangle()
                .fill(PagePaperStyle.brand.color.opacity(0.35))
                .frame(height: 1)
            Text(page.title)
                .interactiveText(.calloutStrong)
                .foregroundStyle(PagePaperStyle.ink.color)
                .fixedSize(horizontal: false, vertical: true)
            ForEach(Array(page.visibleLines.enumerated()), id: \.offset) { _, line in
                Text(line)
                    .interactiveText(.callout)
                    .foregroundStyle(PagePaperStyle.muted.color)
                    .fixedSize(horizontal: false, vertical: true)
            }
            // White text on white: there, and invisible. Small and fixed (it
            // doesn't grow with Dynamic Type): at the accessibility sizes a
            // growing invisible line would be a blank block taller than an
            // SE's screen, and before the guess any big gap is a hint. Its
            // words are never lost: the agent's view and VoiceOver say them.
            Text(page.hiddenLine)
                .font(.system(size: PagePaperStyle.hiddenSize))
                .foregroundStyle(PagePaperStyle.paper.color)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityHidden(true)
        }
        .padding(PageMetrics.paperPadding(theme))
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(PagePaperStyle.paper.color, in: shape)
        // One layer: the card's light-mode shadow (the shell's) would
        // otherwise shadow each line, and a shadow would show the white
        // line on the white page.
        .compositingGroup()
        .overlay(shape.strokeBorder(theme.increasedContrast ? theme.hairline : theme.wellEdge, lineWidth: 1))
    }
}

/// The page as the agent reads it: its text, line by line, straight on the
/// card (no page around it: this is the text, not a picture), the hidden
/// line in a dashed box tagged HIDDEN.
struct PageAgentText: View {
    @Environment(\.interactiveTheme) private var theme

    var body: some View {
        let page = PageWithASecretContent.page
        let box = RoundedRectangle(cornerRadius: 8, style: .continuous)
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(([page.siteName, page.title] + page.visibleLines).enumerated()), id: \.offset) { _, line in
                Text(PageWithASecretContent.breakable(line))
                    .interactiveText(theme.pageMachineRole)
                    .foregroundStyle(theme.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(PageWithASecretCopy.hiddenTag)
                    .interactiveText(.eyebrow)
                    .foregroundStyle(theme.accentText)
                    .fixedSize(horizontal: false, vertical: true)
                Text(PageWithASecretContent.breakable(page.hiddenLine))
                    .interactiveText(theme.pageMachineRole)
                    .foregroundStyle(theme.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(PageMetrics.hiddenBoxPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(theme.wash(0.16), in: box)
            .overlay(box.strokeBorder(theme.increasedContrast ? theme.accentText : theme.lumen,
                                      style: StrokeStyle(lineWidth: theme.increasedContrast ? 2 : 1.5, dash: [5, 4])))
            .shadow(color: theme.lit ? theme.lumen.opacity(0.45) : .clear, radius: 10)
            Text(PageWithASecretCopy.agentReadsNote)
                .interactiveText(.caption)
                .foregroundStyle(theme.ink2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// The run's paddings, named so the iPhone's AX5 word-fit test
/// (`PageWithASecretCardLayoutTests`) measures the room each line really
/// has on an SE.
enum PageMetrics {
    /// A step's leading bar and the gap after it.
    static let stepInset: CGFloat = 13
    /// The page panel's and the email's padding on the iPhone (less at
    /// the accessibility sizes, where every point of an SE's width is a
    /// letter).
    static func phoneWellPadding(usesTables: Bool) -> CGFloat { usesTables ? BrandSpacing.sm : BrandSpacing.md }
    static func phoneWellPadding(_ theme: InteractiveTheme) -> CGFloat { phoneWellPadding(usesTables: theme.usesTables) }
    /// The made-up page's own padding (both platforms).
    static func paperPadding(usesTables: Bool) -> CGFloat { usesTables ? 8 : 12 }
    static func paperPadding(_ theme: InteractiveTheme) -> CGFloat { paperPadding(usesTables: theme.usesTables) }
    /// The hidden line's dashed box.
    static let hiddenBoxPadding: CGFloat = 10
    /// The search field's sides.
    static let searchPadding: CGFloat = 14
    /// Between a plan or list line's number (or bullet) and its words.
    static let markerSpacing: CGFloat = 8
}

extension InteractiveTheme {
    /// The page's machine text (the address, the search, the agent's view):
    /// monospaced, except at the accessibility sizes, where a monospaced
    /// line holds 8 or 9 characters on an SE and "assistants:" would break
    /// inside the word. There the agent's view keeps its dashed box and
    /// tag, and the text is the proportional callout.
    var pageMachineRole: InteractiveTextRole { usesTables ? .callout : .machine }
}
