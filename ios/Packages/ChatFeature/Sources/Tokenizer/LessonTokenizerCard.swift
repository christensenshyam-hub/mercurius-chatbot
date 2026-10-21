#if os(iOS)
import SwiftUI
import DesignSystem

/// Lesson 1.1's interactive on the iPhone, "How a model reads “bank”": a
/// self-contained night-sky card in the lesson's thread, between the two
/// halves of the Merc reply that holds it (`LessonInteractiveAnchor` says
/// which reply and where; `LessonInteractiveSplit` cuts the bubble). The
/// iPhone hasn't adopted Night Studio, so the card brings its own night
/// (`NightSkyCard`): it looks the same in the app's light and dark
/// appearances and sits in both as a picture, not a surface. Its type,
/// spacing and shapes are the iPhone's (`BrandFont`, `BrandSpacing`,
/// `BrandRadius`), and every word is shared with the Mac (`TokenizerCopy`).
///
/// Four steps: the sentence the student types, its tokens with illustrative
/// IDs, "·bank"'s list of numbers, and the map of meaning, where starting
/// the sentence with some context moves "bank" toward its neighbours. It
/// sends, stores and tokenises nothing; the opening picked lives in the
/// lesson's `TokenizerState`, so a reply's re-render never resets it.
///
/// - Dynamic Type through AX5: the map's labels grow as far as its width
///   allows (`TokenizerMapScale`); past xLarge the card also says where
///   "bank" is in words, and at the accessibility sizes the map starts
///   folded behind "Show the map". Decoration goes first (the step numbers'
///   discs, the arrow), never a word.
/// - Openings are 44 pt or taller; a pick gives a selection haptic and
///   VoiceOver hears the finished sentence and where "bank" went.
/// - Reduce Motion: "bank" crossfades to its new place. Increase Contrast:
///   no glows or stars, solid edges, the HC values. Reduce Transparency:
///   every wash and edge solid, no glows.
/// - VoiceOver: the title and each step are headers, each step's picture is
///   one sentence, and the map is one sentence.
struct LessonTokenizerCard: View {
    static let scrollID = "lesson-interactive"
    static let mapScrollID = "lesson-interactive-map"
    static func stepScrollID(_ number: Int) -> String { "lesson-interactive-step-\(number)" }
    #if DEBUG
    static let topEdgeScrollID = "lesson-interactive-top-edge"
    #endif

    @Environment(TokenizerState.self) private var shared: TokenizerState?
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.accessibilityReduceTransparency) private var systemReduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.colorScheme) private var scheme
    @State private var local = TokenizerState()
    @ScaledMetric(relativeTo: .caption2) private var eyebrowSize: CGFloat = 11
    @ScaledMetric(relativeTo: .headline) private var stepDisc: CGFloat = 26

    private var state: TokenizerState { shared ?? local }
    private var sky: NightSkyCard {
        NightSkyCard(increasedContrast: contrast == .increased || DebugAccessibility.increasedContrast,
                     reduceTransparency: systemReduceTransparency || DebugAccessibility.reduceTransparency)
    }
    private var reduceMotion: Bool { systemReduceMotion || DebugAccessibility.reduceMotion }
    /// The accessibility sizes: decoration goes, every word stays.
    private var large: Bool { typeSize.isAccessibilitySize }

    static let padding: CGFloat = BrandSpacing.lg

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: BrandRadius.xl, style: .continuous)
        VStack(alignment: .leading, spacing: large ? BrandSpacing.xxl : BrandSpacing.xl) {
            header
            step(1, TokenizerCopy.step1) { typedSentence }
            step(2, TokenizerCopy.step2) { tokenStep }
                .id(Self.stepScrollID(2))
            step(3, TokenizerCopy.step3) { numbersStep }
                .id(Self.stepScrollID(3))
            step(4, TokenizerCopy.step4) { mapStep }
                .id(Self.mapScrollID)
        }
        .padding(Self.padding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background { cardBackground(shape) }
        .overlay(shape.strokeBorder(sky.edge, lineWidth: 1))
        // The lesson bubble's soft shadow, in light mode only: in dark the
        // lit edge separates the card from the screen.
        .shadow(color: .black.opacity(scheme == .dark ? 0 : 0.16), radius: 14, y: 8)
        .sensoryFeedback(.selection, trigger: state.context)
        // The title (a header) names the card: no label here, or VoiceOver
        // says it twice.
        .accessibilityElement(children: .contain)
        #if DEBUG
        .task { await debugAutoPick() }
        #endif
    }

    @ViewBuilder
    private func cardBackground(_ shape: RoundedRectangle) -> some View {
        ZStack {
            sky.surface
            if sky.lit {
                // A little light from the top corner and a few stars:
                // decoration, so none under Increase Contrast or Reduce
                // Transparency.
                RadialGradient(colors: [sky.lumen.opacity(0.16), sky.lumen.opacity(0)],
                               center: .topLeading, startRadius: 0, endRadius: 320)
                NightStarField(count: 26, brightness: 0.55)
            }
        }
        .clipShape(shape)
    }

    // MARK: Header and steps

    private var header: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.xs) {
            HStack(spacing: BrandSpacing.xs) {
                if !large {
                    Image(systemName: "hand.tap")
                        .font(.system(size: eyebrowSize, weight: .bold))
                }
                Text(TokenizerCopy.eyebrow.uppercased())
                    .font(.system(size: eyebrowSize, weight: .heavy, design: .rounded))
                    .tracking(1.2)
            }
            .foregroundStyle(sky.accentText)
            Text(TokenizerCopy.title)
                .font(BrandFont.roundedTitle3)
                .foregroundStyle(sky.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(TokenizerCopy.cardAccessibility)
        .accessibilityAddTraits(.isHeader)
    }

    private func step<Content: View>(_ number: Int, _ title: String,
                                     @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: BrandSpacing.md) {
            Group {
                if large {
                    // No disc at the accessibility sizes: it would squeeze
                    // the title. The number stays, in the line.
                    Text("\(number) \u{00B7} \(title)")
                        .font(BrandFont.roundedHeadline)
                        .foregroundStyle(sky.ink)
                } else {
                    HStack(alignment: .firstTextBaseline, spacing: BrandSpacing.sm + 2) {
                        Text("\(number)")
                            .font(.system(.subheadline, design: .rounded, weight: .bold))
                            .foregroundStyle(sky.accentText)
                            .frame(width: stepDisc, height: stepDisc)
                            .background(sky.lumenWash(0.14), in: Circle())
                            .overlay(Circle().strokeBorder(sky.increasedContrast ? sky.accentText
                                                               : sky.lumenWash(0.45), lineWidth: 1))
                        Text(title)
                            .font(BrandFont.roundedHeadline)
                            .foregroundStyle(sky.ink)
                    }
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(TokenizerCopy.stepAccessibility(number, title))
            .accessibilityAddTraits(.isHeader)
            content()
        }
    }

    // MARK: 1. You type

    /// "I went to the bank", drawn as the student's own turn is on the
    /// iPhone: their bubble, on the trailing side.
    private var typedSentence: some View {
        let shape = UnevenRoundedRectangle(topLeadingRadius: BrandRadius.xl, bottomLeadingRadius: BrandRadius.xl,
                                           bottomTrailingRadius: BrandRadius.sm, topTrailingRadius: BrandRadius.xl,
                                           style: .continuous)
        return Text(TokenizerInteractive.sentence)
            .font(BrandFont.body)
            .foregroundStyle(.white)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.vertical, BrandSpacing.md)
            .padding(.horizontal, BrandSpacing.lg)
            // The student's bubble's hues, a step deeper so white reads at
            // 5.7:1 or better on the night card.
            .background(LinearGradient(colors: [BrandColor.accentDark, BrandColor.mercViolet],
                                       startPoint: .topLeading, endPoint: .bottomTrailing), in: shape)
            .overlay {
                if sky.increasedContrast { shape.strokeBorder(Color.white.opacity(0.6), lineWidth: 1) }
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(TokenizerCopy.typedAccessibility)
    }

    // MARK: 2. Tokens

    private var tokenStep: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.md) {
            // Six apart, so the five tokens make one line on an SE.
            NightFlow(spacing: BrandSpacing.sm - 2, lineSpacing: BrandSpacing.md) {
                ForEach(Array(TokenizerInteractive.tokens.enumerated()), id: \.offset) { _, token in
                    VStack(spacing: BrandSpacing.xs) {
                        TokenChip(token: token, isFollowed: token == TokenizerInteractive.bank, sky: sky)
                        Text(String(token.id))
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(sky.ink3)
                    }
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(TokenizerCopy.tokensAccessibility)
            VStack(alignment: .leading, spacing: BrandSpacing.xs) {
                note(TokenizerCopy.spaceNote)
                note(TokenizerCopy.idNote)
            }
        }
    }

    // MARK: 3. A list of numbers

    private var numbersStep: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.md) {
            Group {
                if large {
                    // The arrow is decoration: the token, then its list.
                    VStack(alignment: .leading, spacing: BrandSpacing.sm) {
                        TokenChip(token: TokenizerInteractive.bank, isFollowed: true, sky: sky)
                        NumberList(count: 5, sky: sky)
                    }
                } else {
                    ViewThatFits(in: .horizontal) {
                        numbersLine(count: 8)
                        numbersLine(count: 5)
                        VStack(alignment: .leading, spacing: BrandSpacing.sm) {
                            HStack(spacing: BrandSpacing.sm) {
                                TokenChip(token: TokenizerInteractive.bank, isFollowed: true, sky: sky)
                                arrow.rotationEffect(.degrees(90))
                            }
                            NumberList(count: 5, sky: sky)
                        }
                    }
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(TokenizerCopy.numbersAccessibility)
            note(TokenizerCopy.listNote)
        }
    }

    private func numbersLine(count: Int) -> some View {
        HStack(spacing: BrandSpacing.sm) {
            TokenChip(token: TokenizerInteractive.bank, isFollowed: true, sky: sky)
            arrow
            NumberList(count: count, sky: sky)
                .fixedSize()
        }
    }

    private var arrow: some View {
        Image(systemName: "arrow.right")
            .font(.system(.footnote, weight: .semibold))
            .foregroundStyle(sky.ink3)
            .accessibilityHidden(true)
    }

    // MARK: 4. The map of meaning

    private var showsMap: Bool {
        TokenizerMapScale.showsMapInline(at: typeSize) || state.showsFoldedMap
    }

    private var mapStep: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.md) {
            Text(TokenizerCopy.startPrompt)
                .font(.callout)
                .foregroundStyle(sky.ink2)
                .accessibilityHidden(true)
            openings
            finishedSentence
                .padding(.top, BrandSpacing.xs)
            if TokenizerMapScale.saysMapInWords(at: typeSize) {
                Text(TokenizerCopy.mapInWords(state.context))
                    .font(.callout)
                    .foregroundStyle(sky.ink2)
                    .fixedSize(horizontal: false, vertical: true)
                    // VoiceOver hears the map's own line (or, folded, this).
                    .accessibilityHidden(showsMap)
            }
            if !TokenizerMapScale.showsMapInline(at: typeSize) {
                foldToggle
            }
            if showsMap {
                MeaningMapFrame(typeSize: typeSize) {
                    MeaningSkyPanel(context: state.context, typeSize: typeSize, sky: sky, reduceMotion: reduceMotion)
                }
                .transition(.opacity)
                Text(TokenizerCopy.sketch)
                    .font(BrandFont.caption)
                    .foregroundStyle(sky.ink3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text(TokenizerCopy.howItMoves)
                .font(.callout)
                .foregroundStyle(sky.ink2)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// The two openings: side by side when they fit, else one under the
    /// other (a long one wraps rather than leaving the card).
    private var openings: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: BrandSpacing.sm) { openingChips }
            VStack(alignment: .leading, spacing: BrandSpacing.sm) { openingChips }
        }
    }

    @ViewBuilder private var openingChips: some View {
        ForEach(TokenizerContext.allCases, id: \.self) { context in
            OpeningChip(context: context, isSelected: state.context == context, sky: sky) { choose(context) }
        }
    }

    /// "… I went to the bank" and, once picked, the context before it.
    private var finishedSentence: some View {
        var opening: AttributedString
        if let context = state.context {
            opening = AttributedString(context.opening + " ")
            opening.foregroundColor = sky.accentText
        } else {
            opening = AttributedString("\u{2026} ")
            opening.foregroundColor = sky.ink3
        }
        var rest = AttributedString(TokenizerInteractive.sentence + (state.context == nil ? "" : "."))
        rest.foregroundColor = sky.ink
        return Text(opening + rest)
            .font(BrandFont.subheading)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityLabel(state.context?.sentence ?? TokenizerInteractive.sentence)
    }

    /// "Show the map" / "Hide the map", at the accessibility sizes.
    private var foldToggle: some View {
        Button {
            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.25)) { state.showsFoldedMap.toggle() }
        } label: {
            // Only ever at the accessibility sizes: the words, no icon.
            Text(state.showsFoldedMap ? TokenizerCopy.hideMap : TokenizerCopy.showMap)
                .font(.system(.callout, design: .rounded, weight: .semibold))
                .fixedSize(horizontal: false, vertical: true)
                .foregroundStyle(sky.accentText)
                .padding(.horizontal, BrandSpacing.lg)
                .padding(.vertical, BrandSpacing.sm)
                .frame(minHeight: 44)
                .background(sky.raised, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .strokeBorder(sky.increasedContrast ? sky.hairline : sky.lumenWash(0.45), lineWidth: 1))
                .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityHint(state.showsFoldedMap ? "" : TokenizerCopy.showMapHint)
    }

    private func choose(_ context: TokenizerContext) {
        guard state.context != context else { return }
        // Reduce Motion: the map crossfades (`MeaningSkyPanel`) instead.
        withAnimation(reduceMotion ? .easeInOut(duration: 0.35) : .smooth(duration: 0.7)) {
            state.context = context
        }
        AccessibilityNotification.Announcement(TokenizerCopy.pickedAnnouncement(context)).post()
    }

    private func note(_ text: String) -> some View {
        Text(text)
            .font(BrandFont.caption)
            .foregroundStyle(sky.ink3)
            .fixedSize(horizontal: false, vertical: true)
    }

    #if DEBUG
    /// `-NightTokenizerAutoPick money|river` (+ `-NightTokenizerAutoPickDelay
    /// <s>`, default 2): pick that opening once, as a tap would, a while
    /// after the card appears (the motion clip; simctl can't tap).
    private func debugAutoPick() async {
        guard !DebugAutoPick.done,
              let raw = UserDefaults.standard.string(forKey: "NightTokenizerAutoPick"),
              let context = TokenizerContext(rawValue: raw) else { return }
        let delay = UserDefaults.standard.double(forKey: "NightTokenizerAutoPickDelay")
        try? await Task.sleep(for: .seconds(delay > 0 ? delay : 2))
        guard !Task.isCancelled, !DebugAutoPick.done else { return }
        DebugAutoPick.done = true
        choose(context)
    }
    #endif
}

#if DEBUG
@MainActor
private enum DebugAutoPick {
    static var done = false
}
#endif

/// The iPhone shots' accessibility overrides, DEBUG only (simctl sets
/// Increase Contrast, not Reduce Motion or Reduce Transparency):
/// `-NightTokenizerReduceMotion YES`, `-NightTokenizerReduceTransparency
/// YES`, `-NightTokenizerIncreaseContrast YES`. The device's own settings
/// always count.
private enum DebugAccessibility {
    #if DEBUG
    static let reduceMotion = UserDefaults.standard.bool(forKey: "NightTokenizerReduceMotion")
    static let reduceTransparency = UserDefaults.standard.bool(forKey: "NightTokenizerReduceTransparency")
    static let increasedContrast = UserDefaults.standard.bool(forKey: "NightTokenizerIncreaseContrast")
    #else
    static let reduceMotion = false
    static let reduceTransparency = false
    static let increasedContrast = false
    #endif
}

// MARK: - Pieces

/// A token as machine text, its leading space drawn as a dot. The token the
/// map follows ("·bank") is lit: white on "bank"'s indigo.
private struct TokenChip: View {
    let token: TokenizerInteractive.Token
    let isFollowed: Bool
    let sky: NightSkyCard

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: BrandRadius.sm + 2, style: .continuous)
        HStack(spacing: 0) {
            if token.leadingSpace {
                Text("\u{00B7}")
                    .foregroundStyle(isFollowed ? Color.white.opacity(0.85) : sky.ink3)
            }
            Text(token.text)
                .foregroundStyle(isFollowed ? Color.white : sky.accentText)
        }
        .font(.system(.callout, design: .monospaced, weight: .medium))
        .padding(.horizontal, BrandSpacing.sm + 1)
        .padding(.vertical, BrandSpacing.xs + 1)
        .background {
            if isFollowed {
                shape.fill(LinearGradient(colors: sky.bankStops, startPoint: .leading, endPoint: .trailing))
            } else {
                shape.fill(sky.lumenWash(0.16))
            }
        }
        .overlay {
            if !isFollowed {
                shape.strokeBorder(sky.increasedContrast ? sky.accentText : sky.lumenWash(0.55), lineWidth: 1)
            } else if sky.increasedContrast {
                shape.strokeBorder(Color.white.opacity(0.9), lineWidth: 1)
            }
        }
        .fixedSize()
    }
}

/// "·bank"'s first numbers, labelled as what they are: a list of numbers,
/// each value under a bar up or down from zero, and thousands more. The
/// cells grow with the text and wrap when they run out of width. At the
/// accessibility sizes the bars (a picture of the signs) go, and the values
/// flow as text.
private struct NumberList: View {
    let count: Int
    let sky: NightSkyCard
    @Environment(\.dynamicTypeSize) private var typeSize
    /// A cell is as wide as its value at the student's text size.
    @ScaledMetric(relativeTo: .caption2) private var cellWidth: CGFloat = 44
    /// The bars' reach from zero: a picture, so it doesn't grow with the text.
    private let half: CGFloat = 14

    var body: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.sm) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: BrandSpacing.md) { label; Spacer(minLength: 0); more }
                VStack(alignment: .leading, spacing: BrandSpacing.xxs) { label; more }
            }
            if typeSize.isAccessibilitySize {
                Text(TokenizerInteractive.bankNumbers.prefix(count).map(TokenizerInteractive.formatted)
                        .joined(separator: ", ") + ", \u{2026}")
                    .font(.system(.caption2, design: .monospaced, weight: .medium))
                    .foregroundStyle(sky.ink2)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                bars
            }
        }
        .padding(.horizontal, BrandSpacing.md - 2)
        .padding(.vertical, BrandSpacing.sm)
        .background(sky.raised, in: RoundedRectangle(cornerRadius: BrandRadius.md + 2, style: .continuous))
        .overlay {
            if sky.increasedContrast {
                RoundedRectangle(cornerRadius: BrandRadius.md + 2, style: .continuous)
                    .strokeBorder(sky.hairline, lineWidth: 1)
            }
        }
    }

    private var bars: some View {
        NightFlow(spacing: 2, lineSpacing: BrandSpacing.sm) {
            ForEach(Array(TokenizerInteractive.bankNumbers.prefix(count).enumerated()), id: \.offset) { _, value in
                cell(value)
            }
            // "…" on the values' line.
            VStack(spacing: BrandSpacing.xs + 1) {
                Color.clear.frame(width: 1, height: half * 2)
                Text("\u{2026}")
                    .font(.system(.caption2, design: .monospaced, weight: .medium))
                    .foregroundStyle(sky.ink3)
            }
            .accessibilityHidden(true)
        }
    }

    private var label: some View {
        Text(TokenizerCopy.listLabel)
            .font(BrandFont.caption)
            .foregroundStyle(sky.ink2)
    }

    private var more: some View {
        Text(TokenizerCopy.listMore)
            .font(BrandFont.caption)
            .foregroundStyle(sky.ink3)
    }

    private func cell(_ value: Double) -> some View {
        let length = max(2, CGFloat(min(abs(value), 0.35) / 0.35) * half)
        let barFill: AnyShapeStyle = sky.increasedContrast
            ? AnyShapeStyle(sky.accentText)
            : AnyShapeStyle(LinearGradient(colors: [sky.accent, sky.violet], startPoint: .leading, endPoint: .trailing))
        return VStack(spacing: BrandSpacing.xs + 1) {
            ZStack {
                // Zero: each bar goes up (positive) or down (negative) from it.
                Rectangle()
                    .fill(sky.increasedContrast ? sky.ink3 : sky.ink3.opacity(0.45))
                    .frame(height: 1)
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(barFill)
                    .frame(width: 10, height: length)
                    .offset(y: value >= 0 ? -length / 2 : length / 2)
            }
            .frame(width: cellWidth, height: half * 2)
            Text(TokenizerInteractive.formatted(value))
                .font(.system(.caption2, design: .monospaced, weight: .medium))
                .foregroundStyle(sky.ink2)
                .lineLimit(1)
                .fixedSize()
        }
        .frame(minWidth: cellWidth)
    }
}

/// A way the student can start the sentence: 44 pt or taller, indigo with a
/// check once picked. Its words wrap rather than leave the card.
private struct OpeningChip: View {
    let context: TokenizerContext
    let isSelected: Bool
    let sky: NightSkyCard
    let onChoose: () -> Void
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 22, style: .continuous)
        // At the accessibility sizes the check sits over the words, which
        // get the whole width (beside them it broke "paycheck," apart).
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: BrandSpacing.xxs))
            : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: BrandSpacing.xs + 2))
        Button(action: onChoose) {
            layout {
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(.footnote, weight: .bold))
                        .accessibilityHidden(true)
                }
                Text(context.chipTitle)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .font(.system(.callout, design: .rounded, weight: .semibold))
            .foregroundStyle(isSelected ? Color.white : sky.ink)
            .padding(.horizontal, BrandSpacing.lg)
            .padding(.vertical, BrandSpacing.sm + 2)
            .frame(minHeight: 44)
            .background(isSelected ? sky.prominent : sky.raised, in: shape)
            .overlay {
                if isSelected {
                    if sky.increasedContrast { shape.strokeBorder(Color.white.opacity(0.9), lineWidth: 1) }
                } else {
                    shape.strokeBorder(sky.increasedContrast ? sky.hairline : sky.ink3.opacity(0.5), lineWidth: 1)
                }
            }
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(TokenizerCopy.chipAccessibility(context))
        .accessibilityHint(TokenizerCopy.chipHint)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

// MARK: - The map of meaning

/// The map's panel: as wide as it is offered, as tall as `MeaningMap` says
/// for that width at the labels' size, worked out in one layout pass.
private struct MeaningMapFrame: Layout {
    let typeSize: DynamicTypeSize

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 343
        let scale = TokenizerMapScale.labelScale(for: typeSize, panelWidth: width)
        return CGSize(width: width, height: MeaningMap.height(forWidth: width, scale: scale))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for subview in subviews {
            subview.place(at: bounds.origin, proposal: ProposedViewSize(bounds.size))
        }
    }
}

/// The meaning sky on the iPhone: four words in two neighbourhoods,
/// "bank"'s starting ring between them, and "bank" itself with lines to the
/// words it lands near. Positions and label frames are `MeaningMap`'s, at
/// the labels' size for this text size and width (`TokenizerMapScale`). Moving "bank" animates its
/// place and its lines; under Reduce Motion the moved state crossfades in.
private struct MeaningSkyPanel: View {
    let context: TokenizerContext?
    let typeSize: DynamicTypeSize
    let sky: NightSkyCard
    let reduceMotion: Bool

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: BrandRadius.lg, style: .continuous)
        GeometryReader { geo in
            let size = geo.size
            let scale = TokenizerMapScale.labelScale(for: typeSize, panelWidth: size.width)
            ZStack(alignment: .topLeading) {
                skyFill
                constellations(size)
                startRing(size)
                if reduceMotion {
                    moving(size, scale: scale)
                        .id(context)
                        .transition(.opacity)
                } else {
                    moving(size, scale: scale)
                }
                words(size, scale: scale)
                if reduceMotion {
                    bankMark(size, scale: scale)
                        .id(context)
                        .transition(.opacity)
                } else {
                    bankMark(size, scale: scale)
                }
            }
            .frame(width: size.width, height: size.height)
        }
        .clipShape(shape)
        .overlay(shape.strokeBorder(Color.white.opacity(sky.increasedContrast ? 0.55 : 0.14), lineWidth: 1))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(TokenizerCopy.mapSummary(context))
        .accessibilityAddTraits(.isImage)
    }

    @ViewBuilder private var skyFill: some View {
        if sky.increasedContrast {
            sky.skyTop
        } else {
            LinearGradient(colors: [sky.skyTop, sky.skyBottom], startPoint: .top, endPoint: .bottom)
            NightStarField(count: 48, brightness: 0.9)
        }
    }

    private func font(_ points: CGFloat, scale: CGFloat) -> Font {
        .system(size: points * scale, weight: .medium, design: .monospaced)
    }

    /// The start's caption, in the reading face (Lexend), as on the Mac.
    private func captionFont(scale: CGFloat) -> Font {
        let size = MeaningMap.captionPointSize * scale
        switch BrandFont.readingFace {
        case .custom(let name): return .custom(name, fixedSize: size)
        case .system(let design): return .system(size: size, design: design)
        }
    }

    /// Each neighbourhood: its glow (lit only) and the line between its two
    /// words.
    private func constellations(_ size: CGSize) -> some View {
        ZStack(alignment: .topLeading) {
            ForEach(TokenizerContext.allCases, id: \.self) { group in
                let points = MeaningMap.words.filter { $0.group == group }
                    .map { MeaningMap.scaled($0.point, in: size) }
                let lit = context == group
                let glow = sky.glowAlpha(lit: lit)
                if glow > 0 {
                    let centre = CGPoint(x: points.map(\.x).reduce(0, +) / CGFloat(points.count),
                                         y: points.map(\.y).reduce(0, +) / CGFloat(points.count))
                    let radius = min(size.width, size.height) * 0.55
                    let hue = group == .money ? sky.accent : sky.violet
                    Circle()
                        .fill(RadialGradient(colors: [hue.opacity(glow), hue.opacity(0)],
                                             center: .center, startRadius: 0, endRadius: radius))
                        .frame(width: radius * 2, height: radius * 2)
                        .position(centre)
                }
                Path { path in
                    path.move(to: points[0])
                    path.addLine(to: points[1])
                }
                .stroke(sky.increasedContrast ? sky.skyInk2 : Color.white.opacity(lit ? 0.5 : 0.24),
                        style: StrokeStyle(lineWidth: 1, dash: sky.increasedContrast ? [] : [3, 4]))
            }
        }
    }

    /// Where "bank"'s first numbers put it: the same for every opening.
    private func startRing(_ size: CGSize) -> some View {
        let p = MeaningMap.scaled(MeaningMap.start, in: size)
        let r = MeaningMap.startRingRadius
        return Circle()
            .strokeBorder(sky.increasedContrast ? sky.skyInk2 : Color.white.opacity(0.5),
                          style: StrokeStyle(lineWidth: 1.2, dash: [3, 3]))
            .frame(width: r * 2, height: r * 2)
            .position(p)
    }

    /// What moves with the opening: the trail from the start and the lines
    /// to the neighbours; and the start's caption (shown in every state).
    private func moving(_ size: CGSize, scale: CGFloat) -> some View {
        let bankPoint = MeaningMap.scaled(MeaningMap.bank(context), in: size)
        let start = MeaningMap.scaled(MeaningMap.start, in: size)
        let caption = MeaningMap.startCaptionFrame(in: size, scale: scale)
        return ZStack(alignment: .topLeading) {
            MeaningMapLines(from: bankPoint, to: [start])
                .stroke(sky.skyLink.opacity(context == nil ? 0 : 0.7),
                        style: StrokeStyle(lineWidth: 1.2, lineCap: .round, dash: [2, 4]))
            ForEach(TokenizerContext.allCases, id: \.self) { group in
                let neighbours = MeaningMap.words.filter { $0.group == group }
                    .map { MeaningMap.scaled($0.point, in: size) }
                MeaningMapLines(from: bankPoint, to: neighbours)
                    .stroke(sky.skyLink, style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
                    .shadow(color: sky.lit ? sky.lumen.opacity(0.8) : .clear, radius: 4)
                    .opacity(context == group ? 1 : 0)
            }
            Text(MeaningMap.startCaption)
                .font(captionFont(scale: scale))
                .foregroundStyle(sky.skyInk2)
                .fixedSize()
                .position(x: caption.midX, y: caption.midY)
        }
    }

    private func words(_ size: CGSize, scale: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            ForEach(MeaningMap.words, id: \.text) { word in
                let lit = context == word.group
                let p = MeaningMap.scaled(word.point, in: size)
                let label = MeaningMap.labelFrame(word, in: size, scale: scale)
                Circle()
                    .fill(Color.white)
                    .frame(width: lit ? 9 : 6, height: lit ? 9 : 6)
                    .shadow(color: sky.lit ? .white.opacity(lit ? 0.9 : 0.4) : .clear, radius: lit ? 6 : 3)
                    .position(p)
                Text(word.text)
                    .font(font(MeaningMap.wordPointSize, scale: scale))
                    .foregroundStyle(lit ? sky.skyInk : sky.skyInk2)
                    .fixedSize()
                    .position(x: label.midX, y: label.midY)
            }
        }
    }

    /// "bank": a glow, a white dot and its pill.
    private func bankMark(_ size: CGSize, scale: CGFloat) -> some View {
        let p = MeaningMap.scaled(MeaningMap.bank(context), in: size)
        let pill = MeaningMap.pillFrame(context, in: size, scale: scale)
        return ZStack(alignment: .topLeading) {
            if sky.lit {
                Circle()
                    .fill(RadialGradient(colors: [sky.skyLink.opacity(0.75), sky.skyLink.opacity(0)],
                                         center: .center, startRadius: 0, endRadius: 24))
                    .frame(width: 48, height: 48)
                    .position(p)
            }
            Circle()
                .fill(Color.white)
                .frame(width: 12, height: 12)
                .position(p)
            Text("bank")
                .font(font(MeaningMap.pillPointSize, scale: scale))
                .foregroundStyle(.white)
                .padding(.horizontal, 10 * scale)
                .padding(.vertical, 3 * scale)
                .background(LinearGradient(colors: sky.bankStops, startPoint: .leading, endPoint: .trailing),
                            in: Capsule())
                .overlay(Capsule().strokeBorder(Color.white.opacity(sky.increasedContrast ? 0.9 : 0.25), lineWidth: 1))
                .fixedSize()
                .position(x: pill.midX, y: pill.midY)
        }
    }
}
#endif
