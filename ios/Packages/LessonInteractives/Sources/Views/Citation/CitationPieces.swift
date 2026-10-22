import SwiftUI
import DesignSystem

// The Citation That Wasn't's pieces, drawn on both platforms with the
// card's theme (`\.interactiveTheme`): the student's question, the example
// reply with its growing reference, the step strip, a candidate's bar, and
// the five drawn pieces. The Mac's own pieces (the night-sky reply, the
// candidate columns and their keys) are in Views/Mac/NightCitationCard.swift.

/// The scroll ids inside the card (a tap keeps what it changed in view;
/// DEBUG autoplay keeps the newest part in view; the reveal's id is the
/// framework's).
enum CitationScrollID {
    static let walk = "citation-walk"
    /// The step's heading ("Step 2 of 5 · Year").
    static let step = "citation-step"
    /// A draw's button ("Next piece", "See the finished reference"), under
    /// its result: what a draw scrolls to. Not the result and button
    /// together: at AX5 the title's draw is about 1,000 pt, taller than the
    /// reading area, and `scrollTo(_:anchor: nil)` doesn't define which
    /// edge of a part that can't fit it shows. The button always fits, so
    /// every iOS shows it with as much of the result above it as fits (all
    /// of it, whenever it fits).
    static let next = "citation-next"
    static let finished = "citation-finished"
    static let showMe = "citation-show-me"
    static let askedAgain = "citation-asked-again"
    static let end = "citation-end"
}

/// Where VoiceOver's focus goes on the iPhone after a tap that took away
/// the button pressed: what replaced it.
enum CitationVoiceOverTarget: Hashable, Sendable {
    case step, finished, reveal, rewritten
}

/// The iPhone's VoiceOver focus for the card (the Mac has none: its
/// keyboard flow moves focus, and VoiceOver follows it).
struct CitationVoiceOverFocus {
    #if os(iOS)
    var binding: AccessibilityFocusState<CitationVoiceOverTarget?>.Binding?

    init(binding: AccessibilityFocusState<CitationVoiceOverTarget?>.Binding) {
        self.binding = binding
    }
    #endif

    init() {}
}

extension View {
    /// This element takes VoiceOver's focus when `focus` moves to `target`
    /// (the iPhone; nothing on the Mac).
    @ViewBuilder
    func citationFocusTarget(_ target: CitationVoiceOverTarget, focus: CitationVoiceOverFocus) -> some View {
        #if os(iOS)
        if let binding = focus.binding {
            accessibilityFocused(binding, equals: target)
        } else {
            self
        }
        #else
        self
        #endif
    }
}

/// A candidate's VoiceOver traits: a button while its slot takes a guess;
/// once drawn it is no longer a control, and the model's pick is selected.
enum CitationCandidateTraits {
    static func traits(canGuess: Bool, picked: Bool) -> AccessibilityTraits {
        if canGuess { return .isButton }
        return picked ? .isSelected : []
    }
}

// MARK: - The reference

/// The reference as styled text: written pieces in `written`, the slot
/// being written as its placeholder underlined in `current`, the rest as
/// placeholders in `pending`. (No italic journal: the app's Lexend has no
/// italic face.)
enum CitationReferenceText {
    static func attributed(picks: [Int?], current: CitationSlot?, written: Color, pending: Color,
                           currentColor: Color) -> AttributedString {
        func piece(_ slot: CitationSlot) -> AttributedString {
            if let pick = picks[slot.rawValue] {
                var text = AttributedString(CitationContent.candidates(slot)[pick].text)
                text.foregroundColor = written
                return text
            }
            var text = AttributedString(CitationCopy.placeholder(slot))
            if slot == current {
                text.foregroundColor = currentColor
                text.underlineStyle = .single
            } else {
                text.foregroundColor = pending
            }
            return text
        }
        func plain(_ string: String) -> AttributedString {
            var text = AttributedString(string)
            text.foregroundColor = written
            return text
        }
        return piece(.firstAuthor) + plain(" (") + piece(.year) + plain("). ") + piece(.title) + plain(". ")
            + piece(.journal) + plain(", ") + piece(.volumeAndPages) + plain(".")
    }
}

// MARK: - The student's question

/// "Can you give me a study…": the student's own turn, on the trailing
/// side, as each platform draws it.
struct CitationStudentBubble: View {
    @Environment(\.interactiveTheme) private var theme
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Text(CitationCopy.studentQuestion)
            .interactiveText(.body)
            .foregroundStyle(foreground)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.vertical, theme.platform == .phone ? BrandSpacing.md : 9)
            .padding(.horizontal, theme.platform == .phone ? BrandSpacing.lg : 14)
            .background { background }
            .overlay { edge }
            .padding(.leading, theme.usesTables ? 0 : 36)
            .frame(maxWidth: .infinity, alignment: .trailing)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(CitationCopy.studentAccessibility)
    }

    private var shape: UnevenRoundedRectangle {
        let big: CGFloat = theme.platform == .phone ? BrandRadius.xl : 14
        let small: CGFloat = theme.platform == .phone ? BrandRadius.sm : 4
        return UnevenRoundedRectangle(topLeadingRadius: big, bottomLeadingRadius: big, bottomTrailingRadius: small,
                                      topTrailingRadius: big, style: .continuous)
    }

    private var foreground: Color {
        #if os(macOS)
        Night.ink
        #else
        .white
        #endif
    }

    @ViewBuilder private var background: some View {
        #if os(macOS)
        shape.fill(Night.accent.opacity(Night.Tint.student(dark: scheme == .dark)))
        #else
        // The student's bubble's hues, a step deeper so white reads at 5.5:1
        // or better on the night card (Lesson 1.1's typed sentence).
        shape.fill(LinearGradient(colors: [BrandColor.accentDark, BrandColor.mercViolet],
                                  startPoint: .topLeading, endPoint: .bottomTrailing))
        #endif
    }

    @ViewBuilder private var edge: some View {
        #if os(macOS)
        shape.strokeBorder(theme.increasedContrast ? Night.hairline
                               : Night.lumen.opacity(Night.Tint.studentEdge(dark: scheme == .dark)), lineWidth: 1)
        #else
        if theme.increasedContrast { shape.strokeBorder(Color.white.opacity(0.6), lineWidth: 1) }
        #endif
    }
}

// MARK: - The example reply (iPhone, and the Mac's narrow fallback is the sky)

/// The example reply on the iPhone's night card: a dashed well that says it
/// is an example, "Sure, here's one:", and the reference as far as it is
/// written.
struct CitationReplyWell: View {
    let header: String?
    let picks: [Int?]
    let current: CitationSlot?
    @Environment(\.interactiveTheme) private var theme

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: theme.platform == .phone ? BrandRadius.lg : 12, style: .continuous)
        VStack(alignment: .leading, spacing: theme.platform == .phone ? BrandSpacing.sm : 8) {
            if let header {
                Text(header)
                    .interactiveText(.calloutStrong)
                    .foregroundStyle(theme.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text(CitationCopy.replyEyebrow.uppercased())
                .interactiveText(.eyebrow)
                .foregroundStyle(theme.accentText)
                .fixedSize(horizontal: false, vertical: true)
            Text(CitationCopy.replyOpening)
                .interactiveText(.body)
                .foregroundStyle(theme.ink)
            Text(CitationReferenceText.attributed(picks: picks, current: current, written: theme.ink,
                                                  pending: theme.ink3, currentColor: theme.accentText))
                .interactiveText(.body)
                .fixedSize(horizontal: false, vertical: true)
                .contentTransition(.opacity)
        }
        .padding(theme.platform == .phone ? BrandSpacing.md : 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.wash(0.06), in: shape)
        .overlay {
            shape.strokeBorder(theme.increasedContrast ? theme.hairline : theme.accentText.opacity(0.7),
                               style: StrokeStyle(lineWidth: 1, dash: theme.increasedContrast ? [] : [5, 4]))
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(([header].compactMap { $0 } + [CitationCopy.referenceAccessibility(picks)]).joined(separator: ". "))
    }
}

// MARK: - The step strip

/// Five short segments, one per slot: written (a check), being written (a
/// filled bar and bold name), still to come (hollow). Decoration, so it
/// goes where it doesn't fit and at the accessibility sizes; the step's
/// heading under it says the same in words, for VoiceOver too.
struct CitationSlotStrip: View {
    let walk: CitationWalk
    @Environment(\.interactiveTheme) private var theme

    var body: some View {
        if !theme.usesTables {
            ViewThatFits(in: .horizontal) {
                segments
                Color.clear.frame(height: 0)
            }
            .accessibilityHidden(true)
        }
    }

    private var segments: some View {
        HStack(alignment: .top, spacing: 6) {
            ForEach(CitationSlot.allCases, id: \.self) { slot in
                let done = walk.isDrawn(slot) && slot != walk.slot
                let now = slot == walk.slot
                VStack(alignment: .leading, spacing: 4) {
                    Capsule()
                        .fill(fill(done: done, now: now))
                        .overlay {
                            if !done && !now {
                                Capsule().strokeBorder(theme.increasedContrast ? theme.hairline : theme.ink3.opacity(0.6),
                                                       lineWidth: 1)
                            }
                        }
                        .frame(height: 5)
                    HStack(spacing: 3) {
                        if done {
                            Image(systemName: "checkmark")
                                .font(.system(size: theme.platform == .phone ? 9 : 8, weight: .bold))
                        }
                        Text(CitationCopy.slotShortName(slot))
                            .fontWeight(now ? .bold : .regular)
                            .lineLimit(1)
                            .fixedSize()
                    }
                    .interactiveText(.caption)
                    .foregroundStyle(now ? theme.ink : (done ? theme.accentText : theme.ink2))
                }
                .frame(minWidth: 44, maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func fill(done: Bool, now: Bool) -> Color {
        if now { return theme.increasedContrast ? theme.ink : theme.accentText }
        if done { return theme.increasedContrast ? theme.accentText : theme.accentText.opacity(0.55) }
        return .clear
    }
}

// MARK: - A chance's bar

/// A chance as a bar on a 0–100% track, so a flat slot (12%, 11%, 9%) and a
/// peaked one (62%) look as different as they are. The number is always
/// printed beside it; the bar is decoration at the accessibility sizes.
struct CitationBar: View {
    let percent: Int
    let highlighted: Bool
    @Environment(\.interactiveTheme) private var theme

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(theme.increasedContrast ? theme.hairline.opacity(0.6) : theme.wash(0.16))
                Capsule()
                    .fill(highlighted ? theme.accentText : theme.ink3)
                    .frame(width: max(geo.size.width * CGFloat(percent) / 100, 4))
            }
        }
        .frame(height: 6)
        .accessibilityHidden(true)
    }
}

// MARK: - A candidate as a row (the iPhone; the Mac when narrow)

/// One candidate next piece: its words, its chance (printed and as a bar)
/// and, once the slot is drawn, "picked" with a check on the model's pick
/// and "your guess" on the student's. A row at least 44 pt tall on the
/// iPhone. At the accessibility sizes the bar goes and the chance gets its
/// own line.
struct CitationCandidateRow: View {
    let walk: CitationWalk
    let slot: CitationSlot
    let index: Int
    @Environment(\.interactiveTheme) private var theme

    private var candidate: CitationCandidate { CitationContent.candidates(slot)[index] }
    private var drawn: Bool { walk.isDrawn(slot) }
    private var picked: Bool { drawn && walk.pick(slot) == index }
    private var guessed: Bool { walk.guess(at: slot) == index }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if theme.usesTables {
                Text(candidate.text)
                    .interactiveText(.calloutStrong)
                    .foregroundStyle(textColor)
                    .fixedSize(horizontal: false, vertical: true)
                Text("\(candidate.percent)%")
                    .interactiveText(.callout)
                    .monospacedDigit()
                    .foregroundStyle(theme.ink2)
            } else {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(candidate.text)
                        .interactiveText(.calloutStrong)
                        .foregroundStyle(textColor)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 4)
                    Text("\(candidate.percent)%")
                        .interactiveText(.calloutStrong)
                        .monospacedDigit()
                        .foregroundStyle(picked ? theme.accentText : theme.ink2)
                        .fixedSize()
                }
                CitationBar(percent: candidate.percent, highlighted: picked)
            }
            if picked || (drawn && guessed) {
                CitationTags(picked: picked, guessed: guessed)
            }
        }
        .padding(.horizontal, theme.platform == .phone ? BrandSpacing.md : 12)
        .padding(.vertical, theme.platform == .phone ? BrandSpacing.sm + 2 : 8)
        .frame(maxWidth: .infinity, minHeight: theme.minTarget, alignment: .leading)
        .background { CitationWellBackground(picked: picked, guessed: drawn && guessed) }
    }

    private var textColor: Color {
        drawn && !picked && !guessed ? theme.ink2 : theme.ink
    }
}

/// "✓ picked" and "your guess": words beside the glyphs, never colour
/// alone. The guess's hand is decoration (it goes at the accessibility
/// sizes); the pick's check stays.
struct CitationTags: View {
    let picked: Bool
    let guessed: Bool
    @Environment(\.interactiveTheme) private var theme

    var body: some View {
        let layout = theme.usesTables
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 2))
            : AnyLayout(HStackLayout(spacing: 12))
        layout {
            if picked {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.circle.fill")
                        .accessibilityHidden(true)
                    Text(CitationCopy.pickedTag)
                }
                .foregroundStyle(theme.accentText)
            }
            if guessed {
                HStack(spacing: 4) {
                    if !theme.usesTables {
                        Image(systemName: "hand.point.up.left")
                            .accessibilityHidden(true)
                    }
                    Text(CitationCopy.guessTag)
                }
                .foregroundStyle(theme.ink2)
            }
        }
        .interactiveText(.caption)
        .fontWeight(.semibold)
    }
}

/// A candidate's well: raised before the draw; the model's pick lit (a wash
/// and an accent edge, solid under Increase Contrast); the student's guess,
/// when it wasn't the pick, a dashed edge.
struct CitationWellBackground: View {
    let picked: Bool
    let guessed: Bool
    @Environment(\.interactiveTheme) private var theme

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: theme.platform == .phone ? 14 : 10, style: .continuous)
        ZStack {
            shape.fill(picked ? theme.wash(0.18) : theme.raised)
            if picked {
                shape.strokeBorder(theme.increasedContrast ? theme.ink : theme.accentText,
                                   lineWidth: theme.increasedContrast ? 2 : 1.5)
            } else if guessed {
                shape.strokeBorder(theme.increasedContrast ? theme.ink2 : theme.ink3,
                                   style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
            } else {
                shape.strokeBorder(theme.wellEdge, lineWidth: 1)
            }
        }
    }
}

// MARK: - The five drawn pieces

/// The finished walk, one row per slot: the slot, the piece drawn, its
/// chance and bar, and a check with "picked". After the reveal all five
/// light up at once: each was just a likely piece, none the one that made
/// it up.
struct CitationPickRows: View {
    let path: Int
    let lit: Bool
    @Environment(\.interactiveTheme) private var theme
    #if os(iOS)
    @ScaledMetric(relativeTo: .caption) private var labelWidth: CGFloat = 58
    #else
    private let labelWidth: CGFloat = 64
    #endif

    var body: some View {
        VStack(alignment: .leading, spacing: theme.platform == .phone ? BrandSpacing.sm : 8) {
            ForEach(CitationSlot.allCases, id: \.self) { slot in
                row(slot)
                    .padding(.horizontal, theme.platform == .phone ? BrandSpacing.md : 12)
                    .padding(.vertical, theme.platform == .phone ? BrandSpacing.sm : 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background { glow }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(CitationCopy.pickRowAccessibility(path: path, slot: slot))
            }
        }
    }

    @ViewBuilder
    private func row(_ slot: CitationSlot) -> some View {
        let candidate = CitationContent.picked(path: path, slot: slot)
        if theme.usesTables {
            VStack(alignment: .leading, spacing: 2) {
                Text(CitationCopy.slotName(slot))
                    .interactiveText(.caption)
                    .foregroundStyle(theme.ink2)
                Text(candidate.text)
                    .interactiveText(.calloutStrong)
                    .foregroundStyle(theme.ink)
                Text("\(candidate.percent)%")
                    .interactiveText(.callout)
                    .monospacedDigit()
                    .foregroundStyle(theme.ink2)
                CitationTags(picked: true, guessed: false)
            }
            .fixedSize(horizontal: false, vertical: true)
        } else {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(CitationCopy.slotShortName(slot))
                    .interactiveText(.caption)
                    .foregroundStyle(theme.ink2)
                    .frame(width: labelWidth, alignment: .leading)
                VStack(alignment: .leading, spacing: 5) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: theme.platform == .phone ? 13 : 11, weight: .semibold))
                            .foregroundStyle(theme.accentText)
                            .accessibilityHidden(true)
                        Text(candidate.text)
                            .interactiveText(.callout)
                            .foregroundStyle(theme.ink)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 4)
                        Text("\(candidate.percent)%")
                            .interactiveText(.calloutStrong)
                            .monospacedDigit()
                            .foregroundStyle(theme.ink2)
                            .fixedSize()
                    }
                    CitationBar(percent: candidate.percent, highlighted: lit)
                }
            }
        }
    }

    @ViewBuilder private var glow: some View {
        let shape = RoundedRectangle(cornerRadius: theme.platform == .phone ? 12 : 10, style: .continuous)
        if lit {
            shape.fill(theme.wash(0.2))
                .overlay(shape.strokeBorder(theme.increasedContrast ? theme.ink : theme.accentText,
                                            lineWidth: theme.increasedContrast ? 2 : 1.5))
                .shadow(color: theme.lit ? theme.lumen.opacity(0.45) : .clear, radius: 8)
        } else {
            shape.fill(theme.raised)
                .overlay(shape.strokeBorder(theme.wellEdge, lineWidth: 1))
        }
    }
}
