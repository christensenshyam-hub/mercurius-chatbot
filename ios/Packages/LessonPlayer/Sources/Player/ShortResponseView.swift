import SwiftUI
import DesignSystem

/// The one place the player shows a text field: a short original answer.
/// The learner's text is kept through every state (checking, not graded yet,
/// not yet) so nothing they wrote is lost.
struct ShortResponseView: View {
    let model: LessonPlayerModel
    let maxCharacters: Int
    let placeholder: String
    @FocusState private var focused: Bool

    private var text: String {
        if case .text(let t)? = model.record.draft { return t }
        if case .text(let t)? = model.record.lastSubmission?.response { return t }
        return ""
    }

    var body: some View {
        let editable = model.record.phase == .viewing
        VStack(alignment: .leading, spacing: BrandSpacing.xs) {
            ZStack(alignment: .topLeading) {
                if text.isEmpty {
                    Text(placeholder)
                        .font(BrandFont.body)
                        .foregroundStyle(BrandColor.textSecondary)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 8)
                        .accessibilityHidden(true)
                }
                TextEditor(text: Binding(
                    get: { text },
                    set: { model.send(.editText($0)) }
                ))
                .font(BrandFont.body)
                .foregroundStyle(BrandColor.text)
                .scrollContentBackground(.hidden)
                .frame(minHeight: 96)
                .focused($focused)
                .disabled(!editable)
                .accessibilityLabel(placeholder)
                .accessibilityIdentifier("player.response")
            }
            .padding(BrandSpacing.sm)
            .background(BrandColor.surface, in: RoundedRectangle(cornerRadius: BrandRadius.md, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: BrandRadius.md, style: .continuous)
                    .stroke(focused ? BrandColor.accent : BrandColor.border, lineWidth: focused ? 2 : 1)
            )
            Text(PlayerCopy.characters(text.count, of: maxCharacters))
                .font(BrandFont.caption)
                .foregroundStyle(BrandColor.textSecondary)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .onChange(of: model.record.phase) { _, phase in
            if phase != .viewing { focused = false }
        }
    }
}

/// A real first message to the live tutor: a suggestion to send as is, or
/// the learner's own words. Merc's reply appears in the feedback panel.
struct PracticeView: View {
    let model: LessonPlayerModel
    let practice: PracticeActivity

    var body: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.sm) {
            if model.record.phase == .viewing {
                Button {
                    model.send(.editText(practice.suggestion))
                } label: {
                    Label(PlayerCopy.useSuggestion(practice.suggestion), systemImage: "text.bubble")
                        .font(BrandFont.body)
                        .multilineTextAlignment(.leading)
                        .padding(BrandSpacing.md)
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                        .background(BrandColor.accent.opacity(0.10), in: RoundedRectangle(cornerRadius: BrandRadius.md, style: .continuous))
                }
                .buttonStyle(.plain)
                .foregroundStyle(BrandColor.accentText)
                .accessibilityIdentifier("player.practice.suggestion")
            }
            ShortResponseView(model: model, maxCharacters: practice.maxCharacters, placeholder: practice.placeholder)
        }
    }
}
