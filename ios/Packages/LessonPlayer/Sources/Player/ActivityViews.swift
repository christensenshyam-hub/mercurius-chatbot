import SwiftUI
import DesignSystem

struct ActivityStepView: View {
    let model: LessonPlayerModel
    let activity: Activity
    var headingFocused: AccessibilityFocusState<Bool>.Binding

    private var record: StepRecord { model.record }

    var body: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.lg) {
            if let scenario = activity.scenario { MaterialCard(material: scenario) }
            if let evidence = activity.evidence { MaterialCard(material: evidence, emphasis: true) }
            Text(activity.prompt)
                .font(BrandFont.subheading)
                .foregroundStyle(BrandColor.text)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
                .accessibilityFocused(headingFocused)

            switch activity.kind {
            case .choice(let choice):
                ChoiceList(model: model, choice: choice)
            case .claimSelection(let selection):
                ClaimSelectionView(model: model, selection: selection)
            case .shortResponse(let response):
                ShortResponseView(model: model, maxCharacters: response.maxCharacters, placeholder: response.placeholder)
            case .practice(let practice):
                PracticeView(model: model, practice: practice)
            }

            if record.hintsShown > 0 {
                HintList(hints: Array(activity.hints.prefix(record.hintsShown)))
            }
            if record.phase == .feedback || record.phase == .done, let last = record.lastSubmission {
                FeedbackPanel(activity: activity, submission: last, revealed: record.revealed)
            }
        }
    }
}

// MARK: - Choice

/// Shows the state of one option row, paired with words so color is never the
/// only signal.
enum RowState: Equatable {
    case idle, selected, correctAnswer, yourCorrectAnswer, yourWrongAnswer, partOfAnswer

    var value: String? {
        switch self {
        case .idle: return nil
        case .selected: return PlayerCopy.selected
        case .correctAnswer: return PlayerCopy.correctAnswer
        case .yourCorrectAnswer: return PlayerCopy.yourCorrectAnswer
        case .yourWrongAnswer: return PlayerCopy.yourWrongAnswer
        case .partOfAnswer: return PlayerCopy.yourCorrectAnswer
        }
    }
}

/// Row states once an answer is graded. The right answer is marked only when
/// it's right, or once it has been revealed.
func rowState(id: String, draft: Set<String>, submitted: Set<String>?, correct: Set<String>,
              phase: StepPhase, revealed: Bool) -> RowState {
    guard phase == .feedback || phase == .done, let submitted else {
        return draft.contains(id) ? .selected : .idle
    }
    let picked = submitted.contains(id)
    let isRight = correct.contains(id)
    let answerShown = revealed || submitted == correct
    switch (picked, isRight) {
    case (true, true): return .yourCorrectAnswer
    case (true, false): return .yourWrongAnswer
    case (false, true): return answerShown ? .correctAnswer : .idle
    case (false, false): return .idle
    }
}

struct ChoiceList: View {
    let model: LessonPlayerModel
    let choice: ChoiceActivity

    var body: some View {
        let record = model.record
        let draft: Set<String> = { if case .options(let s)? = record.draft { return s }; return [] }()
        let submitted: Set<String>? = { if case .options(let s)? = record.lastSubmission?.response { return s }; return nil }()
        VStack(alignment: .leading, spacing: BrandSpacing.sm) {
            if choice.selection == .multiple {
                Text(PlayerCopy.chooseAll)
                    .font(BrandFont.caption)
                    .foregroundStyle(BrandColor.textSecondary)
            }
            ForEach(Array(choice.options.enumerated()), id: \.element.id) { index, option in
                let state = rowState(id: option.id, draft: draft, submitted: submitted, correct: choice.correct,
                                     phase: record.phase, revealed: record.revealed)
                OptionRow(
                    letter: PlayerCopy.letter(index),
                    text: option.text,
                    state: state,
                    multiple: choice.selection == .multiple,
                    enabled: record.phase == .viewing
                ) { model.send(.choose(option.id)) }
                .accessibilityIdentifier("player.option.\(option.id)")
            }
        }
    }
}

struct OptionRow: View {
    let letter: String
    let text: String
    let state: RowState
    let multiple: Bool
    let enabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .firstTextBaseline, spacing: BrandSpacing.sm) {
                Image(systemName: icon)
                    .font(BrandFont.bodyEmphasized)
                    .foregroundStyle(tint)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(text)
                        .font(BrandFont.body)
                        .foregroundStyle(BrandColor.text)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                    if let word = statusWord {
                        Text(word)
                            .font(BrandFont.caption.weight(.semibold))
                            .foregroundStyle(tint)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.vertical, BrandSpacing.md)
            .padding(.horizontal, BrandSpacing.md)
            .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
            .background(background, in: RoundedRectangle(cornerRadius: BrandRadius.md, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: BrandRadius.md, style: .continuous)
                    .stroke(stroke, lineWidth: state == .idle ? 1 : 2)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        // Not `.disabled`: that dims the text, and an answered row (yours,
        // or the right one) must stay fully readable.
        .allowsHitTesting(enabled)
        .accessibilityRemoveTraits(enabled ? [] : .isButton)
        .accessibilityLabel("\(PlayerCopy.option) \(letter): \(text)")
        .accessibilityValue(state.value ?? "")
        .accessibilityAddTraits(state == .selected ? .isSelected : [])
    }

    private var statusWord: String? {
        switch state {
        case .idle, .selected: return nil
        default: return state.value
        }
    }

    private var icon: String {
        switch state {
        case .idle: return multiple ? "square" : "circle"
        case .selected: return multiple ? "checkmark.square.fill" : "largecircle.fill.circle"
        case .correctAnswer, .yourCorrectAnswer, .partOfAnswer: return "checkmark.circle.fill"
        case .yourWrongAnswer: return "xmark.circle.fill"
        }
    }

    private var tint: Color {
        switch state {
        case .idle: return BrandColor.textSecondary
        case .selected: return BrandColor.accentText
        case .correctAnswer, .yourCorrectAnswer, .partOfAnswer: return BrandColor.successText
        case .yourWrongAnswer: return BrandColor.errorText
        }
    }

    private var stroke: Color {
        switch state {
        case .idle: return BrandColor.border
        case .selected: return BrandColor.accent
        case .correctAnswer, .yourCorrectAnswer, .partOfAnswer: return BrandColor.success
        case .yourWrongAnswer: return BrandColor.error
        }
    }

    private var background: Color {
        switch state {
        case .idle: return BrandColor.surface
        case .selected: return BrandColor.accent.opacity(0.12)
        case .correctAnswer, .yourCorrectAnswer, .partOfAnswer: return BrandColor.success.opacity(0.12)
        case .yourWrongAnswer: return BrandColor.error.opacity(0.12)
        }
    }
}

// MARK: - Claim selection

/// The passage reads as continuous text (claims underlined), and the claims
/// are also listed as rows to choose from: the list is the way to select, so
/// it works the same with VoiceOver, Switch Control and large text.
struct ClaimSelectionView: View {
    let model: LessonPlayerModel
    let selection: ClaimSelectionActivity

    var body: some View {
        let record = model.record
        let draft: Set<String> = { if case .claims(let s)? = record.draft { return s }; return [] }()
        let submitted: Set<String>? = { if case .claims(let s)? = record.lastSubmission?.response { return s }; return nil }()
        VStack(alignment: .leading, spacing: BrandSpacing.sm) {
            Text(PlayerCopy.chooseClaim)
                .font(BrandFont.caption)
                .foregroundStyle(BrandColor.textSecondary)
            ForEach(Array(selection.claims.enumerated()), id: \.offset) { index, segment in
                let id = segment.claimId ?? ""
                OptionRow(
                    letter: PlayerCopy.letter(index),
                    text: "“\(segment.text)”",
                    state: rowState(id: id, draft: draft, submitted: submitted, correct: selection.correct,
                                    phase: record.phase, revealed: record.revealed),
                    multiple: selection.selection == .multiple,
                    enabled: record.phase == .viewing
                ) { model.send(.toggleClaim(id)) }
                .accessibilityIdentifier("player.claim.\(id)")
            }
        }
    }
}

// MARK: - Hints and feedback

struct HintList: View {
    let hints: [String]
    var body: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.xs) {
            ForEach(Array(hints.enumerated()), id: \.offset) { _, hint in
                Label(hint, systemImage: "lightbulb")
                    .font(BrandFont.body)
                    .foregroundStyle(BrandColor.text)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityLabel("\(PlayerCopy.hint): \(hint)")
            }
        }
        .padding(BrandSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(BrandColor.surface, in: RoundedRectangle(cornerRadius: BrandRadius.md, style: .continuous))
    }
}

struct FeedbackPanel: View {
    let activity: Activity
    let submission: Submission
    let revealed: Bool

    var body: some View {
        let look = FeedbackLook(status: submission.status)
        VStack(alignment: .leading, spacing: BrandSpacing.sm) {
            Label(look.title, systemImage: look.icon)
                .font(BrandFont.bodyEmphasized)
                .foregroundStyle(look.tint)
            ForEach(lines, id: \.self) { line in
                Text(line)
                    .font(BrandFont.body)
                    .foregroundStyle(BrandColor.text)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(BrandSpacing.md + 2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(look.tint.opacity(0.10), in: RoundedRectangle(cornerRadius: BrandRadius.lg, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: BrandRadius.lg, style: .continuous).stroke(look.tint.opacity(0.6), lineWidth: 1))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("player.feedback")
    }

    /// The feedback text: the answer-specific line, then any revealed answer,
    /// misconception correction, hint or fallback guidance. Short by design.
    private var lines: [String] {
        var out: [String] = []
        switch (activity.kind, submission.status) {
        case (.shortResponse, .ungraded(.support)):
            out.append(PlayerCopy.supportShown)
        case (.shortResponse(let sr), .ungraded):
            out.append(sr.fallbackGuidance)
        case (.shortResponse(let sr), .graded(let verdict)):
            if let f = submission.feedback { out.append(f) }
            for id in submission.flags {
                if let flag = sr.rubric.flags.first(where: { $0.id == id }) { out.append(flag.correction) }
            }
            if verdict != .correct, let hint = submission.hint { out.append("\(PlayerCopy.hint): \(hint)") }
            if verdict != .correct, revealed { out.append(PlayerCopy.exemplar(sr.exemplar)) }
        case (.shortResponse, .pending), (.practice, .pending):
            break
        case (.practice(let p), .notGraded):
            if let reply = submission.feedback { out.append(reply) }
            out.append(p.notice)
        case (.practice, .ungraded(.support)):
            out.append(PlayerCopy.supportShown)
        case (.practice(let p), .ungraded):
            out.append(p.fallbackGuidance)
        default:
            if let f = submission.feedback, !f.isEmpty { out.append(f) }
            if revealed, submission.status.verdict != .correct, let answer = revealedAnswer {
                out.append(answer)
            }
        }
        return out
    }

    private var revealedAnswer: String? {
        switch activity.kind {
        case .choice(let c):
            let texts = c.options.filter { c.correct.contains($0.id) }.map(\.text)
            return PlayerCopy.revealed(texts.joined(separator: "; "))
        case .claimSelection(let s):
            let texts = s.claims.filter { s.correct.contains($0.claimId ?? "") }.map { "“\($0.text)”" }
            return PlayerCopy.revealed(texts.joined(separator: "; "))
        case .shortResponse, .practice:
            return nil
        }
    }
}

struct FeedbackLook {
    let title: String
    let icon: String
    let tint: Color

    init(status: GradingStatus) {
        switch status {
        case .graded(.correct):
            title = PlayerCopy.correct; icon = "checkmark.circle.fill"; tint = BrandColor.successText
        case .graded(.partial):
            title = PlayerCopy.partly; icon = "circle.lefthalf.filled"; tint = BrandColor.accentText
        case .graded(.incorrect):
            title = PlayerCopy.notQuite; icon = "arrow.uturn.backward.circle.fill"; tint = BrandColor.errorText
        case .notGraded:
            title = PlayerCopy.mercReplied; icon = "bubble.left.fill"; tint = BrandColor.accentText
        case .pending:
            title = PlayerCopy.checking; icon = "hourglass"; tint = BrandColor.textSecondary
        case .ungraded:
            title = PlayerCopy.notGradedYet; icon = "exclamationmark.circle.fill"; tint = BrandColor.textSecondary
        }
    }
}

// MARK: - Optional depth

struct DepthSection: View {
    let model: LessonPlayerModel
    let step: LessonStep

    private var why: [DepthItem] { step.depth.filter { $0.kind == .why } }
    private var examples: [DepthItem] { step.depth.filter { $0.kind == .example } }
    private var stages: [DepthItem] {
        step.depth.filter { if case .stage = $0.kind { return true } else { return false } }
    }

    var body: some View {
        let opened = model.record.depthOpened
        VStack(alignment: .leading, spacing: BrandSpacing.sm) {
            // What the learner opened sits first, in the order it was
            // authored (Go deeper stages in sequence), above what's left.
            ForEach(step.depth.filter { opened.contains($0.id) }) { item in
                DepthCard(item: item)
            }
            FlowLayout(spacing: BrandSpacing.sm) { buttons(opened) }
        }
    }

    @ViewBuilder
    private func buttons(_ opened: Set<String>) -> some View {
        ForEach(why + examples) { item in
            if !opened.contains(item.id) {
                DepthButton(title: item.title, icon: item.kind == .why ? "questionmark.circle" : "text.quote") {
                    model.send(.openDepth(item.id))
                }
            }
        }
        if let nextStage = stages.first(where: { !opened.contains($0.id) }) {
            DepthButton(title: opened.isDisjoint(with: stages.map(\.id)) ? PlayerCopy.goDeeper : PlayerCopy.goDeeperMore,
                        icon: "arrow.down.right.circle") {
                model.send(.openDepth(nextStage.id))
            }
        }
        if model.canAskMerc {
            DepthButton(title: PlayerCopy.askMerc, icon: "bubble.left.and.text.bubble.right") { model.askMerc() }
                .accessibilityHint(PlayerCopy.askMercHint)
        }
    }
}

struct DepthButton: View {
    let title: String
    let icon: String
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .font(BrandFont.caption.weight(.semibold))
                .padding(.horizontal, BrandSpacing.md)
                .frame(minHeight: 44)
                .background(BrandColor.surface, in: Capsule())
                .overlay(Capsule().stroke(BrandColor.border, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .foregroundStyle(BrandColor.accentText)
    }
}

struct DepthCard: View {
    let item: DepthItem
    var body: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.xs) {
            Text(item.title)
                .font(BrandFont.bodyEmphasized)
                .foregroundStyle(BrandColor.accentText)
            Text(item.body)
                .font(BrandFont.body)
                .foregroundStyle(BrandColor.text)
                .fixedSize(horizontal: false, vertical: true)
            if let origin = item.origin { OriginLabel(origin: origin) }
        }
        .padding(BrandSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(BrandColor.surface, in: RoundedRectangle(cornerRadius: BrandRadius.md, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

/// Lays its children out in rows, wrapping to the next row when one is full
/// (the optional-depth buttons). Each child keeps its natural size, capped
/// at the row width, so large text wraps inside a button instead of clipping.
struct FlowLayout: Layout {
    var spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(width: proposal.width ?? .infinity, subviews: subviews)
        let width = rows.map(\.width).max() ?? 0
        let height = rows.map(\.height).reduce(0, +) + spacing * CGFloat(max(rows.count - 1, 0))
        return CGSize(width: proposal.width ?? width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in arrange(width: bounds.width, subviews: subviews) {
            var x = bounds.minX
            for item in row.items {
                subviews[item.index].place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(item.size))
                x += item.size.width + spacing
            }
            y += row.height + spacing
        }
    }

    private struct Row {
        var items: [(index: Int, size: CGSize)] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func arrange(width: CGFloat, subviews: Subviews) -> [Row] {
        var rows: [Row] = [Row()]
        for index in subviews.indices {
            var size = subviews[index].sizeThatFits(.unspecified)
            if size.width > width {
                size = subviews[index].sizeThatFits(ProposedViewSize(width: width, height: nil))
            }
            let needed = rows[rows.count - 1].items.isEmpty ? size.width : rows[rows.count - 1].width + spacing + size.width
            if needed > width, !rows[rows.count - 1].items.isEmpty {
                rows.append(Row())
            }
            var row = rows[rows.count - 1]
            row.width = row.items.isEmpty ? size.width : row.width + spacing + size.width
            row.height = max(row.height, size.height)
            row.items.append((index, size))
            rows[rows.count - 1] = row
        }
        return rows.filter { !$0.items.isEmpty }
    }
}
