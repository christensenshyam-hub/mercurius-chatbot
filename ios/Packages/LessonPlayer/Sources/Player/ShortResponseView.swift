import SwiftUI
import DesignSystem

/// The one place the player shows a text field: a short original answer.
/// The learner's text is kept through every state (checking, not graded yet,
/// not yet) so nothing they wrote is lost.
struct ShortResponseView: View {
    let model: LessonPlayerModel
    let activity: ShortResponseActivity
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
                    Text(activity.placeholder)
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
                .accessibilityLabel(activity.placeholder)
                .accessibilityIdentifier("player.response")
            }
            .padding(BrandSpacing.sm)
            .background(BrandColor.surface, in: RoundedRectangle(cornerRadius: BrandRadius.md, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: BrandRadius.md, style: .continuous)
                    .stroke(focused ? BrandColor.accent : BrandColor.border, lineWidth: focused ? 2 : 1)
            )
            Text(PlayerCopy.characters(text.count, of: activity.maxCharacters))
                .font(BrandFont.caption)
                .foregroundStyle(BrandColor.textSecondary)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .onChange(of: model.record.phase) { _, phase in
            if phase != .viewing { focused = false }
        }
    }
}
