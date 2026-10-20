#if os(macOS)
import SwiftUI
import DesignSystem
import CurriculumFeature

/// One unit's page of the learning path on the Mac, in Night Studio
/// (docs/mac-night-studio/SPEC.md §5.2). It replaces the iPhone's winding
/// path (`CurriculumView`) in the Mac's detail column:
///
/// - **The unit's cover**: a lit card (not a gradient) with the unit's
///   title, its summary, a meter of its lessons ending at the check, and
///   where the student is in it.
/// - **The thread**: one row per lesson, then the unit check, on a thread
///   of light that is lit where the student has been. Done lessons are
///   marked done; the current one is lit, with its objective and the one
///   prominent button (Return); later ones show their objective and, in
///   place of a padlock, the lesson that opens them ("Opens after 1.2").
/// - **Next unit**: its title and summary, one click away.
///
/// The gating is the iPhone's (`CurriculumProgressStore.isLessonUnlocked`,
/// `isUnitTestUnlocked`), only said in words. Nothing here talks to the
/// server. No top inset: on macOS 26 a top `safeAreaInset` blanked the
/// path once the sidebar folded away in a narrow window (PR #47 step 05).
struct MacUnitPage: View {
    let unit: CurriculumFeature.Unit
    let progress: CurriculumProgressStore
    let onStartLesson: (Lesson) -> Void
    let onStartUnitTest: (CurriculumFeature.Unit) -> Void
    /// Opens another unit's page (the next-unit row).
    let onOpenUnit: (String) -> Void

    /// The page's reading column.
    static let columnWidth: CGFloat = MacLayout.readableWidth
    /// Below this column width the cover's big numeral goes.
    static let numeralMinColumn: CGFloat = 560
    /// Below this row width a row's trailing note moves under its title.
    static let rowMetaMinWidth: CGFloat = 420

    @NightSettings private var night
    @State private var detailWidth: CGFloat = 1040

    var body: some View {
        let gutter = Night.Space.pageGutter(forWidth: detailWidth)
        let column = min(Self.columnWidth, max(detailWidth - 2 * gutter, 0))
        let page = Self.page(unit: unit, progress: progress)
        ScrollView {
            VStack(alignment: .leading, spacing: Night.Space.section) {
                cover(page, showsNumeral: column >= Self.numeralMinColumn)
                thread(page, stacked: column - 52 < Self.rowMetaMinWidth)
                if let next = page.nextUnit {
                    nextUnitRow(next)
                }
            }
            .padding(.horizontal, gutter)
            .padding(.top, 28)
            .padding(.bottom, 40)
            .frame(maxWidth: Self.columnWidth + 2 * gutter)
            .frame(maxWidth: .infinity)
        }
        .scrollBounceBehavior(.basedOnSize)
        .background {
            NightCanvas(pools: .both, stars: true)
                .nightExtendsUnderSidebar(night)
        }
        .background {
            GeometryReader { geo in
                Color.clear
                    .onAppear { detailWidth = geo.size.width }
                    .onChange(of: geo.size.width) { _, width in detailWidth = width }
            }
        }
        .navigationTitle("Learning Path")
        .navigationSubtitle(Self.subtitle(unitId: unit.id))
    }

    // MARK: - The model (pure, tested)

    /// What one lesson's row shows.
    enum LessonState: Equatable {
        /// Completed: marked done, opens for review.
        case done
        /// The unit's first unlocked lesson not yet done: lit, with its
        /// objective and the page's prominent button. `isFrontier`: it's
        /// the student's next stop on the whole path ("You're here").
        case current(isFrontier: Bool, inProgress: Bool)
        /// Unlocked and not done, past the current one (progress merged out
        /// of order): it opens, without the prominent button.
        case open
        /// Locked: it opens once `after` is done.
        case locked(after: Lesson)
    }

    struct LessonStop: Equatable, Identifiable {
        let lesson: Lesson
        /// "1.3": the unit's number and the lesson's.
        let code: String
        let state: LessonState
        var id: String { lesson.id }
    }

    enum CheckState: Equatable {
        /// Opens once every lesson is done; `after` is the last one not done.
        case locked(after: Lesson?)
        case open
        case mastered
    }

    struct Page: Equatable {
        let unit: CurriculumFeature.Unit
        let unitNumber: Int
        let lessons: [LessonStop]
        let check: CheckState
        /// The check's question count (0 if it has none).
        let questionCount: Int
        let done: Int
        let nextUnit: CurriculumFeature.Unit?

        /// The cover's eyebrow status.
        var status: String {
            if check == .mastered { return "Mastered" }
            if done == unit.lessons.count { return "All lessons done" }
            if done > 0 || lessons.contains(where: { if case .current(_, true) = $0.state { return true }; return false }) {
                return "In progress"
            }
            return "Not started"
        }

        /// Whether the check is the page's prominent action (every lesson
        /// done, not yet mastered).
        var checkIsPrimary: Bool { check == .open }
    }

    @MainActor
    static func page(unit: CurriculumFeature.Unit, progress: CurriculumProgressStore) -> Page {
        let number = Int(unit.number) ?? 0
        let frontier = progress.frontierLessonId
        var foundCurrent = false
        var stops: [LessonStop] = []
        for (index, lesson) in unit.lessons.enumerated() {
            let state: LessonState
            if progress.isCompleted(lesson.id) {
                state = .done
            } else if !progress.isLessonUnlocked(lesson, in: unit), index > 0 {
                state = .locked(after: unit.lessons[index - 1])
            } else if !foundCurrent {
                foundCurrent = true
                state = .current(isFrontier: frontier == lesson.id,
                                 inProgress: progress.state(of: lesson.id) == .inProgress)
            } else {
                state = .open
            }
            stops.append(LessonStop(lesson: lesson, code: code(unitNumber: number, lesson: lesson), state: state))
        }
        let check: CheckState
        if progress.isUnitMastered(unit.id) {
            check = .mastered
        } else if progress.isUnitTestUnlocked(unit) {
            check = .open
        } else {
            check = .locked(after: unit.lessons.last(where: { !progress.isCompleted($0.id) }))
        }
        let units = MercuriusCurriculum.units
        let nextUnit = units.firstIndex(where: { $0.id == unit.id }).flatMap { index in
            units.indices.contains(index + 1) ? units[index + 1] : nil
        }
        return Page(unit: unit, unitNumber: number, lessons: stops, check: check,
                    questionCount: MercuriusCurriculum.unitTest(for: unit.id)?.questions.count ?? 0,
                    done: progress.completedCount(in: unit), nextUnit: nextUnit)
    }

    /// "1.3".
    static func code(unitNumber: Int, lesson: Lesson) -> String { "\(unitNumber).\(lesson.number)" }

    /// "Unit 1 of 8", under "Learning Path" in the toolbar.
    static func subtitle(unitId: String) -> String {
        let units = MercuriusCurriculum.units
        guard let index = units.firstIndex(where: { $0.id == unitId }) else { return "All units" }
        return "Unit \(index + 1) of \(units.count)"
    }

    // MARK: - Words (held to the honest-copy register by NightCopyTests)

    static func coverEyebrow(_ page: Page) -> String { "Unit \(page.unit.number) · \(page.status)" }

    static func coverMeterLabel(_ page: Page) -> String {
        let total = page.unit.lessons.count
        switch page.check {
        case .mastered: return "\(total) of \(total) lessons · check passed"
        case .open: return "\(total) of \(total) lessons · the unit check is open"
        case .locked: return "\(page.done) of \(total) lessons · then the unit check"
        }
    }

    static func opensAfter(_ code: String) -> String { "Opens after \(code)" }

    static func currentEyebrow(code: String, isFrontier: Bool) -> String {
        isFrontier ? "Lesson \(code) · You're here" : "Lesson \(code) · Next in this unit"
    }

    static func currentButton(code: String, inProgress: Bool) -> String {
        inProgress ? "Continue Lesson \(code)" : "Start Lesson \(code)"
    }

    static func checkTitle(_ page: Page) -> String { "Unit \(page.unitNumber) check" }

    static func checkDetail(questionCount: Int) -> String {
        questionCount > 0
            ? "\(questionCount) questions, then one written answer Merc grades."
            : "A short check on the whole unit, then one written answer Merc grades."
    }

    static func checkNote(_ page: Page) -> String? {
        switch page.check {
        case .locked(let after):
            return after.map { opensAfter(code(unitNumber: page.unitNumber, lesson: $0)) }
                ?? "Opens after every lesson is done"
        case .open: return nil
        case .mastered: return "Mastered"
        }
    }

    static let takeCheck = "Take the check"

    static func lessonAccessibility(_ stop: LessonStop) -> String {
        let place = "Lesson \(stop.code)"
        switch stop.state {
        case .done:
            return "\(place), done: \(stop.lesson.title)."
        case .current(let isFrontier, let inProgress):
            let where_ = isFrontier ? "you're here" : "next in this unit"
            let progress = inProgress ? ", in progress" : ""
            return "\(place), \(where_)\(progress): \(stop.lesson.title). \(stop.lesson.objective)"
        case .open:
            return "\(place), open: \(stop.lesson.title). \(stop.lesson.objective)"
        case .locked(let after):
            let unit = stop.code.split(separator: ".").first.map(String.init) ?? ""
            let afterCode = unit.isEmpty ? "\(after.number)" : "\(unit).\(after.number)"
            return "\(place), opens after lesson \(afterCode): \(stop.lesson.title). \(stop.lesson.objective)"
        }
    }

    static func checkAccessibility(_ page: Page) -> String {
        let detail = checkDetail(questionCount: page.questionCount)
        switch page.check {
        case .locked(let after):
            let when = after.map { "opens after lesson \(page.unitNumber).\($0.number)" } ?? "opens after every lesson"
            return "\(checkTitle(page)), \(when): \(detail)"
        case .open:
            return "\(checkTitle(page)), open: \(detail)"
        case .mastered:
            return "\(checkTitle(page)), mastered: \(detail)"
        }
    }

    static func nextUnitLabel(_ unit: CurriculumFeature.Unit) -> String {
        "Unit \(Int(unit.number) ?? 0) · \(unit.title)"
    }

    // MARK: - The cover

    private func cover(_ page: Page, showsNumeral: Bool) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 10) {
                NightEyebrow(Self.coverEyebrow(page), systemImage: page.check == .mastered ? "checkmark.seal.fill" : nil,
                             color: page.check == .mastered ? Night.successText : Night.accentText)
                Text(page.unit.title)
                    .nightFont(.title)
                    .foregroundStyle(Night.ink)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                Text(page.unit.summary)
                    .nightFont(.callout)
                    .foregroundStyle(Night.ink2)
                    .fixedSize(horizontal: false, vertical: true)
                meter(page)
                    .padding(.top, 6)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if showsNumeral {
                Text(page.unit.number)
                    .font(NightType.lexend(56, semibold: true))
                    .tracking(-2)
                    .foregroundStyle(Night.accentText.opacity(0.18))
                    .padding(.top, -6)
                    .accessibilityHidden(true)
            }
        }
        .padding(Night.Space.card)
        .frame(maxWidth: .infinity, alignment: .leading)
        .nightLit(radius: Night.Radius.card)
    }

    /// One 5 pt capsule per lesson (lit when done; the current one in
    /// `lumen`; the rest `hairline`), then a diamond for the check.
    private func meter(_ page: Page) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                ForEach(page.lessons) { stop in
                    Capsule()
                        .fill(meterFill(stop.state))
                        .frame(height: 5)
                }
                Image(systemName: page.check == .mastered ? "diamond.fill" : "diamond")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(page.check == .mastered ? Night.successText : Night.accentText)
            }
            .frame(maxWidth: 360)
            .accessibilityHidden(true)
            Text(Self.coverMeterLabel(page))
                .nightFont(.caption)
                .foregroundStyle(Night.ink3)
        }
    }

    private func meterFill(_ state: LessonState) -> AnyShapeStyle {
        switch state {
        case .done: return Night.progressLight(increasedContrast: night.increasedContrast)
        case .current: return AnyShapeStyle(night.increasedContrast ? Night.ink3 : Night.lumen.opacity(0.4))
        case .open, .locked: return AnyShapeStyle(Night.hairline)
        }
    }

    // MARK: - The thread

    private func thread(_ page: Page, stacked: Bool) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(page.lessons.enumerated()), id: \.element.id) { index, stop in
                threadRow(isFirst: index == 0, isLast: false,
                          litAbove: index > 0 && page.lessons[index - 1].state == .done,
                          litBelow: stop.state == .done,
                          nodeTop: Self.nodeTop(stop.state)) {
                    lessonNode(stop)
                } content: {
                    lessonContent(stop, page: page, stacked: stacked)
                }
            }
            threadRow(isFirst: false, isLast: true,
                      litAbove: page.lessons.last?.state == .done, litBelow: false, nodeTop: 2) {
                checkNode(page.check)
            } content: {
                checkContent(page, stacked: stacked)
            }
        }
    }

    /// Where a row's node sits, from the row's top: the current lesson's
    /// node lines up with its card's eyebrow.
    static func nodeTop(_ state: LessonState) -> CGFloat {
        if case .current = state { return 18 }
        return 2
    }

    private func threadRow<Node: View, Content: View>(
        isFirst: Bool, isLast: Bool, litAbove: Bool, litBelow: Bool, nodeTop: CGFloat,
        @ViewBuilder node: () -> Node, @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack(alignment: .top) {
                VStack(spacing: 0) {
                    threadSegment(lit: litAbove)
                        .frame(height: nodeTop + 4)
                        .opacity(isFirst ? 0 : 1)
                    threadSegment(lit: litBelow)
                        .frame(maxHeight: .infinity)
                        .opacity(isLast ? 0 : 1)
                }
                node()
                    .padding(.top, nodeTop)
            }
            .frame(width: 40)
            .accessibilityHidden(true)

            content()
                .padding(.bottom, isLast ? 0 : 14)
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private func threadSegment(lit: Bool) -> some View {
        Rectangle()
            .fill(lit ? Night.progressLight(increasedContrast: night.increasedContrast) : AnyShapeStyle(Night.hairline))
            .frame(width: 2)
    }

    // MARK: Nodes

    @ViewBuilder
    private func lessonNode(_ stop: LessonStop) -> some View {
        switch stop.state {
        case .done:
            ZStack {
                Circle().fill(Night.progressLight(increasedContrast: night.increasedContrast))
                // White on the brand light; under Increase Contrast the
                // fill is flat `accentText` (pale in dark mode), so the
                // check takes `surface` (NightRestContrastTests).
                Image(systemName: "checkmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(night.increasedContrast ? Night.surface : .white)
            }
            .frame(width: 24, height: 24)
        case .current:
            ZStack {
                if !night.increasedContrast {
                    NightNodeHalo(still: night.reduceMotion)
                }
                Circle().fill(Night.surface).frame(width: 30, height: 30)
                Circle().strokeBorder(Night.accentText, lineWidth: 2.5).frame(width: 30, height: 30)
                nodeLabel(stop.code, color: Night.accentText)
            }
            .frame(width: 40, height: 30)
        case .open, .locked:
            ZStack {
                Circle().fill(Night.canvasTop)
                Circle().strokeBorder(Night.ink3, lineWidth: 1.5)
                nodeLabel(stop.code, color: Night.ink2)
            }
            .frame(width: 28, height: 28)
        }
    }

    private func nodeLabel(_ code: String, color: Color) -> some View {
        Text(code)
            .font(NightType.lexend(11, semibold: true))
            .monospacedDigit()
            .foregroundStyle(color)
            .minimumScaleFactor(0.8)
            .lineLimit(1)
    }

    @ViewBuilder
    private func checkNode(_ check: CheckState) -> some View {
        let shape = RoundedRectangle(cornerRadius: 5, style: .continuous)
        ZStack {
            switch check {
            case .mastered:
                shape.fill(Night.successText)
                Image(systemName: "checkmark")
                    .font(.system(size: 10, weight: .heavy))
                    .foregroundStyle(Night.surface)
                    .rotationEffect(.degrees(-45))
            case .open:
                shape.fill(Night.surface)
                shape.strokeBorder(Night.accentText, lineWidth: 2.5)
            case .locked:
                shape.fill(Night.canvasTop)
                shape.strokeBorder(Night.accentText, lineWidth: 1.5)
            }
        }
        .frame(width: 20, height: 20)
        .rotationEffect(.degrees(45))
        .frame(width: 28, height: 28)
        // The open check is the lit stop: the current lesson's halo.
        .background {
            if check == .open && !night.increasedContrast {
                NightNodeHalo(still: night.reduceMotion)
            }
        }
    }

    // MARK: Row content

    @ViewBuilder
    private func lessonContent(_ stop: LessonStop, page: Page, stacked: Bool) -> some View {
        switch stop.state {
        case .done:
            Button { onStartLesson(stop.lesson) } label: {
                metaRow(stacked: stacked) {
                    Text(stop.lesson.title)
                        .nightFont(.headline)
                        .foregroundStyle(Night.ink2)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                } meta: {
                    Text("Done")
                        .nightFont(.caption)
                        .foregroundStyle(Night.successText)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .contentShape(Rectangle())
            }
            .buttonStyle(NightCardButtonStyle(cornerRadius: Night.Radius.row))
            .nightFocusRing(RoundedRectangle(cornerRadius: Night.Radius.row, style: .continuous))
            .padding(.horizontal, -10)
            .padding(.top, -4)
            .help("Open Lesson \(stop.code) to review it")
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Self.lessonAccessibility(stop))
            .accessibilityHint("Opens the lesson to review it.")
            .accessibilityAddTraits(.isButton)

        case .current(let isFrontier, let inProgress):
            currentCard(stop, isFrontier: isFrontier, inProgress: inProgress, isPrimary: !page.checkIsPrimary)

        case .open:
            Button { onStartLesson(stop.lesson) } label: {
                lessonText(stop, note: nil, stacked: stacked)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .contentShape(Rectangle())
            }
            .buttonStyle(NightCardButtonStyle(cornerRadius: Night.Radius.row))
            .nightFocusRing(RoundedRectangle(cornerRadius: Night.Radius.row, style: .continuous))
            .padding(.horizontal, -10)
            .padding(.top, -4)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Self.lessonAccessibility(stop))
            .accessibilityAddTraits(.isButton)

        case .locked(let after):
            let note = Self.opensAfter(Self.code(unitNumber: page.unitNumber, lesson: after))
            lessonText(stop, note: note, stacked: stacked)
                .padding(.top, 2)
                .help(note)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Self.lessonAccessibility(stop))
        }
    }

    /// A lesson's title and objective, with its note (when it opens) beside
    /// the title, or under it in a narrow row.
    private func lessonText(_ stop: LessonStop, note: String?, stacked: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            metaRow(stacked: stacked) {
                Text(stop.lesson.title)
                    .nightFont(.headline)
                    .foregroundStyle(Night.ink)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            } meta: {
                if let note {
                    Text(note)
                        .nightFont(.caption)
                        .foregroundStyle(Night.ink3)
                }
            }
            Text(stop.lesson.objective)
                .nightFont(.callout)
                .foregroundStyle(Night.ink2)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Title and trailing note side by side; stacked in a narrow row.
    @ViewBuilder
    private func metaRow<Title: View, Meta: View>(stacked: Bool, @ViewBuilder title: () -> Title,
                                                  @ViewBuilder meta: () -> Meta) -> some View {
        if stacked {
            VStack(alignment: .leading, spacing: 2) {
                title()
                meta()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                title()
                Spacer(minLength: 0)
                meta()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// The current lesson: a lit card with its objective and the page's
    /// prominent button (Return).
    private func currentCard(_ stop: LessonStop, isFrontier: Bool, inProgress: Bool, isPrimary: Bool) -> some View {
        let title = Self.currentButton(code: stop.code, inProgress: inProgress)
        return VStack(alignment: .leading, spacing: 8) {
            NightEyebrow(Self.currentEyebrow(code: stop.code, isFrontier: isFrontier),
                         systemImage: isFrontier ? "location.fill" : nil)
            Text(stop.lesson.title)
                .nightFont(.title2)
                .foregroundStyle(Night.ink)
                .fixedSize(horizontal: false, vertical: true)
            Text(stop.lesson.objective)
                .nightFont(.callout)
                .foregroundStyle(Night.ink2)
                .fixedSize(horizontal: false, vertical: true)
            Group {
                if isPrimary {
                    NightPrimaryButton(title, systemImage: "arrow.right") { onStartLesson(stop.lesson) }
                        .keyboardShortcut(.defaultAction)
                        .help("\(title) (Return)")
                } else {
                    NightSecondaryButton(title) { onStartLesson(stop.lesson) }
                }
            }
            .padding(.top, 6)
            .accessibilityIdentifier("path.currentLesson")
        }
        .padding(Night.Space.card)
        .frame(maxWidth: .infinity, alignment: .leading)
        .nightWash()
        .nightLit(radius: Night.Radius.card)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Self.lessonAccessibility(stop))
    }

    @ViewBuilder
    private func checkContent(_ page: Page, stacked: Bool) -> some View {
        let text = VStack(alignment: .leading, spacing: 4) {
            metaRow(stacked: stacked) {
                Text(Self.checkTitle(page))
                    .nightFont(.headline)
                    .foregroundStyle(Night.ink)
            } meta: {
                if let note = Self.checkNote(page) {
                    Text(note)
                        .nightFont(.caption)
                        .foregroundStyle(page.check == .mastered ? Night.successText : Night.accentText)
                }
            }
            Text(Self.checkDetail(questionCount: page.questionCount))
                .nightFont(.callout)
                .foregroundStyle(Night.ink2)
                .fixedSize(horizontal: false, vertical: true)
        }
        switch page.check {
        case .locked:
            text
                .padding(.top, 2)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Self.checkAccessibility(page))
        case .open:
            VStack(alignment: .leading, spacing: 12) {
                text
                NightPrimaryButton(Self.takeCheck, systemImage: "arrow.right") { onStartUnitTest(page.unit) }
                    .keyboardShortcut(.defaultAction)
                    .help("\(Self.takeCheck) (Return)")
                    .accessibilityIdentifier("path.unitCheck")
            }
            .padding(.top, 2)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .contain)
            .accessibilityLabel(Self.checkAccessibility(page))
        case .mastered:
            Button { onStartUnitTest(page.unit) } label: {
                text
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(NightCardButtonStyle(cornerRadius: Night.Radius.row))
            .nightFocusRing(RoundedRectangle(cornerRadius: Night.Radius.row, style: .continuous))
            .padding(.horizontal, -10)
            .padding(.top, -4)
            .help("Take the Unit \(page.unitNumber) check again")
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Self.checkAccessibility(page))
            .accessibilityHint("Takes the check again.")
            .accessibilityAddTraits(.isButton)
        }
    }

    // MARK: - Next unit

    private func nextUnitRow(_ next: CurriculumFeature.Unit) -> some View {
        Button { onOpenUnit(next.id) } label: {
            HStack(alignment: .center, spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    NightEyebrow("Next unit", color: Night.ink3)
                    Text(Self.nextUnitLabel(next))
                        .nightFont(.headline)
                        .foregroundStyle(Night.accentText)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(next.summary)
                        .nightFont(.callout)
                        .foregroundStyle(Night.ink2)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Image(systemName: "arrow.right")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Night.accentText)
                    .accessibilityHidden(true)
            }
            .padding(Night.Space.card)
            .frame(maxWidth: .infinity, alignment: .leading)
            .nightLit(radius: Night.Radius.card)
        }
        .buttonStyle(NightCardButtonStyle())
        .nightFocusRing(RoundedRectangle(cornerRadius: Night.Radius.card, style: .continuous))
        .help("Open \(Self.nextUnitLabel(next))")
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Next unit: \(Self.nextUnitLabel(next)). \(next.summary)")
        .accessibilityAddTraits(.isButton)
    }
}

/// The current lesson's halo (§2.6): `lumen` breathing between 16% and 30%
/// over 1.8 s; still at 22% under Reduce Motion.
private struct NightNodeHalo: View {
    let still: Bool

    var body: some View {
        if still {
            Circle()
                .fill(Night.lumen.opacity(0.22))
                .frame(width: 40, height: 40)
        } else {
            PhaseAnimator([false, true]) { on in
                Circle()
                    .fill(Night.lumen.opacity(on ? 0.30 : 0.16))
                    .frame(width: on ? 42 : 36, height: on ? 42 : 36)
            } animation: { _ in .easeInOut(duration: 1.8) }
        }
    }
}
#endif
