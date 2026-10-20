#if os(macOS)
import SwiftUI
import DesignSystem

/// The lesson's [Q] check on the Mac (SPEC.md §5.3.3, D9): pick an answer,
/// then **Lock it in**. Lock it in grades on the device, says the result to
/// VoiceOver, and calls `onSelect`, which sends "I picked B) …" exactly as
/// the iPhone's tap does; Merc's real follow-up then streams below. A pick
/// alone sends nothing.
///
/// From the keyboard, while the card has focus (Tab to it, or click it):
/// A–D or 1–4 pick, ↑/↓ move the pick, Return locks it in. Typing in the
/// composer never picks.
///
/// The check stays where it streamed: there is no docked tray on the Mac.
struct NightCheckCard: View {
    let quiz: QuizBlock
    /// Live only on the latest reply, complete, with nothing in flight.
    let isEnabled: Bool
    /// The student's earlier answer, from the "I picked X)" turn after it.
    let answeredIndex: Int?
    let onSelect: (Int) -> Void

    /// Picked, not yet locked in.
    @State private var pick: Int?
    /// Locked in on this card (before the next turn carries it).
    @State private var locked: Int?
    @FocusState private var focused: Bool
    @NightSettings private var night
    @Environment(\.colorScheme) private var scheme

    private var gradedPick: Int? { locked ?? answeredIndex }
    private var graded: Bool { gradedPick != nil }
    private var answerable: Bool { isEnabled && !graded }
    /// A pick shows only while it can still be locked in.
    private var livePick: Int? { answerable ? pick : nil }

    private var eyebrow: String {
        if graded { return NightReplyCopy.checkAnswered }
        return isEnabled ? NightReplyCopy.checkOpen : NightReplyCopy.checkInert
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Night.Radius.card, style: .continuous)
        VStack(alignment: .leading, spacing: 14) {
            NightEyebrow(eyebrow, systemImage: graded ? "checkmark.circle" : "circle.dashed")
            Text(quiz.stem)
                .nightFont(.title2)
                .foregroundStyle(Night.ink)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            VStack(spacing: 8) {
                ForEach(Array(quiz.options.enumerated()), id: \.offset) { index, option in
                    row(index: index, option: option)
                }
            }
            if let livePick {
                NightPrimaryButton(NightReplyCopy.lockIn, systemImage: "lock") { lockIn() }
                    .help(NightReplyCopy.lockInHelp)
                    .accessibilityLabel(NightReplyCopy.lockInAccessibility(letter: ChatAnnouncement.letter(livePick)))
                    .transition(.opacity)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .nightLit(radius: Night.Radius.card)
        // In the Tab loop whatever the Full Keyboard Access setting, like the
        // unit check's cards, with Night's own ring.
        .focusable(answerable, interactions: .edit)
        .focused($focused)
        .focusEffectDisabled()
        .overlay {
            if focused && answerable {
                shape.inset(by: -3 - night.focusRingWidth / 2)
                    .stroke(Night.focusRing, lineWidth: night.focusRingWidth)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }
        .onKeyPress(phases: .down) { press in handleKey(press) }
        .help(answerable ? NightReplyCopy.checkCardHelp : "")
        .preference(key: NightUncommittedPickKey.self, value: livePick != nil)
        .animation(night.animation(Night.Motion.tap), value: pick)
        .animation(night.animation(Night.Motion.layout), value: locked)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Question: \(quiz.stem)")
        #if DEBUG
        .onAppear(perform: applyDebugState)
        .onChange(of: isEnabled) { _, _ in applyDebugState() }
        #endif
    }

    // MARK: Picking and locking in

    private func choose(_ index: Int) {
        guard answerable, quiz.options.indices.contains(index) else { return }
        pick = index
    }

    private func lockIn() {
        guard answerable, let pick else { return }
        locked = pick
        AccessibilityNotification.Announcement(ChatAnnouncement.quizPick(index: pick, quiz: quiz)).post()
        onSelect(pick)
    }

    private func handleKey(_ press: KeyPress) -> KeyPress.Result {
        guard answerable, !press.modifiers.contains(.command) else { return .ignored }
        switch press.key {
        case .return:
            guard pick != nil else { return .ignored }
            lockIn()
            return .handled
        case .upArrow:
            pick = NightCheckKeys.moved(pick, by: -1, optionCount: quiz.options.count)
            return .handled
        case .downArrow:
            pick = NightCheckKeys.moved(pick, by: 1, optionCount: quiz.options.count)
            return .handled
        default:
            guard let index = NightCheckKeys.optionIndex(forKey: press.characters,
                                                         optionCount: quiz.options.count) else { return .ignored }
            choose(index)
            return .handled
        }
    }

    // MARK: Rows

    private enum RowState { case rest, picked, correct, wrong, other }

    private func state(of index: Int) -> RowState {
        if let gradedPick {
            if index == quiz.answerIndex { return .correct }
            if index == gradedPick { return .wrong }
            return .other
        }
        return livePick == index ? .picked : .rest
    }

    private func row(index: Int, option: String) -> some View {
        let state = state(of: index)
        let shape = RoundedRectangle(cornerRadius: Night.Radius.row, style: .continuous)
        let spoken = CheckQuizCard.optionAccessibility(index: index, option: option, pick: gradedPick,
                                                       answerIndex: quiz.answerIndex)
        return Button {
            choose(index)
            if answerable { focused = true }
        } label: {
            HStack(alignment: .center, spacing: 12) {
                disc(index: index, state: state)
                Text(option)
                    .nightFont(.body)
                    .foregroundStyle(state == .other ? Night.ink2 : Night.ink)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                switch state {
                case .correct:
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Night.successText)
                        .accessibilityHidden(true)
                case .wrong:
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Night.errorText)
                        .accessibilityHidden(true)
                default:
                    EmptyView()
                }
            }
            .padding(.horizontal, Night.Space.rowHorizontal)
            .padding(.vertical, Night.Space.rowVertical)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .background(fill(state), in: shape)
            .overlay(shape.strokeBorder(stroke(state), lineWidth: strokeWidth(state)))
            .contentShape(shape)
            .nightHover(cornerRadius: Night.Radius.row, isEnabled: answerable)
        }
        .buttonStyle(.plain)
        .allowsHitTesting(answerable)
        .accessibilityLabel(spoken.label)
        .accessibilityValue(spoken.value ?? (state == .picked ? "Picked, not locked in" : ""))
        .accessibilityAddTraits(state == .picked || state == .wrong || (state == .correct && gradedPick == index)
                                ? .isSelected : [])
        .accessibilityRemoveTraits(answerable ? [] : .isButton)
        .accessibilityHint(answerable ? "Picks this answer. Then lock it in." : "")
    }

    private func fill(_ state: RowState) -> Color {
        let dark = scheme == .dark
        switch state {
        case .rest, .other: return Night.surfaceRaised
        case .picked: return Night.accent.opacity(Night.Tint.selected(dark: dark))
        case .correct: return Night.success.opacity(Night.Tint.answer)
        case .wrong: return Night.error.opacity(Night.Tint.answer)
        }
    }

    private func stroke(_ state: RowState) -> Color {
        switch state {
        case .rest, .other: return night.increasedContrast ? Night.hairline : .clear
        case .picked: return Night.accentText
        case .correct: return Night.success
        case .wrong: return Night.error
        }
    }

    private func strokeWidth(_ state: RowState) -> CGFloat {
        switch state {
        case .rest, .other: return 1.5
        default: return 2
        }
    }

    /// The 26 pt letter disc. Picked: the letter in white on `prominent`
    /// (7.9:1; white on `accent` would be 4.47:1). Correct: a check on
    /// `success`. Wrong: the letter in `errorText` in an `errorText` ring.
    @ViewBuilder
    private func disc(index: Int, state: RowState) -> some View {
        let letter = ChatAnnouncement.letter(index)
        ZStack {
            switch state {
            case .picked:
                Circle().fill(Night.prominent)
                discLetter(letter, color: .white)
            case .correct:
                Circle().fill(Night.success)
                Image(systemName: "checkmark")
                    .font(.system(size: 12, weight: .heavy))
                    .foregroundStyle(Night.surface)
            case .wrong:
                Circle().strokeBorder(Night.errorText, lineWidth: 1.5)
                discLetter(letter, color: Night.errorText)
            case .rest, .other:
                Circle().strokeBorder(night.increasedContrast ? Night.ink3 : Night.ink3.opacity(0.55), lineWidth: 1.5)
                discLetter(letter, color: Night.ink2)
            }
        }
        .frame(width: 26, height: 26)
        .accessibilityHidden(true)
    }

    private func discLetter(_ letter: String, color: Color) -> some View {
        Text(letter)
            .font(NightType.lexend(13, semibold: true))
            .foregroundStyle(color)
    }

    #if DEBUG
    /// `-NightCheckState picked|answered` (shots only): the live check with
    /// B picked, or B picked and locked in a moment later, which sends it
    /// through the real path. Once per launch.
    private func applyDebugState() {
        guard answerable, !NightCheckCard.didApplyDebugState,
              let state = UserDefaults.standard.string(forKey: "NightCheckState"),
              state == "picked" || state == "answered", quiz.options.count > 1 else { return }
        NightCheckCard.didApplyDebugState = true
        pick = 1
        if state == "answered" {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { lockIn() }
        }
    }

    @MainActor static var didApplyDebugState = false
    #endif
}

/// Whether a check on screen holds a pick that isn't locked in: the lesson's
/// Escape must not throw it away.
struct NightUncommittedPickKey: PreferenceKey {
    static let defaultValue = false
    static func reduce(value: inout Bool, nextValue: () -> Bool) {
        value = value || nextValue()
    }
}
#endif
