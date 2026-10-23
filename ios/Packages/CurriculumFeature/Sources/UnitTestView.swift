import SwiftUI
import DesignSystem

/// The cumulative unit-test experience: a multiple-choice quiz (scored
/// on-device), then one open-ended "defense" question (graded by the server via
/// the injected `gradeDefense` closure), then a combined result. On an overall
/// pass it calls `onMastered(unitId)` exactly once. When the server answers the
/// written defense with crisis support, the test is set aside for
/// `CrisisSupportView`: no grade, no score, no retake.
public struct UnitTestView: View {
    @State private var model: UnitTestViewModel
    @State private var reportedMastery = false
    #if os(macOS)
    /// The question the keyboard answers (A–D, 1–4); Tab, ↑ and ↓ move it.
    @FocusState private var focusedQuestion: String?
    #endif
    private let onMastered: (String) -> Void
    private let onExit: () -> Void

    public init(
        unit: Unit,
        test: UnitTest,
        gradeDefense: @escaping (String) async throws -> UnitTestViewModel.DefenseResult,
        onMastered: @escaping (String) -> Void,
        onExit: @escaping () -> Void
    ) {
        _model = State(initialValue: UnitTestViewModel(unit: unit, test: test, gradeDefense: gradeDefense))
        self.onMastered = onMastered
        self.onExit = onExit
    }

    /// Hosts a model the caller already holds (DEBUG previews drive one to a
    /// given phase).
    public init(
        model: UnitTestViewModel,
        onMastered: @escaping (String) -> Void,
        onExit: @escaping () -> Void
    ) {
        _model = State(initialValue: model)
        self.onMastered = onMastered
        self.onExit = onExit
    }

    public var body: some View {
        ZStack(alignment: .top) {
            BrandColor.background.ignoresSafeArea()
            VStack(spacing: 0) {
                #if os(iOS)
                header
                Divider().overlay(BrandColor.border)
                #endif
                ScrollViewReader { proxy in
                    ScrollView {
                        content
                            .padding(.horizontal, BrandSpacing.lg)
                            .padding(.vertical, BrandSpacing.lg)
                            // The Mac's reading column, centred in a wide window.
                            .macReadableColumn()
                    }
                    #if os(macOS)
                    // The question the keyboard moved to comes into view.
                    .onChange(of: focusedQuestion) { _, id in
                        guard let id else { return }
                        withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo(id) }
                    }
                    #endif
                }
                // Each phase is its own screen and opens at its top — the
                // support view must never appear scrolled past its heading.
                .id(model.phase)
            }
        }
        #if os(macOS)
        // The window's toolbar carries what the iPhone's header row shows:
        // the title, the unit (subtitle) and the way back.
        .navigationTitle(model.phase == .support ? "Support" : "Unit \(Int(model.unit.number) ?? 0) Check")
        .navigationSubtitle(model.phase == .support ? "" : model.unit.title)
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Button { onExit() } label: {
                    Label("Done", systemImage: "chevron.backward")
                }
                .buttonStyle(.automatic)
                // Escape only when leaving loses nothing (no picks, no
                // written answer, nothing being graded).
                .keyboardShortcut(model.exitLosesNothing ? .cancelAction : nil)
                .help(model.exitLosesNothing ? "Done: back to the path (Esc)" : "Done: back to the path")
                .accessibilityLabel("Done. Exit unit test.")
            }
        }
        #endif
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .top, spacing: BrandSpacing.md) {
            // On the support screen the test is set aside: no unit/test
            // title, just the way out, so the hotlines sit higher.
            if model.phase != .support {
                VStack(alignment: .leading, spacing: 4) {
                    Text("UNIT \(model.unit.number) · UNIT TEST")
                        .font(BrandFont.caption)
                        .tracking(1.2)
                        .foregroundStyle(BrandColor.accentText)
                    Text(model.unit.title)
                        .font(BrandFont.subheading)
                        .foregroundStyle(BrandColor.text)
                }
                // One heading for VoiceOver's rotor (AUD-49).
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(.isHeader)
            }
            Spacer(minLength: BrandSpacing.sm)
            Button { onExit() } label: {
                Text("Done")
                    .font(BrandFont.bodyEmphasized)
                    .foregroundStyle(BrandColor.accentText)
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Done. Exit unit test.")
        }
        .padding(.horizontal, BrandSpacing.lg)
        .padding(.top, BrandSpacing.md)
        .padding(.bottom, BrandSpacing.sm)
    }

    @ViewBuilder private var content: some View {
        switch model.phase {
        case .quiz: quizPhase
        case .defense: defensePhase
        case .result: resultPhase
        case .support: supportPhase
        }
    }

    // MARK: - Support phase

    /// The written answer read as a crisis: support resources instead of a
    /// result. The header's Done and this view's button both leave the test.
    private var supportPhase: some View {
        CrisisSupportView(closeTitle: "Back to your path", onClose: onExit)
    }

    // MARK: - Quiz phase

    private var quizPhase: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.lg) {
            Text("Answer all \(model.mcqTotal) questions, then submit. You need \(model.mcqCorrectNeeded) of \(model.mcqTotal) correct to move on.")
                .font(BrandFont.body)
                .foregroundStyle(BrandColor.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            #if os(macOS)
            if !model.quizSubmitted {
                Label("Keyboard: A–D answers the highlighted question, Tab or ↓ moves on, ⌘Return submits.",
                      systemImage: "keyboard")
                    .font(BrandFont.caption)
                    .foregroundStyle(BrandColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            #endif

            ForEach(Array(model.questions.enumerated()), id: \.element.id) { index, question in
                questionCard(index: index, question: question)
            }

            if model.quizSubmitted {
                VStack(spacing: BrandSpacing.sm) {
                    Text("You got \(model.mcqScore) of \(model.mcqTotal) correct.")
                        .font(BrandFont.bodyEmphasized)
                        .foregroundStyle(BrandColor.text)
                    primaryButton(model.mcqPassed ? "Continue to the written question" : "See results",
                                  submitsWithCommandReturn: true) {
                        model.continueAfterQuiz()
                    }
                }
            } else {
                primaryButton(model.submitTitle, enabled: model.allAnswered, submitsWithCommandReturn: true) {
                    model.submitQuiz()
                }
            }
        }
        .onChange(of: model.quizSubmitted) { _, submitted in
            if submitted, let line = model.scoreAnnouncement { announce(line) }
            #if os(macOS)
            if submitted { focusedQuestion = nil }
            #endif
        }
        #if os(macOS)
        .onAppear {
            if !model.quizSubmitted { focusedQuestion = model.questions.first?.id }
        }
        #endif
    }

    #if os(macOS)
    /// A–D / 1–4 answer the focused question and move to the next one;
    /// ↑ and ↓ move between questions. ⌘-keys pass through (⌘Return
    /// submits).
    private func handleQuizKey(_ press: KeyPress, question: UnitTestQuestion, index: Int) -> KeyPress.Result {
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
        focusedQuestion = model.questions[next].id
    }
    #endif

    private func questionCard(index: Int, question: UnitTestQuestion) -> some View {
        VStack(alignment: .leading, spacing: BrandSpacing.sm) {
            Text("Question \(index + 1)")
                .font(BrandFont.caption)
                .tracking(1.1)
                .foregroundStyle(BrandColor.textSecondary)
            Text(question.q)
                .font(BrandFont.bodyEmphasized)
                .foregroundStyle(BrandColor.text)
                .fixedSize(horizontal: false, vertical: true)

            ForEach(question.options.indices, id: \.self) { i in
                UnitTestOptionRow(state: model.optionState(for: question, index: i)) {
                    model.select(UnitTestViewModel.optionLetter(i), for: question.id)
                }
            }

            if model.quizSubmitted {
                Text(question.explanation)
                    .font(BrandFont.body)
                    .foregroundStyle(BrandColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 2)
            }
        }
        .padding(BrandSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(BrandColor.surface)
        .clipShape(RoundedRectangle(cornerRadius: BrandRadius.md))
        .id(question.id)
        #if os(macOS)
        // In the Tab loop whatever the student's Full Keyboard Access
        // setting (`.edit`, like a text field), with its own ring.
        .focusable(!model.quizSubmitted, interactions: .edit)
        .focused($focusedQuestion, equals: question.id)
        .focusEffectDisabled()
        .overlay(
            RoundedRectangle(cornerRadius: BrandRadius.md)
                .strokeBorder(BrandColor.accent, lineWidth: 2)
                .opacity(focusedQuestion == question.id && !model.quizSubmitted ? 1 : 0)
                .allowsHitTesting(false)
        )
        .onKeyPress(phases: .down) { press in handleQuizKey(press, question: question, index: index) }
        #endif
    }

    // MARK: - Defense phase

    private var defensePhase: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.md) {
            Text("WRITTEN DEFENSE")
                .font(BrandFont.caption)
                .tracking(1.2)
                .foregroundStyle(BrandColor.accentText)
            Text("Nice — \(model.mcqScore)/\(model.mcqTotal) on the quiz. One written question left, graded by Mercurius.")
                .font(BrandFont.body)
                .foregroundStyle(BrandColor.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            Text(model.test.defensePrompt)
                .font(BrandFont.bodyEmphasized)
                .foregroundStyle(BrandColor.text)
                .fixedSize(horizontal: false, vertical: true)
                .padding(BrandSpacing.md)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(BrandColor.surface)
                .clipShape(RoundedRectangle(cornerRadius: BrandRadius.md))

            TextEditor(text: Binding(get: { model.defenseAnswer }, set: { model.defenseAnswer = $0 }))
                .font(BrandFont.body)
                .foregroundStyle(BrandColor.text)
                .scrollContentBackground(.hidden)
                .frame(minHeight: 160)
                // An empty editor says what goes in it; VoiceOver hears a
                // name instead of "text view" (AUD-22).
                .overlay(alignment: .topLeading) {
                    if model.defenseAnswer.isEmpty {
                        Text("Type your answer here…")
                            .font(BrandFont.body)
                            .foregroundStyle(BrandColor.textSecondary)
                            .padding(.top, 8)
                            .padding(.leading, 5)
                            .allowsHitTesting(false)
                            .accessibilityHidden(true)
                    }
                }
                .accessibilityLabel("Your written answer")
                .padding(BrandSpacing.sm)
                .background(BrandColor.surfaceElevated)
                .clipShape(RoundedRectangle(cornerRadius: BrandRadius.md))
                .overlay(
                    RoundedRectangle(cornerRadius: BrandRadius.md)
                        .stroke(BrandColor.border, lineWidth: 1)
                )
                .disabled(model.isGrading)

            if let error = model.defenseError {
                Text(error)
                    .font(BrandFont.body)
                    .foregroundStyle(BrandColor.errorText)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if model.isGrading {
                HStack(spacing: BrandSpacing.sm) {
                    ProgressView()
                    Text("Grading your answer…")
                        .font(BrandFont.caption)
                        .foregroundStyle(BrandColor.textSecondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, BrandSpacing.xs)
            } else {
                primaryButton("Submit for grading", enabled: model.canSubmitDefense, submitsWithCommandReturn: true) {
                    Task { await model.submitDefense() }
                }
            }
        }
    }

    // MARK: - Result phase

    private var resultPhase: some View {
        let passed = model.overallPassed
        return VStack(spacing: BrandSpacing.lg) {
            if passed {
                // Mastery gets its Merc moment (AUD-22).
                MercMascot(.celebrate, size: 120)
                    .padding(.top, BrandSpacing.md)
                    .accessibilityHidden(true)
            } else {
                Image(systemName: "arrow.counterclockwise.circle.fill")
                    .font(.system(size: 56))
                    .foregroundStyle(BrandColor.accentText)
                    .padding(.top, BrandSpacing.md)
                    .accessibilityHidden(true)
            }

            Text(passed ? "Unit mastered" : "Almost there")
                .font(BrandFont.title)
                .foregroundStyle(BrandColor.text)
                .accessibilityAddTraits(.isHeader)

            VStack(alignment: .leading, spacing: BrandSpacing.sm) {
                resultRow(label: "Quiz", detail: "\(model.mcqScore)/\(model.mcqTotal)", ok: model.mcqPassed)
                if let defense = model.defenseResult {
                    resultRow(label: "Written defense", detail: "Grade \(defense.grade)", ok: defense.pass)
                } else {
                    resultRow(label: "Written defense", detail: "Not reached", ok: false)
                }
            }
            .padding(BrandSpacing.md)
            .frame(maxWidth: .infinity)
            .background(BrandColor.surface)
            .clipShape(RoundedRectangle(cornerRadius: BrandRadius.md))

            if let defense = model.defenseResult {
                Text(defense.feedback)
                    .font(BrandFont.body)
                    .foregroundStyle(BrandColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            if passed {
                Text("You've shown real command of \(model.unit.title). This unit is now marked mastered.")
                    .font(BrandFont.body)
                    .foregroundStyle(BrandColor.textSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                primaryButton("Done") { onExit() }
            } else {
                Text(model.mcqPassed
                     ? "Your written answer needs more depth. Revisit the unit and try the test again."
                     : "Review the unit's lessons, then retake the test when you're ready.")
                    .font(BrandFont.body)
                    .foregroundStyle(BrandColor.textSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                if model.offersRetake {
                    primaryButton("Retake test") { model.retake() }
                }
                Button { onExit() } label: {
                    Text("Done")
                        .font(BrandFont.bodyEmphasized)
                        .foregroundStyle(BrandColor.accentText)
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity)
        .onAppear {
            // Fire the mastery callback exactly once when the student passes.
            if model.overallPassed && !reportedMastery {
                reportedMastery = true
                onMastered(model.unit.id)
            }
            if let line = model.resultAnnouncement { announce(line) }
        }
    }

    private func resultRow(label: String, detail: String, ok: Bool) -> some View {
        HStack(spacing: BrandSpacing.sm) {
            Image(systemName: ok ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundStyle(ok ? BrandColor.successText : BrandColor.errorText)
            Text(label)
                .font(BrandFont.body)
                .foregroundStyle(BrandColor.text)
            Spacer()
            Text(detail)
                .font(BrandFont.body)
                .foregroundStyle(BrandColor.textSecondary)
        }
        // "Quiz, 4/5, passed": the mark's meaning in words, not colour.
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label), \(detail), \(ok ? "passed" : "not passed")")
    }

    // MARK: - Shared

    /// Enabled: white on indigo. Not yet enabled: readable secondary text
    /// on a quiet card, not the whole button faded to half (AUD-22).
    /// `submitsWithCommandReturn`: on the Mac, ⌘Return presses it (the
    /// quiz's submit, the written answer's submit).
    private func primaryButton(_ title: String, enabled: Bool = true, submitsWithCommandReturn: Bool = false,
                               action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(BrandFont.bodyEmphasized)
                .foregroundStyle(enabled ? Color.white : BrandColor.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, BrandSpacing.md)
                .padding(.vertical, BrandSpacing.sm)
                .frame(maxWidth: .infinity, minHeight: 50)
                .background(enabled ? BrandColor.accent : BrandColor.surfaceElevated)
                .clipShape(RoundedRectangle(cornerRadius: BrandRadius.md))
                .overlay(
                    RoundedRectangle(cornerRadius: BrandRadius.md)
                        .stroke(enabled ? Color.clear : BrandColor.border, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        #if os(macOS)
        .keyboardShortcut(submitsWithCommandReturn ? KeyboardShortcut(.return, modifiers: .command) : nil)
        #endif
    }

    private func announce(_ line: String) {
        AccessibilityNotification.Announcement(line).post()
    }
}
