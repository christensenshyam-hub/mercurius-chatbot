import SwiftUI
import DesignSystem

// Delete the Gender Box's pieces, drawn on both platforms with the card's
// theme (`\.interactiveTheme`): the iPhone stacks them
// (`GenderBoxPhoneCard`); the Mac puts the résumés left and the weights
// right, with the two new résumés under both, next to the guess and the
// control (`NightGenderBoxCard`). Every word comes from `GenderBoxCopy`,
// every number from `GenderBoxContent`.

/// The card's content inside the shell: the hook and its label, the past
/// résumés, what the toy learned, the two new résumés, the guess, the one
/// control and the reveal.
struct GenderBoxCardBody: View {
    let state: GenderBoxState

    @Environment(\.interactiveTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: theme.sectionSpacing) {
            // The hook in `ink` and the slate's label right under it, before
            // the résumés and the guess, as every card opens.
            VStack(alignment: .leading, spacing: theme.rowSpacing) {
                Text(GenderBoxCopy.hook)
                    .interactiveText(.body)
                    .foregroundStyle(theme.ink)
                    .fixedSize(horizontal: false, vertical: true)
                LabelLine(GenderBoxCopy.toyLabel)
            }
            if theme.platform == .mac {
                // The Mac: the résumés left and the weights right, from
                // 500 pt (stacked below that). The two new résumés span
                // both, so their scores sit right above the guess and the
                // control (the reading column is about 540 pt: a third
                // column of score cards would leave each 110 pt).
                GenderBoxColumns(stackedSpacing: theme.sectionSpacing) {
                    pastSection
                    learnedSection
                }
                testSection
            } else {
                pastSection
                learnedSection
                testSection
            }
            if state.machine.asksForPrediction {
                PredictChips(GenderBoxCopy.predictPrompt, machine: state.machine,
                             title: GenderBoxCopy.guessTitle) { guess in
                    _ = state.lock(guess)
                }
            }
            GenderBoxToggle(state: state) { box in
                if let line = state.set(box) { InteractiveAccessibility.announce(line) }
            }
            if state.machine.isRevealed {
                reveal
                    .id(InteractiveScrollID.reveal)
                    .transition(theme.transition())
            }
        }
        .animation(theme.animation(.easeInOut(duration: 0.45)), value: state.box)
        .animation(theme.animation(.smooth(duration: 0.4)), value: state.machine.phase)
        #if DEBUG
        .task { await state.debugAutoplay() }
        #endif
    }

    // MARK: Sections

    private func heading(_ text: String) -> some View {
        Text(text)
            .interactiveText(.heading)
            .foregroundStyle(theme.ink)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityAddTraits(.isHeader)
    }

    /// The table, or (accessibility sizes) its summary in sight and the list
    /// behind "Show all 12". The hook already gives the counts to the eye,
    /// so at the other sizes the summary is the heading's VoiceOver label.
    private var pastSection: some View {
        VStack(alignment: .leading, spacing: theme.rowSpacing) {
            if theme.usesTables {
                heading(GenderBoxCopy.pastHeading)
                Text(GenderBoxCopy.pastSummary)
                    .interactiveText(.callout)
                    .foregroundStyle(theme.ink2)
                    .fixedSize(horizontal: false, vertical: true)
                GenderBoxResumeList(state: state)
            } else {
                heading(GenderBoxCopy.pastHeading)
                    .accessibilityLabel(GenderBoxCopy.pastHeadingSpoken)
                GenderBoxResumeTable(box: state.box)
            }
        }
    }

    private var learnedSection: some View {
        VStack(alignment: .leading, spacing: theme.rowSpacing) {
            heading(GenderBoxCopy.learnedHeading)
            Text(GenderBoxCopy.learnedIntro(state.box))
                .interactiveText(.callout)
                .foregroundStyle(theme.ink2)
                .fixedSize(horizontal: false, vertical: true)
            GenderBoxWeights(box: state.box)
            LabelLine(GenderBoxCopy.arithmeticLabel)
        }
    }

    private var testSection: some View {
        VStack(alignment: .leading, spacing: theme.rowSpacing) {
            heading(GenderBoxCopy.testHeading)
            Text(GenderBoxCopy.testIntro)
                .interactiveText(.callout)
                .foregroundStyle(theme.ink2)
                .fixedSize(horizontal: false, vertical: true)
            GenderBoxTestResumes(box: state.box)
        }
    }

    private var reveal: some View {
        VStack(alignment: .leading, spacing: theme.rowSpacing) {
            RevealBox(state.revealLines)
            // The payoff where the click is: the weights' growing bar sits
            // a screen above, so the reveal shows "women's" again, its bar
            // with a tick where it was. Decoration: it goes at the
            // accessibility sizes, where the result says the numbers.
            if !theme.usesTables {
                GenderBoxRevealWeight()
            }
            // The honest nuance, kept small (SLATE.md: both women gained).
            Text(GenderBoxCopy.nuance)
                .interactiveText(.caption)
                .foregroundStyle(theme.ink2)
                .fixedSize(horizontal: false, vertical: true)
            InteractiveTakeaway(GenderBoxCopy.takeawayLine, detail: GenderBoxCopy.takeawayDetail)
        }
    }
}

// MARK: - The Mac's two columns

/// Two views side by side from `twoFrom` points of width (the first takes
/// `ratio` of it, in whole points), else one above the other. A layout
/// rather than a measured width: a column width computed from a measured
/// width fed back into that width (by fractions of a point, for ever) and
/// hung the Mac's lesson.
struct GenderBoxColumns: Layout {
    var twoFrom: CGFloat = 500
    var ratio: CGFloat = 0.58
    var spacing: CGFloat = 24
    var stackedSpacing: CGFloat

    /// The columns' widths for `width`, or nil to stack.
    func columns(_ width: CGFloat?, count: Int) -> (left: CGFloat, right: CGFloat)? {
        guard count == 2, let width, width.isFinite, width >= twoFrom else { return nil }
        let left = ((width - spacing) * ratio).rounded(.down)
        return (left, max(width - spacing - left, 0))
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        if let widths = columns(proposal.width, count: subviews.count) {
            let left = subviews[0].sizeThatFits(ProposedViewSize(width: widths.left, height: nil))
            let right = subviews[1].sizeThatFits(ProposedViewSize(width: widths.right, height: nil))
            return CGSize(width: proposal.width ?? 0, height: max(left.height, right.height))
        }
        let child = ProposedViewSize(width: proposal.width, height: nil)
        let sizes = subviews.map { $0.sizeThatFits(child) }
        let height = sizes.map(\.height).reduce(0, +) + stackedSpacing * CGFloat(max(sizes.count - 1, 0))
        return CGSize(width: proposal.width ?? (sizes.map(\.width).max() ?? 0), height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        if let widths = columns(bounds.width, count: subviews.count) {
            subviews[0].place(at: bounds.origin, anchor: .topLeading,
                              proposal: ProposedViewSize(width: widths.left, height: nil))
            subviews[1].place(at: CGPoint(x: bounds.minX + widths.left + spacing, y: bounds.minY), anchor: .topLeading,
                              proposal: ProposedViewSize(width: widths.right, height: nil))
            return
        }
        var y = bounds.minY
        let child = ProposedViewSize(width: bounds.width, height: nil)
        for subview in subviews {
            subview.place(at: CGPoint(x: bounds.minX, y: y), anchor: .topLeading, proposal: child)
            y += subview.sizeThatFits(child).height + stackedSpacing
        }
    }
}

// MARK: - The strike-through

/// A line drawn through a deleted thing (the gender box): it draws across
/// from the leading edge, or (Reduce Motion) fades in. For one line of text
/// that can't wrap (the table's cells, the weights' names); a line that may
/// wrap takes `GenderBoxStruckLines`.
struct GenderBoxStruck: ViewModifier {
    let struck: Bool
    @Environment(\.interactiveTheme) private var theme

    func body(content: Content) -> some View {
        content.overlay {
            GenderBoxStrikeLine()
                .trim(from: 0, to: struck || theme.reduceMotion ? 1 : 0)
                .stroke(theme.ink, style: StrokeStyle(lineWidth: theme.increasedContrast ? 2 : 1.5, lineCap: .round))
                .opacity(struck ? 1 : 0)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }
}

/// The strike-through for text that may wrap ("Gender box: woman" on a
/// new résumé, or in the accessibility sizes' list): the text's own, so
/// every line is struck (it crossfades with the change).
struct GenderBoxStruckLines: ViewModifier {
    let struck: Bool
    @Environment(\.interactiveTheme) private var theme

    func body(content: Content) -> some View {
        content.strikethrough(struck, color: theme.ink)
    }
}

struct GenderBoxStrikeLine: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        return path
    }
}

// MARK: - Club lines

/// A club line with the toy's words picked out (accent and bold), so the
/// student sees what the scorer reads.
struct GenderBoxClubsText: View {
    let clubs: [GenderBoxClub]
    @Environment(\.interactiveTheme) private var theme

    var body: some View {
        if clubs.isEmpty {
            Text(GenderBoxCopy.noClubs)
                .foregroundStyle(theme.ink3)
                .fixedSize(horizontal: false, vertical: true)
        } else {
            Text(Self.marked(clubs.map(GenderBoxCopy.club).joined(separator: ", "), highlight: theme.accentText))
                .foregroundStyle(theme.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// `text` with each of the toy's words in `highlight`, bold.
    static func marked(_ text: String, highlight: Color) -> AttributedString {
        var marked = AttributedString(text)
        var mark = AttributeContainer()
        mark.foregroundColor = highlight
        mark.inlinePresentationIntent = .stronglyEmphasized
        for feature in GenderBoxFeature.allCases {
            guard let word = GenderBoxCopy.featureWord(feature) else { continue }
            var from = marked.startIndex
            while from < marked.endIndex, let range = marked[from...].range(of: word) {
                marked[range].mergeAttributes(mark)
                from = range.upperBound
            }
        }
        return marked
    }
}

// MARK: - The past résumés

/// The 12 past résumés as a table: gender box, clubs, hired. Deleting the
/// gender box strikes its column. Each row is one VoiceOver element.
struct GenderBoxResumeTable: View {
    let box: GenderBox
    @Environment(\.interactiveTheme) private var theme

    private var deleted: Bool { box == .deleted }
    private var spacing: CGFloat { theme.platform == .phone ? 8 : 10 }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: spacing) {
                genderColumn {
                    Text(GenderBoxCopy.genderColumn)
                        .foregroundStyle(deleted ? theme.ink3 : theme.ink2)
                        .modifier(GenderBoxStruck(struck: deleted))
                }
                Text(GenderBoxCopy.clubsColumn)
                    .frame(maxWidth: .infinity, alignment: .leading)
                outcomeColumn { Text(GenderBoxCopy.hiredColumn) }
            }
            .interactiveText(.caption)
            .foregroundStyle(theme.ink2)
            .padding(.bottom, 6)
            .accessibilityHidden(true)
            ForEach(GenderBoxContent.resumes) { resume in
                // A rule under the header, and between the men and the women.
                if resume.id == 1 || resume.id == firstWoman {
                    Rectangle()
                        .fill(theme.wellEdge)
                        .frame(height: 1)
                        .accessibilityHidden(true)
                }
                row(resume)
            }
        }
    }

    private var firstWoman: Int { GenderBoxContent.women.first?.id ?? 0 }

    private func row(_ resume: GenderBoxResume) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: spacing) {
            genderColumn {
                Text(GenderBoxCopy.gender(resume.profile))
                    .foregroundStyle(deleted ? theme.ink3 : theme.ink)
                    .modifier(GenderBoxStruck(struck: deleted))
            }
            GenderBoxClubsText(clubs: resume.profile.clubs)
                .frame(maxWidth: .infinity, alignment: .leading)
            outcomeColumn { outcome(resume.hired) }
        }
        .interactiveText(.caption)
        .padding(.vertical, theme.platform == .phone ? 5 : 4)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(GenderBoxCopy.resumeSpoken(resume, box))
    }

    /// The gender column: as wide as its widest word, so every row lines up.
    private func genderColumn<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        ZStack(alignment: .leading) {
            ForEach([GenderBoxCopy.genderColumn, GenderBoxCopy.man, GenderBoxCopy.woman], id: \.self) {
                Text($0).hidden()
            }
            content()
        }
        .fixedSize()
    }

    private func outcomeColumn<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        ZStack(alignment: .leading) {
            Text(GenderBoxCopy.hiredColumn).hidden()
            outcome(true).hidden()
            outcome(false).hidden()
            content()
        }
        .fixedSize()
    }

    /// "✓ Hired" / "✕ Not hired": a glyph and a word, never colour alone.
    private func outcome(_ hired: Bool) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 3) {
            Image(systemName: hired ? "checkmark" : "xmark")
                .font(.system(size: theme.platform == .phone ? 10 : 9, weight: .bold))
                .accessibilityHidden(true)
            Text(GenderBoxCopy.outcome(hired))
        }
        .foregroundStyle(hired ? theme.ink : theme.ink2)
    }
}

/// The accessibility sizes: the summary stays (above), and the 12 résumés
/// open as text behind "Show all 12".
struct GenderBoxResumeList: View {
    let state: GenderBoxState
    @Environment(\.interactiveTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: theme.rowSpacing) {
            InteractiveActionButton(state.showsAllResumes ? GenderBoxCopy.hideAll : GenderBoxCopy.showAll,
                                    systemImage: state.showsAllResumes ? "chevron.up" : "chevron.down",
                                    accessibilityHint: GenderBoxCopy.showAllHelp) {
                state.showsAllResumes.toggle()
            }
            if state.showsAllResumes {
                ForEach(GenderBoxContent.resumes) { resume in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(GenderBoxCopy.rowTitle(resume))
                            .interactiveText(.calloutStrong)
                            .foregroundStyle(theme.ink)
                        Text(GenderBoxCopy.genderLine(resume.profile))
                            .interactiveText(.callout)
                            .foregroundStyle(state.box == .deleted ? theme.ink3 : theme.ink2)
                            .modifier(GenderBoxStruckLines(struck: state.box == .deleted))
                        GenderBoxClubsText(clubs: resume.profile.clubs)
                            .interactiveText(.callout)
                        Text(GenderBoxCopy.outcome(resume.hired))
                            .interactiveText(.callout)
                            .foregroundStyle(theme.ink2)
                    }
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(GenderBoxCopy.resumeSpoken(resume, state.box))
                }
            }
        }
    }
}

// MARK: - What it learned

/// The toy's weights: a word, what it does in words, a signed bar about
/// zero and the signed number. The iPhone puts each in one row (name, bar,
/// number); the Mac's column is narrower, so there the bar runs the
/// column's width under its name and number. At the accessibility sizes,
/// rows of text.
struct GenderBoxWeights: View {
    let box: GenderBox
    @Environment(\.interactiveTheme) private var theme

    var body: some View {
        if theme.usesTables {
            InteractiveTextTable(GenderBoxFeature.allCases.map {
                InteractiveTextTable.Row(GenderBoxCopy.featureName($0), GenderBoxCopy.weightText($0, box))
            })
        } else if theme.platform == .mac {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(GenderBoxFeature.allCases, id: \.self) { stackedRow($0) }
                stackedLegend
            }
        } else {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(GenderBoxFeature.allCases, id: \.self) { row($0) }
                legend
            }
        }
    }

    /// The Mac: the name and the number, the bar across the column, then
    /// what it does and what it was.
    private func stackedRow(_ feature: GenderBoxFeature) -> some View {
        let weight = GenderBoxContent.weight(feature, box)
        let struck = weight == nil
        let earlier = GenderBoxCopy.earlier(feature, box)
        return VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(GenderBoxCopy.featureName(feature))
                    .interactiveText(.calloutStrong)
                    .foregroundStyle(struck ? theme.ink3 : theme.ink)
                    .fixedSize()
                    .modifier(GenderBoxStruck(struck: struck))
                Spacer(minLength: 8)
                Text(weight.map(GenderBoxContent.signed) ?? " ")
                    .interactiveText(.calloutStrong)
                    .monospacedDigit()
                    .foregroundStyle(theme.ink)
                    .contentTransition(theme.reduceMotion ? .opacity : .numericText())
            }
            GenderBoxBar(weight: weight, box: box, earlier: earlier, height: 20)
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(weight.map { GenderBoxCopy.effect(GenderBoxContent.effect($0)) } ?? GenderBoxCopy.deletedTag)
                Spacer(minLength: 8)
                if let earlier {
                    Text(GenderBoxCopy.was(earlier))
                        .monospacedDigit()
                        .transition(.opacity)
                }
            }
            .interactiveText(.caption)
            .foregroundStyle(theme.ink2)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(GenderBoxCopy.weightSpoken(feature, box))
    }

    private var stackedLegend: some View {
        HStack {
            Text(GenderBoxCopy.axisDown)
            Spacer(minLength: 8)
            Text(GenderBoxCopy.axisUp)
        }
        .interactiveText(.caption)
        .foregroundStyle(theme.ink2)
        .accessibilityHidden(true)
    }

    private func row(_ feature: GenderBoxFeature) -> some View {
        let weight = GenderBoxContent.weight(feature, box)
        let struck = weight == nil
        let earlier = GenderBoxCopy.earlier(feature, box)
        return HStack(alignment: .center, spacing: 10) {
            nameColumn {
                VStack(alignment: .leading, spacing: 1) {
                    Text(GenderBoxCopy.featureName(feature))
                        .interactiveText(.calloutStrong)
                        .foregroundStyle(struck ? theme.ink3 : theme.ink)
                        .modifier(GenderBoxStruck(struck: struck))
                    Text(weight.map { GenderBoxCopy.effect(GenderBoxContent.effect($0)) } ?? GenderBoxCopy.deletedTag)
                        .interactiveText(.caption)
                        .foregroundStyle(theme.ink2)
                }
            }
            GenderBoxBar(weight: weight, box: box, earlier: earlier)
                .frame(maxWidth: .infinity)
            numberColumn {
                VStack(alignment: .trailing, spacing: 1) {
                    Text(weight.map(GenderBoxContent.signed) ?? " ")
                        .interactiveText(.calloutStrong)
                        .monospacedDigit()
                        .foregroundStyle(theme.ink)
                        .contentTransition(theme.reduceMotion ? .opacity : .numericText())
                    if let earlier {
                        Text(GenderBoxCopy.was(earlier))
                            .interactiveText(.caption)
                            .foregroundStyle(theme.ink2)
                            .transition(.opacity)
                    }
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(GenderBoxCopy.weightSpoken(feature, box))
    }

    private var legend: some View {
        HStack(spacing: 10) {
            nameColumn { EmptyView() }
            HStack {
                Text(GenderBoxCopy.axisDown)
                Spacer(minLength: 4)
                Text(GenderBoxCopy.axisUp)
            }
            .frame(maxWidth: .infinity)
            numberColumn { EmptyView() }
        }
        .interactiveText(.caption)
        .foregroundStyle(theme.ink2)
        .accessibilityHidden(true)
    }

    /// As wide as the widest name and effect line.
    private func nameColumn<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        ZStack(alignment: .leading) {
            ForEach(GenderBoxFeature.allCases, id: \.self) {
                Text(GenderBoxCopy.featureName($0)).interactiveText(.calloutStrong).hidden()
            }
            ForEach([GenderBoxEffect.up, .upALittle, .down, .downALittle], id: \.self) {
                Text(GenderBoxCopy.effect($0)).interactiveText(.caption).hidden()
            }
            content()
        }
        .fixedSize()
    }

    /// As wide as the widest number and "was" line.
    private func numberColumn<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        ZStack(alignment: .trailing) {
            Text(GenderBoxContent.signed(-GenderBoxContent.barMaximum))
                .interactiveText(.calloutStrong).monospacedDigit().hidden()
            Text(GenderBoxCopy.was(-GenderBoxContent.barMaximum)).interactiveText(.caption).hidden()
            content()
        }
        .fixedSize()
    }
}

/// One signed bar about a zero line: left for "pushes down", right for
/// "pushes up", its length the weight on the card's one scale. The words
/// and the signed number say the same (never colour alone). Under Reduce
/// Motion a new length crossfades instead of growing.
///
/// `earlier`: the weight before the gender box went, drawn as a tick at
/// that length (a notch through the bar, and a line a little taller than
/// it), so "women's" visibly grew without flipping back. Static, so Reduce
/// Motion changes nothing; the row's "was −1.21" says the same in words.
struct GenderBoxBar: View {
    let weight: Double?
    let box: GenderBox
    var earlier: Double? = nil
    var height: CGFloat = 24
    @Environment(\.interactiveTheme) private var theme

    private static let thickness: CGFloat = 12
    /// The tick's height: 4 pt past the bar on each side.
    static let tickHeight: CGFloat = thickness + 8

    var body: some View {
        GeometryReader { geo in
            let half = geo.size.width / 2
            ZStack(alignment: .topLeading) {
                // The scale's track (decoration: the bars share one scale).
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(theme.raised)
                    .frame(width: geo.size.width, height: Self.thickness)
                    .offset(y: (geo.size.height - Self.thickness) / 2)
                Rectangle()
                    .fill(theme.increasedContrast ? theme.ink2 : theme.ink3)
                    .frame(width: 1, height: geo.size.height)
                    .offset(x: half - 0.5)
                if let weight {
                    let length = half * GenderBoxContent.barFraction(weight)
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        // Both read at 3:1 or better on the card in light
                        // and dark (lumen 7.6 / 4.5, accentText 8.7 / 6.3);
                        // the side, the sign and the words say the same.
                        .fill(weight < 0 ? theme.lumen : theme.accentText)
                        .overlay {
                            if theme.increasedContrast {
                                RoundedRectangle(cornerRadius: 3, style: .continuous)
                                    .strokeBorder(theme.ink, lineWidth: 1)
                            }
                        }
                        .frame(width: length, height: Self.thickness)
                        .offset(x: weight < 0 ? half - length : half, y: (geo.size.height - Self.thickness) / 2)
                        .id(theme.reduceMotion ? box.rawValue : "bar")
                        .transition(.opacity)
                }
                if let earlier {
                    let reach = half * GenderBoxContent.barFraction(earlier)
                    let x = earlier < 0 ? half - reach : half + reach
                    Rectangle()
                        .fill(theme.surface)
                        .frame(width: 4, height: Self.thickness)
                        .offset(x: x - 2, y: (geo.size.height - Self.thickness) / 2)
                        .transition(.opacity)
                    Rectangle()
                        .fill(theme.increasedContrast ? theme.ink : theme.ink2)
                        .frame(width: 2, height: Self.tickHeight)
                        .offset(x: x - 1, y: (geo.size.height - Self.tickHeight) / 2)
                        .transition(.opacity)
                }
            }
        }
        .frame(height: height)
        .accessibilityHidden(true)
    }
}

/// The reveal's "women's" row: its name and "−1.21 → −1.53" above its bar
/// at the new length, with a tick where it was, across the reveal's width
/// (the same on both platforms; the weights a screen above are out of view
/// when the student deletes the box). Decoration: the result says the same
/// numbers, so VoiceOver skips it, and the accessibility sizes leave it out.
struct GenderBoxRevealWeight: View {
    @Environment(\.interactiveTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(GenderBoxCopy.featureName(.womens))
                    .foregroundStyle(theme.ink)
                Spacer(minLength: 8)
                Text(GenderBoxCopy.revealWeightChange)
                    .monospacedDigit()
                    .foregroundStyle(theme.ink)
            }
            .interactiveText(.calloutStrong)
            GenderBoxBar(weight: GenderBoxContent.weight(.womens, .deleted), box: .deleted,
                         earlier: GenderBoxContent.weight(.womens, .kept), height: GenderBoxBar.tickHeight)
        }
        .accessibilityHidden(true)
    }
}

// MARK: - The two new résumés

/// The two test résumés, identical but for "women's", and their scores out
/// of 100: side by side, or stacked at the accessibility sizes.
struct GenderBoxTestResumes: View {
    let box: GenderBox
    @Environment(\.interactiveTheme) private var theme

    var body: some View {
        let layout = theme.usesTables
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: theme.chipSpacing + 2))
            : AnyLayout(HStackLayout(alignment: .top, spacing: theme.chipSpacing + 2))
        layout {
            card(GenderBoxContent.testWith, title: GenderBoxCopy.testWithTitle, lit: true)
            card(GenderBoxContent.testWithout, title: GenderBoxCopy.testWithoutTitle, lit: false)
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private func card(_ profile: GenderBoxProfile, title: String, lit: Bool) -> some View {
        let shape = RoundedRectangle(cornerRadius: theme.platform == .phone ? BrandRadius.lg : 12, style: .continuous)
        let deleted = box == .deleted
        return VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .interactiveText(.calloutStrong)
                .foregroundStyle(theme.accentText)
                .fixedSize(horizontal: false, vertical: true)
            Text(GenderBoxCopy.genderLine(profile))
                .interactiveText(.caption)
                .foregroundStyle(deleted ? theme.ink3 : theme.ink2)
                .fixedSize(horizontal: false, vertical: true)
                .modifier(GenderBoxStruckLines(struck: deleted))
            ForEach(profile.clubs, id: \.self) { club in
                GenderBoxClubsText(clubs: [club])
                    .interactiveText(.caption)
            }
            Spacer(minLength: theme.platform == .phone ? 6 : 4)
            Text("\(GenderBoxContent.score(profile, box))")
                .interactiveText(.number)
                .foregroundStyle(theme.ink)
                .contentTransition(theme.reduceMotion ? .opacity : .numericText())
            Text(GenderBoxCopy.scoreCaption)
                .interactiveText(.caption)
                .foregroundStyle(theme.ink2)
        }
        .padding(theme.platform == .phone ? BrandSpacing.md : 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(theme.raised, in: shape)
        .overlay(shape.strokeBorder(lit ? (theme.increasedContrast ? theme.accentText : theme.wash(0.6)) : theme.wellEdge,
                                    lineWidth: lit ? 1.5 : 1))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(GenderBoxCopy.testSpoken(profile, box))
    }
}

// MARK: - The one control

/// "Gender box: kept | deleted". Off (and saying "Make your guess first.")
/// until a guess is locked. Each option says the control's name to
/// VoiceOver ("Gender box: deleted"); on the Mac both are in the Tab loop,
/// Space or Return picks, and ←/→ move between them while one has focus.
struct GenderBoxToggle: View {
    let state: GenderBoxState
    let onSet: (GenderBox) -> Void
    @Environment(\.interactiveTheme) private var theme

    var body: some View {
        let enabled = state.machine.canExplore
        let layout = theme.usesTables
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: theme.chipSpacing))
            : AnyLayout(HStackLayout(alignment: .center, spacing: theme.chipSpacing))
        VStack(alignment: .leading, spacing: theme.chipSpacing) {
            layout {
                Text(GenderBoxCopy.controlLabel)
                    .interactiveText(.heading)
                    .foregroundStyle(enabled ? theme.ink : theme.ink3)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityHidden(true)
                ForEach(GenderBox.allCases, id: \.self) { option in
                    chip(option, enabled: enabled)
                }
            }
            if !enabled {
                Text(InteractiveShellCopy.guessFirst)
                    .interactiveText(.caption)
                    .foregroundStyle(theme.ink2)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityHidden(true)
                    .transition(.opacity)
            }
        }
        #if os(iOS)
        .sensoryFeedback(.selection, trigger: state.box)
        #endif
    }

    private func chip(_ option: GenderBox, enabled: Bool) -> some View {
        InteractiveChip(GenderBoxCopy.boxTitle(option), isSelected: state.box == option, isEnabled: enabled,
                        isFirst: state.machine.spoiled && option == .deleted,
                        accessibilityLabel: GenderBoxCopy.boxAccessibility(option),
                        accessibilityHint: GenderBoxCopy.boxHelp(option),
                        onArrow: { arrow in onSet(GenderBox.after(arrow)) }) {
            if option != state.box { onSet(option) }
        }
        .accessibilityValue(enabled ? "" : InteractiveShellCopy.guessFirst)
        #if os(macOS)
        .help(GenderBoxCopy.boxHelp(option))
        #endif
    }
}
