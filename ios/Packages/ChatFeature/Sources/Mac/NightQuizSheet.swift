#if os(macOS)
import SwiftUI
import DesignSystem
import NetworkingKit

/// The chat's "Quiz me" sheet on the Mac, in Night Studio: a quiz Merc
/// writes from this conversation (`POST /api/quiz`, the iPhone's
/// `QuizViewModel`, unchanged). Each question is a lit card with the same
/// answer rows as a lesson's check (`NightAnswerRow`); Submit (⌘Return)
/// reveals the answers and Merc's explanations. Loading, failure and the
/// crisis branch keep their copy: a failure is a line and a way forward;
/// the crisis branch is `CrisisSupportView` as it is, on a flat canvas.
struct NightQuizSheet: View {
    let model: QuizViewModel
    let dismissAction: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            topBar
            Group {
                switch model.phase {
                case .loading:
                    loading
                case .ready(let quiz):
                    content(quiz)
                case .failed(let reason, let retryable):
                    failure(reason: reason, retryable: retryable)
                case .support:
                    ScrollView {
                        CrisisSupportView(closeTitle: "Close", onClose: dismissAction)
                            .padding(24)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(NightCanvas(pools: model.phase == .support ? .flat : .indigo, stars: false))
        .frame(minWidth: 480, idealWidth: 560, minHeight: 520, idealHeight: 640)
        .task { if case .loading = model.phase { await model.load() } }
    }

    private var topBar: some View {
        HStack {
            NightEyebrow("Quiz from this chat", systemImage: "checklist")
            Spacer()
            NightTextButton("Done", action: dismissAction)
                .keyboardShortcut(.cancelAction)
                .help("Close the quiz (Esc)")
        }
        .padding(.horizontal, 24)
        .padding(.top, 14)
        .padding(.bottom, 6)
    }

    // MARK: States

    private var loading: some View {
        VStack(spacing: 14) {
            ProgressView().controlSize(.regular)
            Text("Generating a quiz from our conversation…")
                .nightFont(.callout)
                .foregroundStyle(Night.ink3)
                .multilineTextAlignment(.center)
        }
        .padding(24)
        .accessibilityElement(children: .combine)
    }

    private func failure(reason: String, retryable: Bool) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: "exclamationmark.circle")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Night.errorText)
                    .accessibilityHidden(true)
                Text(reason)
                    .nightFont(.body)
                    .foregroundStyle(Night.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityElement(children: .combine)
            if retryable {
                NightPrimaryButton("Try again") { Task { await model.load() } }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(Night.Space.card)
        .frame(maxWidth: 420, alignment: .leading)
        .nightLit(radius: Night.Radius.card)
        .padding(24)
    }

    // MARK: The quiz

    private func content(_ quiz: Quiz) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Night.Space.section) {
                Text(quiz.title)
                    .nightFont(.title)
                    .foregroundStyle(Night.ink)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                ForEach(Array(quiz.questions.enumerated()), id: \.element.id) { index, question in
                    questionCard(index: index, question: question)
                }
                if model.isSubmitted {
                    score(quiz)
                } else {
                    NightPrimaryButton("Submit quiz", size: .large) { model.submit() }
                        .disabled(!model.allAnswered(quiz: quiz))
                        .keyboardShortcut(KeyboardShortcut(.return, modifiers: .command))
                        .help("Submit quiz (⌘Return)")
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 8)
            .padding(.bottom, 28)
        }
        .scrollBounceBehavior(.basedOnSize)
    }

    private func questionCard(index: Int, question: QuizQuestion) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            NightEyebrow("Question \(index + 1)")
            Text(question.q)
                .nightFont(.title2)
                .foregroundStyle(Night.ink)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            VStack(spacing: 8) {
                ForEach(Array(question.options.enumerated()), id: \.offset) { optionIndex, option in
                    let letter = QuizQuestion.letter(forIndex: optionIndex)
                    let mark = Self.mark(letter: letter, selection: model.selections[question.id],
                                         answer: question.answer, submitted: model.isSubmitted)
                    NightAnswerRow(letter: letter, text: Self.strippedOption(option, letter: letter), mark: mark,
                                   isInteractive: !model.isSubmitted) {
                        model.select(letter, for: question.id)
                    }
                    .accessibilityLabel("Option \(letter): \(Self.strippedOption(option, letter: letter))")
                    .accessibilityValue(Self.spokenValue(mark))
                    .accessibilityAddTraits(model.selections[question.id] == letter ? .isSelected : [])
                    .accessibilityRemoveTraits(model.isSubmitted ? .isButton : [])
                }
            }
            if model.isSubmitted {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Image(systemName: "lightbulb")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Night.accentText)
                        .accessibilityHidden(true)
                    Text(question.explanation)
                        .nightFont(.body)
                        .foregroundStyle(Night.ink2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .nightLit(radius: Night.Radius.card)
        .accessibilityElement(children: .contain)
    }

    private func score(_ quiz: Quiz) -> some View {
        let score = model.score(quiz: quiz)
        let total = quiz.questions.count
        return VStack(alignment: .leading, spacing: 10) {
            Text("\(score) / \(total)")
                .nightFont(.display)
                .monospacedDigit()
                .foregroundStyle(Night.ink)
                .accessibilityLabel("You scored \(score) out of \(total)")
            Text(Self.scoreBlurb(correct: score, total: total))
                .nightFont(.body)
                .foregroundStyle(Night.ink2)
                .fixedSize(horizontal: false, vertical: true)
            NightSecondaryButton("New quiz", systemImage: "arrow.clockwise") { model.restart() }
                .padding(.top, 4)
        }
        .padding(Night.Space.card)
        .frame(maxWidth: .infinity, alignment: .leading)
        .nightLit(radius: Night.Radius.card)
    }

    // MARK: Pure helpers

    /// A row's mark: before Submit, picked or not; after, the right answer
    /// (picked or not), a wrong pick, or neither.
    static func mark(letter: String, selection: String?, answer: String, submitted: Bool) -> NightAnswerRow.Mark {
        let picked = selection == letter
        guard submitted else { return picked ? .picked : .rest }
        if letter == answer { return .correct(picked: picked) }
        return picked ? .wrong : .other
    }

    static func spokenValue(_ mark: NightAnswerRow.Mark) -> String {
        switch mark {
        case .rest, .other: return ""
        case .picked: return "Selected"
        case .correct(let picked): return picked ? "Correct answer, your answer" : "Correct answer"
        case .wrong: return "Your answer, incorrect"
        }
    }

    /// The server's options sometimes carry their letter ("A) foo"): drop it.
    static func strippedOption(_ text: String, letter: String) -> String {
        for prefix in ["\(letter)) ", "\(letter). ", "\(letter): "] where text.hasPrefix(prefix) {
            return String(text.dropFirst(prefix.count))
        }
        return text
    }

    /// `QuizView`'s lines, unchanged.
    static func scoreBlurb(correct: Int, total: Int) -> String {
        guard total > 0 else { return "" }
        let ratio = Double(correct) / Double(total)
        switch ratio {
        case 1.0: return "Perfect — you clearly got the material."
        case 0.75...: return "Strong work. A couple to revisit."
        case 0.5...: return "Halfway there. Worth going over the explanations."
        default: return "That's on the hard side. Take another pass through the chat and try again."
        }
    }
}
#endif
