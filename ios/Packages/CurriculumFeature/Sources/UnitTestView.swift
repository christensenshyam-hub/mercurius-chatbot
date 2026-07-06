import SwiftUI
import DesignSystem

/// The cumulative unit-test experience: a multiple-choice quiz (scored
/// on-device), then one open-ended "defense" question (graded by the server via
/// the injected `gradeDefense` closure), then a combined result. On an overall
/// pass it calls `onMastered(unitId)` exactly once.
public struct UnitTestView: View {
    @State private var model: UnitTestViewModel
    @State private var reportedMastery = false
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

    public var body: some View {
        ZStack(alignment: .top) {
            BrandColor.background.ignoresSafeArea()
            VStack(spacing: 0) {
                header
                Divider().overlay(BrandColor.border)
                ScrollView {
                    content
                        .padding(.horizontal, BrandSpacing.lg)
                        .padding(.vertical, BrandSpacing.lg)
                }
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .top, spacing: BrandSpacing.md) {
            VStack(alignment: .leading, spacing: 4) {
                Text("UNIT \(model.unit.number) · UNIT TEST")
                    .font(BrandFont.caption)
                    .tracking(1.2)
                    .foregroundStyle(BrandColor.accent)
                Text(model.unit.title)
                    .font(BrandFont.subheading)
                    .foregroundStyle(BrandColor.text)
            }
            Spacer(minLength: BrandSpacing.sm)
            Button("Done") { onExit() }
                .font(BrandFont.bodyEmphasized)
                .foregroundStyle(BrandColor.accent)
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
        }
    }

    // MARK: - Quiz phase

    private var quizPhase: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.lg) {
            Text("Answer all \(model.mcqTotal) questions, then submit. You need \(model.mcqCorrectNeeded) of \(model.mcqTotal) correct to move on.")
                .font(BrandFont.caption)
                .foregroundStyle(BrandColor.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            ForEach(Array(model.questions.enumerated()), id: \.element.id) { index, question in
                questionCard(index: index, question: question)
            }

            if model.quizSubmitted {
                VStack(spacing: BrandSpacing.sm) {
                    Text("You got \(model.mcqScore) of \(model.mcqTotal) correct.")
                        .font(BrandFont.bodyEmphasized)
                        .foregroundStyle(BrandColor.text)
                    primaryButton(model.mcqPassed ? "Continue to the written question" : "See results") {
                        model.continueAfterQuiz()
                    }
                }
            } else {
                primaryButton("Submit answers", enabled: model.allAnswered) {
                    model.submitQuiz()
                }
            }
        }
    }

    private func questionCard(index: Int, question: UnitTestQuestion) -> some View {
        VStack(alignment: .leading, spacing: BrandSpacing.sm) {
            Text("Question \(index + 1)")
                .font(.caption2)
                .tracking(1.1)
                .foregroundStyle(BrandColor.textSecondary)
            Text(question.q)
                .font(BrandFont.bodyEmphasized)
                .foregroundStyle(BrandColor.text)
                .fixedSize(horizontal: false, vertical: true)

            ForEach(Array(question.options.enumerated()), id: \.offset) { i, option in
                optionRow(question: question, index: i, option: option)
            }

            if model.quizSubmitted {
                Text(question.explanation)
                    .font(BrandFont.caption)
                    .foregroundStyle(BrandColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 2)
            }
        }
        .padding(BrandSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(BrandColor.surface)
        .clipShape(RoundedRectangle(cornerRadius: BrandRadius.md))
    }

    private func optionRow(question: UnitTestQuestion, index: Int, option: String) -> some View {
        let letter = UnitTestViewModel.optionLetter(index)
        let isSelected = model.selectedLetter(for: question.id) == letter
        let submitted = model.quizSubmitted
        let isAnswer = question.answer.uppercased() == letter

        let bg: Color
        let stroke: Color
        let fg: Color
        if submitted {
            if isAnswer {
                bg = BrandColor.success.opacity(0.15); stroke = BrandColor.success; fg = BrandColor.text
            } else if isSelected {
                bg = BrandColor.error.opacity(0.15); stroke = BrandColor.error; fg = BrandColor.text
            } else {
                bg = BrandColor.surfaceElevated; stroke = BrandColor.border; fg = BrandColor.textSecondary
            }
        } else if isSelected {
            bg = BrandColor.accent.opacity(0.15); stroke = BrandColor.accent; fg = BrandColor.text
        } else {
            bg = BrandColor.surfaceElevated; stroke = BrandColor.border; fg = BrandColor.text
        }

        return Button {
            model.select(letter, for: question.id)
        } label: {
            HStack(alignment: .top, spacing: BrandSpacing.sm) {
                Text(letter)
                    .font(BrandFont.caption)
                    .fontWeight(.bold)
                    .foregroundStyle(stroke)
                Text(option)
                    .font(BrandFont.caption)
                    .foregroundStyle(fg)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                if submitted && isAnswer {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(BrandColor.success)
                } else if submitted && isSelected {
                    Image(systemName: "xmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(BrandColor.error)
                }
            }
            .padding(.vertical, 10)
            .padding(.horizontal, BrandSpacing.sm)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(bg)
            .clipShape(RoundedRectangle(cornerRadius: BrandRadius.sm))
            .overlay(
                RoundedRectangle(cornerRadius: BrandRadius.sm)
                    .stroke(stroke, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .disabled(submitted)
    }

    // MARK: - Defense phase

    private var defensePhase: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.md) {
            Text("WRITTEN DEFENSE")
                .font(BrandFont.caption)
                .tracking(1.2)
                .foregroundStyle(BrandColor.accent)
            Text("Nice — \(model.mcqScore)/\(model.mcqTotal) on the quiz. One written question left, graded by Mercurius.")
                .font(BrandFont.caption)
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
                    .font(BrandFont.caption)
                    .foregroundStyle(BrandColor.error)
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
                primaryButton("Submit for grading", enabled: model.canSubmitDefense) {
                    Task { await model.submitDefense() }
                }
            }
        }
    }

    // MARK: - Result phase

    private var resultPhase: some View {
        let passed = model.overallPassed
        return VStack(spacing: BrandSpacing.lg) {
            Image(systemName: passed ? "checkmark.seal.fill" : "arrow.counterclockwise.circle.fill")
                .font(.system(size: 56))
                .foregroundStyle(passed ? BrandColor.success : BrandColor.accent)
                .padding(.top, BrandSpacing.md)

            Text(passed ? "Unit mastered" : "Almost there")
                .font(BrandFont.title)
                .foregroundStyle(BrandColor.text)

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
                    .font(BrandFont.caption)
                    .foregroundStyle(BrandColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            if passed {
                Text("You've shown real command of \(model.unit.title). This unit is now marked mastered.")
                    .font(BrandFont.caption)
                    .foregroundStyle(BrandColor.textSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                primaryButton("Done") { onExit() }
            } else {
                Text(model.mcqPassed
                     ? "Your written answer needs more depth. Revisit the unit and try the test again."
                     : "Review the unit's lessons, then retake the test when you're ready.")
                    .font(BrandFont.caption)
                    .foregroundStyle(BrandColor.textSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                primaryButton("Retake test") { model.retake() }
                Button("Done") { onExit() }
                    .font(BrandFont.bodyEmphasized)
                    .foregroundStyle(BrandColor.accent)
            }
        }
        .frame(maxWidth: .infinity)
        .onAppear {
            // Fire the mastery callback exactly once when the student passes.
            if model.overallPassed && !reportedMastery {
                reportedMastery = true
                onMastered(model.unit.id)
            }
        }
    }

    private func resultRow(label: String, detail: String, ok: Bool) -> some View {
        HStack(spacing: BrandSpacing.sm) {
            Image(systemName: ok ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundStyle(ok ? BrandColor.success : BrandColor.error)
            Text(label)
                .font(BrandFont.body)
                .foregroundStyle(BrandColor.text)
            Spacer()
            Text(detail)
                .font(BrandFont.caption)
                .foregroundStyle(BrandColor.textSecondary)
        }
    }

    // MARK: - Shared

    private func primaryButton(_ title: String, enabled: Bool = true, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(BrandFont.bodyEmphasized)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, minHeight: 50)
                .background(BrandColor.accent)
                .clipShape(RoundedRectangle(cornerRadius: BrandRadius.md))
        }
        .buttonStyle(.plain)
        .opacity(enabled ? 1 : 0.5)
        .disabled(!enabled)
    }
}
