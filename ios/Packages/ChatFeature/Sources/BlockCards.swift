import SwiftUI
import DesignSystem

/// blocks_v1 native cards (Presentation P4): the lesson bubble renders
/// [KEY]/[EX] as branded cards and [Q] as a tappable multiple-choice check.
/// Styles sit in the `calloutCard` family (tinted rounded cards) and the
/// option rows lift `UnitTestView.optionRow`'s letter/tint/feedback pattern.

/// One-sentence takeaway card — "KEY IDEA" eyebrow + lightbulb.
struct KeyIdeaCard: View {
    let text: String
    let bodySize: CGFloat
    let font: Font

    var body: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.xs) {
            HStack(spacing: BrandSpacing.xs) {
                Image(systemName: "lightbulb.fill")
                    .font(.system(size: bodySize * 0.7, weight: .semibold))
                Text("KEY IDEA")
                    .font(.system(size: 11, weight: .heavy, design: .rounded))
                    .tracking(1.2)
            }
            .foregroundStyle(BrandColor.accent)
            .accessibilityHidden(true)
            Text(text)
                .font(font)
                .foregroundStyle(BrandColor.text)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 13)
        .padding(.horizontal, 14)
        .background(BrandColor.accent.opacity(0.08),
                    in: RoundedRectangle(cornerRadius: BrandRadius.lg, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Key idea: \(text)")
    }
}

/// Concrete-example card — "EXAMPLE" eyebrow on an elevated surface.
struct ExampleCard: View {
    let text: String
    let bodySize: CGFloat
    let font: Font

    var body: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.xs) {
            HStack(spacing: BrandSpacing.xs) {
                Image(systemName: "sparkles")
                    .font(.system(size: bodySize * 0.7, weight: .semibold))
                Text("EXAMPLE")
                    .font(.system(size: 11, weight: .heavy, design: .rounded))
                    .tracking(1.2)
            }
            .foregroundStyle(BrandColor.textSecondary)
            .accessibilityHidden(true)
            Text(text)
                .font(font)
                .foregroundStyle(BrandColor.text)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 13)
        .padding(.horizontal, 14)
        .background(BrandColor.surfaceElevated,
                    in: RoundedRectangle(cornerRadius: BrandRadius.lg, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: BrandRadius.lg, style: .continuous)
                .stroke(BrandColor.border, lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Example: \(text)")
    }
}

/// Tappable multiple-choice check. Tap → instant local grade (green/red +
/// haptic) → the host auto-sends "I picked B) …" as a normal user turn, so
/// the model reacts to the answer exactly like typed input.
struct CheckQuizCard: View {
    let quiz: QuizBlock
    let bodySize: CGFloat
    let stemFont: Font
    /// Whether taps are live (last assistant message, complete, phase idle).
    let isEnabled: Bool
    /// The student's prior pick for inert re-renders (recovered from the
    /// following user message's "I picked X)" prefix), nil if unanswered.
    let answeredIndex: Int?
    /// Fires with the picked index after local grading renders.
    let onSelect: (Int) -> Void

    @State private var localPick: Int?

    private var effectivePick: Int? { localPick ?? answeredIndex }
    private var graded: Bool { effectivePick != nil }

    var body: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.sm) {
            HStack(alignment: .firstTextBaseline, spacing: BrandSpacing.sm) {
                Image(systemName: "questionmark.bubble.fill")
                    .font(.system(size: bodySize * 0.9, weight: .semibold))
                    .foregroundStyle(BrandColor.accent)
                    .accessibilityHidden(true)
                Text(quiz.stem)
                    .font(stemFont)
                    .foregroundStyle(BrandColor.accent)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            ForEach(Array(quiz.options.enumerated()), id: \.offset) { index, option in
                optionRow(index: index, option: option)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 13)
        .padding(.horizontal, 14)
        .background(BrandColor.accent.opacity(0.10),
                    in: RoundedRectangle(cornerRadius: BrandRadius.lg, style: .continuous))
        .sensoryFeedback(.impact, trigger: localPick)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Question: \(quiz.stem)")
    }

    private func optionRow(index: Int, option: String) -> some View {
        let isPick = effectivePick == index
        let isAnswer = quiz.answerIndex == index

        let bg: Color
        let stroke: Color
        if graded {
            if isAnswer { bg = BrandColor.success.opacity(0.15); stroke = BrandColor.success }
            else if isPick { bg = BrandColor.error.opacity(0.15); stroke = BrandColor.error }
            else { bg = BrandColor.surface; stroke = BrandColor.border }
        } else {
            bg = BrandColor.surface; stroke = BrandColor.border
        }

        return Button {
            guard isEnabled, localPick == nil, answeredIndex == nil else { return }
            localPick = index
            onSelect(index)
        } label: {
            HStack(alignment: .top, spacing: BrandSpacing.sm) {
                Text(String(UnicodeScalar(65 + index)!))
                    .font(.system(size: bodySize * 0.8, weight: .bold, design: .rounded))
                    .foregroundStyle(graded && (isAnswer || isPick) ? stroke : BrandColor.accent)
                Text(option)
                    .font(.system(size: bodySize * 0.85))
                    .foregroundStyle(BrandColor.text)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                if graded && isAnswer {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(BrandColor.success)
                } else if graded && isPick {
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
        .disabled(!isEnabled || graded)
        .accessibilityHint(isEnabled && !graded ? "Double-tap to pick this answer" : "")
    }
}
