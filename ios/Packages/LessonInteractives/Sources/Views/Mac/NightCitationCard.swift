#if os(macOS)
import SwiftUI
import DesignSystem

/// The Citation That Wasn't on the Mac (U1L3): Night Studio's lit card in
/// the lesson's reading column, compact ("Try it") below 440 pt. The
/// example reply is a night sky that the reference fills in under, and it
/// glows once when the reference is finished; on a wide card each slot's
/// three candidates stand as columns, their bars rising to their chances.
///
/// Keys (the tokenizer's contract): Tab reaches each candidate; ←/→ (and
/// ↑/↓ while the lesson's check isn't waiting) move between a slot's
/// candidates while one has focus; Space or Return picks. "Next piece",
/// the step chips, "Show me" and "Write it again" are in the Tab loop. A
/// focused control holds Return from the lesson's check; A–D and 1–4 still
/// answer it. A click picks without keeping the keyboard.
struct NightCitationCard: View {
    private let context: InteractiveCardContext

    init(_ context: InteractiveCardContext) {
        self.context = context
    }

    var body: some View {
        let state = context.state { CitationState(spoiled: $0.spoiled) }
        InteractiveCardShell(id: context.id, title: CitationCopy.title, summary: state.summary,
                             compactLine: CitationCopy.compactLine) {
            CitationCardBody(state: state)
        }
    }
}

// MARK: - The night-sky reply

/// The example reply as a night sky (night in both appearances, like the
/// tokenizer's map): its label, "Sure, here's one:" and the reference in
/// the sky's ink, the slot being written underlined. `glow` (0–1) lights
/// its edge once when the reference is finished.
struct NightCitationSkyReply: View {
    let header: String?
    let picks: [Int?]
    let current: CitationSlot?
    let glow: Double
    @Environment(\.interactiveTheme) private var theme

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)
        VStack(alignment: .leading, spacing: 8) {
            if let header {
                Text(header)
                    .nightFont(.calloutStrong)
                    .foregroundStyle(NightSky.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text(CitationCopy.replyEyebrow.uppercased())
                .nightFont(.eyebrow)
                .foregroundStyle(NightSky.ink2)
            Text(CitationCopy.replyOpening)
                .nightFont(.body)
                .foregroundStyle(NightSky.ink)
            Text(CitationReferenceText.attributed(picks: picks, current: current, written: NightSky.ink,
                                                  pending: NightSky.ink2, currentColor: NightSky.ink))
                .nightFont(.body)
                .fixedSize(horizontal: false, vertical: true)
                .contentTransition(.opacity)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            ZStack {
                if theme.increasedContrast {
                    NightSky.top
                } else {
                    LinearGradient(colors: [NightSky.top, NightSky.bottom], startPoint: .top, endPoint: .bottom)
                    NightStarField(count: 40, brightness: 0.9)
                }
            }
            .clipShape(shape)
        }
        .overlay(shape.strokeBorder(Color.white.opacity(theme.increasedContrast ? 0.55 : 0.14), lineWidth: 1))
        .overlay {
            if glow > 0 {
                shape.strokeBorder(NightSky.ink.opacity(0.85 * glow), lineWidth: 2)
                    .shadow(color: theme.lumen.opacity(0.8 * glow), radius: 12)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(([header].compactMap { $0 } + [CitationCopy.referenceAccessibility(picks)]).joined(separator: ". "))
    }
}

// MARK: - The candidates as columns

/// A slot's three candidates side by side, each a column: its chance, its
/// bar rising on a 0–100% scale, its words, and once drawn "✓ picked" and
/// "your guess". Each column is a keyboard control (`NightCitationCandidateKeys`).
struct NightCitationColumns: View {
    let walk: CitationWalk
    var focus: FocusState<Int?>.Binding
    /// The candidate picked, and whether from the keyboard.
    let onPick: (Int, Bool) -> Void
    @Environment(\.interactiveTheme) private var theme

    /// The bar at 100%.
    static let barHeight: CGFloat = 96
    /// Columns need room for a title in three or four lines: narrower cards
    /// use rows.
    static func fits(width: CGFloat) -> Bool { width >= 420 }

    var body: some View {
        let slot = walk.slot
        HStack(alignment: .top, spacing: 10) {
            ForEach(CitationContent.candidates(slot).indices, id: \.self) { index in
                let picked = walk.isDrawn(slot) && walk.pick(slot) == index
                column(slot, index)
                    .modifier(NightCitationCandidateKeys(slot: slot, index: index,
                                                         focus: focus, isEnabled: walk.canGuess,
                                                         shape: RoundedRectangle(cornerRadius: 12, style: .continuous)) {
                        onPick(index, $0)
                    })
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(CitationCopy.candidateAccessibility(slot, index: index))
                    .accessibilityValue(CitationCopy.candidateValue(walk, slot: slot, index: index))
                    .accessibilityHint(walk.canGuess ? CitationCopy.walkPrompt : "")
                    .accessibilityAddTraits(picked ? [.isButton, .isSelected] : .isButton)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(CitationCopy.slotName(slot))
    }

    private func column(_ slot: CitationSlot, _ index: Int) -> some View {
        let candidate = CitationContent.candidates(slot)[index]
        let drawn = walk.isDrawn(slot)
        let picked = drawn && walk.pick(slot) == index
        let guessed = walk.guess(at: slot) == index
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
        return VStack(spacing: 8) {
            Text("\(candidate.percent)%")
                .font(NightType.lexend(17, semibold: true))
                .monospacedDigit()
                .foregroundStyle(picked ? Night.accentText : Night.ink2)
            ZStack(alignment: .bottom) {
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(theme.increasedContrast ? Night.hairline.opacity(0.5) : Night.lumen.opacity(0.12))
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(picked ? AnyShapeStyle(Night.progressLight(increasedContrast: theme.increasedContrast))
                                 : AnyShapeStyle(Night.ink3))
                    .frame(height: max(Self.barHeight * CGFloat(candidate.percent) / 100, 4))
            }
            .frame(width: 30, height: Self.barHeight)
            .accessibilityHidden(true)
            Text(candidate.text)
                .nightFont(.calloutStrong)
                .foregroundStyle(drawn && !picked && !guessed ? Night.ink2 : Night.ink)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            if picked || (drawn && guessed) {
                CitationTags(picked: picked, guessed: guessed)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background { CitationWellBackground(picked: picked, guessed: drawn && guessed) }
        .contentShape(shape)
    }
}

/// A candidate on the Mac, as one keyboard control in its slot's group: in
/// the Tab loop whatever the Full Keyboard Access setting, Night's ring
/// while it has the keyboard, ←/→/↑/↓ move to the slot's other candidates
/// only while one has focus, Space or Return picks it, a click picks it
/// without keeping the keyboard, and while focused it holds Return from the
/// lesson's check (A–D and 1–4 still answer the check; a pick there takes
/// the keyboard back).
struct NightCitationCandidateKeys<S: InsettableShape>: ViewModifier {
    let slot: CitationSlot
    let index: Int
    var focus: FocusState<Int?>.Binding
    let isEnabled: Bool
    let shape: S
    /// `true`: picked from the keyboard.
    let onPick: (Bool) -> Void

    @Environment(\.interactiveKeyRouter) private var router
    @Environment(\.interactiveTheme) private var theme
    @State private var holder = UUID()
    @State private var hovering = false

    func body(content: Content) -> some View {
        let focused = focus.wrappedValue == index
        content
            .overlay {
                if hovering && isEnabled {
                    shape.fill(Night.lumen.opacity(Night.Tint.hover)).allowsHitTesting(false)
                }
            }
            .contentShape(shape)
            .onHover { hovering = $0 }
            .onTapGesture {
                guard isEnabled else { return }
                onPick(false)
                if focus.wrappedValue != nil { focus.wrappedValue = nil }
            }
            .focusable(isEnabled, interactions: .edit)
            .focused(focus, equals: index)
            .focusEffectDisabled()
            .overlay {
                if focused {
                    shape.inset(by: -3 - theme.focusRingWidth / 2)
                        .stroke(theme.focusRing, lineWidth: theme.focusRingWidth)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
            }
            .onKeyPress(keys: [.space, .return], phases: .down) { _ in
                guard isEnabled else { return .ignored }
                onPick(true)
                return .handled
            }
            .onKeyPress(keys: [.leftArrow, .rightArrow, .upArrow, .downArrow], phases: .down) { press in
                guard isEnabled else { return .ignored }
                let arrow: InteractiveArrow = press.key == .leftArrow || press.key == .upArrow ? .previous : .next
                focus.wrappedValue = CitationContent.neighbour(of: index, moving: arrow, in: slot)
                return .handled
            }
            .onChange(of: focused) { _, now in router?.hold(holder, now) }
            .onChange(of: router?.checkPicks) { _, _ in if focused { focus.wrappedValue = nil } }
            .onDisappear { router?.hold(holder, false) }
            // VoiceOver's press picks it, as the shared controls' does.
            .accessibilityAction { if isEnabled { onPick(false) } }
    }
}
#endif
