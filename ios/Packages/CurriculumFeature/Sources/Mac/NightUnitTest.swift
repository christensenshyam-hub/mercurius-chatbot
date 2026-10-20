#if os(macOS)
import SwiftUI
import DesignSystem

/// Every new or changed line the Mac's unit check says (SPEC.md §5.5, §6),
/// in one place for the honest-copy tests. The rules, the questions, the
/// grading and the crisis branch are the iPhone's (`UnitTestViewModel`).
enum NightUnitTestCopy {
    static func eyebrow(unitNumber: String) -> String { "Unit \(displayUnit(unitNumber)) check" }
    static func question(_ number: Int) -> String { "Question \(number)" }
    static let instructionsKeyboard = "Keyboard: A–D answers the highlighted question, Tab or ↓ moves on, ⌘Return submits."
    static func instructions(total: Int, needed: Int) -> String {
        "Answer all \(total) questions, then submit. You need \(needed) of \(total) correct to move on."
    }
    static func score(_ score: Int, of total: Int) -> String { "You got \(score) of \(total) correct." }
    static let continueToWritten = "Continue to the written question"
    static let seeResults = "See results"

    /// Was "WRITTEN DEFENSE".
    static let writtenAnswer = "Written answer"
    static func writtenLead(score: Int, total: Int) -> String {
        "Nice — \(score)/\(total) on the quiz. One written question left, graded by Mercurius."
    }
    static let writtenPlaceholder = "Type your answer here…"
    static let grading = "Grading your answer…"
    static let submitWritten = "Submit for grading"

    static let mastered = "Unit mastered"
    static let almost = "Almost there"
    static let quizRow = "Quiz"
    static let writtenRow = "Written answer"
    static let notReached = "Not reached"
    static func grade(_ grade: String) -> String { "Grade \(grade)" }
    static func masteredLine(unitTitle: String) -> String {
        "You've shown real command of \(unitTitle). This unit is now marked mastered."
    }
    static func notPassedLine(quizPassed: Bool) -> String {
        quizPassed
            ? "Your written answer needs more depth. Revisit the unit and try the test again."
            : "Review the unit's lessons, then retake the test when you're ready."
    }
    static let retake = "Retake test"
    static let done = "Done"

    /// "01" reads as "1".
    static func displayUnit(_ unitNumber: String) -> String {
        Int(unitNumber).map(String.init) ?? unitNumber
    }
}

/// The unit check on the Mac, in Night Studio (SPEC.md §5.5): each question
/// a lit card with the same answer rows as a lesson's check
/// (`NightAnswerRow`), Night's prominent button for each step (⌘Return), the
/// written answer as Merc's question in the "keep" face over a lit well, and
/// a plain result — no ceremony. On the crisis branch it shows
/// `CrisisSupportView` exactly as it is (the host draws a flat canvas
/// behind it).
///
/// The keyboard is the iPhone's model with the Mac's keys, unchanged: A–D
/// or 1–4 answer the focused question and move on, ↑/↓ move, Tab walks the
/// cards, ⌘Return submits.
struct NightUnitTestContent: View {
    let model: UnitTestViewModel
    var focusedQuestion: FocusState<String?>.Binding
    @Binding var reportedMastery: Bool
    let onMastered: (String) -> Void
    let onExit: () -> Void

    @NightSettings private var night

    var body: some View {
        Group {
            switch model.phase {
            case .quiz: quizPhase
            case .defense: defensePhase
            case .result: resultPhase
            case .support: supportPhase
            }
        }
        .padding(.horizontal, 8)
        .padding(.top, 12)
        .padding(.bottom, 24)
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            NightEyebrow(NightUnitTestCopy.eyebrow(unitNumber: model.unit.number), systemImage: "checkmark.seal")
            Text(model.unit.title)
                .nightFont(.title)
                .foregroundStyle(Night.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    // MARK: Quiz

    private var quizPhase: some View {
        VStack(alignment: .leading, spacing: Night.Space.section) {
            header
            VStack(alignment: .leading, spacing: 8) {
                Text(NightUnitTestCopy.instructions(total: model.mcqTotal, needed: model.mcqCorrectNeeded))
                    .nightFont(.body)
                    .foregroundStyle(Night.ink2)
                    .fixedSize(horizontal: false, vertical: true)
                if !model.quizSubmitted {
                    Label(NightUnitTestCopy.instructionsKeyboard, systemImage: "keyboard")
                        .nightFont(.caption)
                        .foregroundStyle(Night.ink3)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            ForEach(Array(model.questions.enumerated()), id: \.element.id) { index, question in
                questionCard(index: index, question: question)
            }

            if model.quizSubmitted {
                VStack(alignment: .leading, spacing: 14) {
                    Text(NightUnitTestCopy.score(model.mcqScore, of: model.mcqTotal))
                        .nightFont(.title2)
                        .monospacedDigit()
                        .foregroundStyle(Night.ink)
                    primary(model.mcqPassed ? NightUnitTestCopy.continueToWritten : NightUnitTestCopy.seeResults,
                            commandReturn: true) {
                        model.continueAfterQuiz()
                    }
                }
            } else {
                primary(model.submitTitle, enabled: model.allAnswered, commandReturn: true) {
                    model.submitQuiz()
                }
            }
        }
        .onChange(of: model.quizSubmitted) { _, submitted in
            if submitted, let line = model.scoreAnnouncement { announce(line) }
            if submitted { focusedQuestion.wrappedValue = nil }
        }
        .onAppear {
            if !model.quizSubmitted { focusedQuestion.wrappedValue = model.questions.first?.id }
        }
    }

    private func questionCard(index: Int, question: UnitTestQuestion) -> some View {
        let shape = RoundedRectangle(cornerRadius: Night.Radius.card, style: .continuous)
        let focused = focusedQuestion.wrappedValue == question.id && !model.quizSubmitted
        return VStack(alignment: .leading, spacing: 14) {
            NightEyebrow(NightUnitTestCopy.question(index + 1))
            Text(question.q)
                .nightFont(.title2)
                .foregroundStyle(Night.ink)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            VStack(spacing: 8) {
                ForEach(question.options.indices, id: \.self) { i in
                    row(model.optionState(for: question, index: i)) {
                        model.select(UnitTestViewModel.optionLetter(i), for: question.id)
                        focusedQuestion.wrappedValue = question.id
                    }
                }
            }
            if model.quizSubmitted {
                Text(question.explanation)
                    .nightFont(.body)
                    .foregroundStyle(Night.ink2)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 2)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .nightLit(radius: Night.Radius.card)
        .id(question.id)
        // In the Tab loop whatever the Full Keyboard Access setting (`.edit`,
        // like a text field), with Night's own ring (§4.4).
        .focusable(!model.quizSubmitted, interactions: .edit)
        .focused(focusedQuestion, equals: question.id)
        .focusEffectDisabled()
        .overlay {
            if focused {
                shape.inset(by: -3 - night.focusRingWidth / 2)
                    .stroke(Night.focusRing, lineWidth: night.focusRingWidth)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }
        .onKeyPress(phases: .down) { press in handleKey(press, question: question, index: index) }
        .accessibilityElement(children: .contain)
    }

    /// One answer: the shared Night row, with the unit check's own words for
    /// VoiceOver (`UnitTestOptionState`, AUD-22).
    private func row(_ state: UnitTestOptionState, select: @escaping () -> Void) -> some View {
        NightAnswerRow(letter: state.letter, text: state.text, mark: Self.mark(for: state),
                       isInteractive: !state.isSubmitted, action: select)
            .accessibilityLabel(state.accessibilityLabel)
            .accessibilityValue(state.accessibilityValue ?? "")
            .accessibilityAddTraits(state.isSelected ? .isSelected : [])
            .accessibilityRemoveTraits(state.isSubmitted ? .isButton : [])
            .accessibilityHint(state.isSubmitted ? "" : "Chooses this answer")
    }

    /// The unit check's row state as the shared row's mark.
    static func mark(for state: UnitTestOptionState) -> NightAnswerRow.Mark {
        switch state.grade {
        case .open: return state.isSelected ? .picked : .rest
        case .correctPick: return .correct(picked: true)
        case .correctAnswer: return .correct(picked: false)
        case .wrongPick: return .wrong
        case .other: return .other
        }
    }

    /// A–D / 1–4 answer the focused question and move to the next one;
    /// ↑ and ↓ move between questions. ⌘-keys pass through (⌘Return submits).
    private func handleKey(_ press: KeyPress, question: UnitTestQuestion, index: Int) -> KeyPress.Result {
        guard !model.quizSubmitted, !press.modifiers.contains(.command) else { return .ignored }
        switch press.key {
        case .downArrow:
            moveFocus(from: index, by: 1)
            return .handled
        case .upArrow:
            moveFocus(from: index, by: -1)
            return .handled
        default:
            break
        }
        guard let letter = UnitTestViewModel.optionLetter(forKey: press.characters,
                                                          optionCount: question.options.count) else {
            return .ignored
        }
        model.select(letter, for: question.id)
        moveFocus(from: index, by: 1)
        return .handled
    }

    private func moveFocus(from index: Int, by step: Int) {
        let next = index + step
        guard model.questions.indices.contains(next) else { return }
        focusedQuestion.wrappedValue = model.questions[next].id
    }

    // MARK: Written answer

    private var defensePhase: some View {
        VStack(alignment: .leading, spacing: Night.Space.section) {
            header
            VStack(alignment: .leading, spacing: 8) {
                NightEyebrow(NightUnitTestCopy.writtenAnswer, systemImage: "pencil.line")
                Text(NightUnitTestCopy.writtenLead(score: model.mcqScore, total: model.mcqTotal))
                    .nightFont(.body)
                    .foregroundStyle(Night.ink2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: 16) {
                // Merc's question to the student: the "keep" face.
                Text(model.test.defensePrompt)
                    .nightFont(.keep)
                    .foregroundStyle(Night.ink)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
                answerField
            }
            .padding(Night.Space.card)
            .frame(maxWidth: .infinity, alignment: .leading)
            .nightWash()
            .nightLit(radius: Night.Radius.card)

            if let error = model.defenseError {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Image(systemName: "exclamationmark.circle")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Night.errorText)
                        .accessibilityHidden(true)
                    Text(error)
                        .nightFont(.body)
                        .foregroundStyle(Night.ink)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .accessibilityElement(children: .combine)
            }

            if model.isGrading {
                HStack(spacing: 10) {
                    ProgressView().controlSize(.small)
                    Text(NightUnitTestCopy.grading)
                        .nightFont(.callout)
                        .foregroundStyle(Night.ink3)
                }
                .accessibilityElement(children: .combine)
            } else {
                primary(NightUnitTestCopy.submitWritten, enabled: model.canSubmitDefense, commandReturn: true) {
                    Task { await model.submitDefense() }
                }
            }
        }
    }

    /// The written answer: a lit well with Night's field edge (≥ 3:1), the
    /// placeholder in `ink3`, and the focus ring on the well.
    private var answerField: some View {
        let shape = RoundedRectangle(cornerRadius: Night.Radius.row, style: .continuous)
        return TextEditor(text: Binding(get: { model.defenseAnswer }, set: { model.defenseAnswer = $0 }))
            .nightFont(.body)
            .foregroundStyle(Night.ink)
            .scrollContentBackground(.hidden)
            .frame(minHeight: 160)
            .overlay(alignment: .topLeading) {
                if model.defenseAnswer.isEmpty {
                    Text(NightUnitTestCopy.writtenPlaceholder)
                        .nightFont(.body)
                        .foregroundStyle(Night.ink3)
                        .padding(.leading, 5)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
            }
            .accessibilityLabel("Your written answer")
            .padding(10)
            .background(Night.surfaceRaised, in: shape)
            .overlay(shape.strokeBorder(Night.fieldStroke, lineWidth: night.increasedContrast ? 2 : 1))
            .nightFocusRing(shape)
            .disabled(model.isGrading)
    }

    // MARK: Result

    private var resultPhase: some View {
        let passed = model.overallPassed
        return VStack(alignment: .leading, spacing: Night.Space.section) {
            header
            VStack(alignment: .leading, spacing: 10) {
                Image(systemName: passed ? "checkmark.seal.fill" : "arrow.counterclockwise.circle")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(passed ? Night.successText : Night.accentText)
                    .accessibilityHidden(true)
                Text(passed ? NightUnitTestCopy.mastered : NightUnitTestCopy.almost)
                    .nightFont(.display)
                    .foregroundStyle(Night.ink)
                    .accessibilityAddTraits(.isHeader)
                Text(passed ? NightUnitTestCopy.masteredLine(unitTitle: model.unit.title)
                            : NightUnitTestCopy.notPassedLine(quizPassed: model.mcqPassed))
                    .nightFont(.body)
                    .foregroundStyle(Night.ink2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(spacing: 0) {
                resultRow(label: NightUnitTestCopy.quizRow, detail: "\(model.mcqScore)/\(model.mcqTotal)",
                          ok: model.mcqPassed)
                Rectangle().fill(Night.hairline).frame(height: 1)
                if let defense = model.defenseResult {
                    resultRow(label: NightUnitTestCopy.writtenRow, detail: NightUnitTestCopy.grade(defense.grade),
                              ok: defense.pass)
                } else {
                    resultRow(label: NightUnitTestCopy.writtenRow, detail: NightUnitTestCopy.notReached, ok: false)
                }
            }
            .padding(.horizontal, Night.Space.card)
            .padding(.vertical, 6)
            .nightLit(radius: Night.Radius.card)

            if let defense = model.defenseResult, !defense.feedback.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    NightEyebrow("Merc on your written answer", color: Night.ink3)
                    Text(defense.feedback)
                        .nightFont(.body)
                        .foregroundStyle(Night.ink2)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                }
                .accessibilityElement(children: .combine)
            }

            HStack(spacing: 16) {
                if passed {
                    primary(NightUnitTestCopy.done, defaultAction: true) { onExit() }
                } else {
                    if model.offersRetake {
                        primary(NightUnitTestCopy.retake) { model.retake() }
                    }
                    NightTextButton(NightUnitTestCopy.done) { onExit() }
                        .accessibilityLabel("Done. Exit unit test.")
                }
            }
        }
        .onAppear {
            // The mastery callback fires exactly once, when the student passes.
            if model.overallPassed && !reportedMastery {
                reportedMastery = true
                onMastered(model.unit.id)
            }
            if let line = model.resultAnnouncement { announce(line) }
        }
    }

    private func resultRow(label: String, detail: String, ok: Bool) -> some View {
        HStack(spacing: 10) {
            Image(systemName: ok ? "checkmark.circle.fill" : "xmark.circle.fill")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(ok ? Night.successText : Night.errorText)
            Text(label)
                .nightFont(.body)
                .foregroundStyle(Night.ink)
            Spacer()
            Text(detail)
                .nightFont(.body)
                .monospacedDigit()
                .foregroundStyle(Night.ink2)
        }
        .padding(.vertical, 12)
        // "Quiz, 4/5, passed": the mark's meaning in words, not colour.
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label), \(detail), \(ok ? "passed" : "not passed")")
    }

    // MARK: Support

    /// The written answer read as a crisis: support resources, as they are.
    /// Palette only: no Night type, no light, no Merc, no motion.
    private var supportPhase: some View {
        CrisisSupportView(closeTitle: "Back to your path", onClose: onExit)
    }

    // MARK: Shared

    /// The screen's one prominent button. `commandReturn`: ⌘Return presses
    /// it (the quiz's and the written answer's submit); `defaultAction`:
    /// Return does (the result's next step).
    @ViewBuilder
    private func primary(_ title: String, enabled: Bool = true, commandReturn: Bool = false,
                         defaultAction: Bool = false, action: @escaping () -> Void) -> some View {
        let button = NightPrimaryButton(title, size: .large, action: action)
            .disabled(!enabled)
            .help(commandReturn ? "\(title) (⌘Return)" : title)
        if commandReturn {
            button.keyboardShortcut(KeyboardShortcut(.return, modifiers: .command))
        } else if defaultAction {
            button.keyboardShortcut(.defaultAction)
        } else {
            button
        }
    }

    private func announce(_ line: String) {
        AccessibilityNotification.Announcement(line).post()
    }
}
#endif
