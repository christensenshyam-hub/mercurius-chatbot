#if os(macOS)
import SwiftUI
import DesignSystem

/// Lesson 1.1's interactive, "How a model reads “bank”", as a lit card in
/// the lesson's reading column (`NightInteractiveAnchor` says where). Four
/// steps: the sentence the student types, its tokens with illustrative IDs,
/// "·bank"'s list of numbers, and the map of meaning, where starting the
/// sentence with some context moves "bank" toward its neighbours.
///
/// It is the lesson's own picture, drawn on the Mac: nothing is sent,
/// stored or tokenised. The opening the student picks lives in the lesson's
/// `NightTokenizerState`, so a reply's re-render never resets it.
///
/// - Keyboard: Tab reaches each opening (and "Try it"); Space or Return
///   picks it. While an opening has focus from the keyboard, Return is its
///   own, not the lesson's check's; A–D and the arrows still answer the
///   check, and a pick there takes the keys back. A click picks an opening
///   without keeping the keyboard, so the check's keys keep working.
/// - VoiceOver: each step is a header with a spoken summary; the map reads
///   as one sentence ("bank is near loan and deposit"), and a pick says the
///   finished sentence and where "bank" went.
/// - Reduce Motion: "bank" crossfades to its new place instead of moving.
/// - Increase Contrast: no glows or stars, solid edges, the HC tokens.
/// - Narrower than 440 pt (a 700 pt window with the sidebar open) it starts
///   as a compact "Try it" card that opens in place: VoiceOver moves to the
///   card's title, and the keyboard (when it opened it) to the first
///   opening.
struct NightInteractiveCard: View {
    static let scrollID = "night-interactive"
    static let mapScrollID = "night-interactive-map"

    @Environment(NightTokenizerState.self) private var shared: NightTokenizerState?
    @Environment(\.nightCheckRouter) private var router
    @NightSettings private var night
    @State private var local = NightTokenizerState()
    @State private var width: CGFloat = 0
    @State private var keyHolder = UUID()
    @State private var tryItKeyHolder = UUID()
    @FocusState private var focusedOpening: NightTokenizerContext?
    @FocusState private var tryItFocused: Bool
    @AccessibilityFocusState private var titleHasVoiceOver: Bool
    /// "Try it" was pressed: where focus goes once the full card is there.
    @State private var focusOnOpen: (voiceOver: Bool, keyboard: Bool) = (false, false)

    private var state: NightTokenizerState { shared ?? local }

    private var compact: Bool {
        NightTokenizerLayout.isCompact(width: width, expanded: state.expanded,
                                       forced: NightTokenizerLayout.debugForcesCompact)
    }

    var body: some View {
        Group {
            if compact {
                compactCard
            } else {
                fullCard
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .nightLit(radius: Night.Radius.card)
        .onGeometryChange(for: CGFloat.self) { geo in
            geo.size.width
        } action: { newWidth in
            width = newWidth
        }
        // An opening with the keyboard keeps Return: the lesson's waiting
        // check doesn't lock in from it meanwhile.
        .onChange(of: focusedOpening) { _, opening in router?.hold(keyHolder, opening != nil) }
        .onChange(of: tryItFocused) { _, focused in router?.hold(tryItKeyHolder, focused) }
        // The check got a pick (a letter, an arrow or a click): it has the
        // student's attention, so the opening lets go of the keyboard.
        .onChange(of: router?.checkPicks) { _, _ in
            if focusedOpening != nil { focusedOpening = nil }
            if tryItFocused { tryItFocused = false }
        }
        .onDisappear {
            router?.hold(keyHolder, false)
            router?.hold(tryItKeyHolder, false)
        }
        // The title (a header) names the card: no label here, or VoiceOver
        // says it twice.
        .accessibilityElement(children: .contain)
    }

    // MARK: The compact card

    private var compactCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            Text(NightTypography.curlQuotes(NightTokenizerCopy.compactLine))
                .nightFont(.callout)
                .foregroundStyle(Night.ink2)
                .fixedSize(horizontal: false, vertical: true)
            // A lit capsule, not glass: glass chrome floats over the
            // canvas; this sits inside a card. In the Tab loop whatever the
            // Full Keyboard Access setting, like the openings.
            NightTryItControl(focus: $tryItFocused) { open(fromKeyboard: $0) }
        }
        .padding(Night.Space.card)
    }

    /// Opens the compact card in place. The control that was pressed goes,
    /// so VoiceOver moves to the card's title and, when the keyboard opened
    /// it, the keyboard moves to the first opening (a click shows no ring).
    private func open(fromKeyboard: Bool) {
        focusOnOpen = (true, fromKeyboard)
        // "Try it" goes: it lets go of the keyboard (and of Return) first.
        if tryItFocused { tryItFocused = false }
        router?.hold(tryItKeyHolder, false)
        withAnimation(night.animation(Night.Motion.layout)) { state.expanded = true }
    }

    /// The full card is on screen after "Try it": move focus into it.
    private func focusAfterOpening() {
        guard focusOnOpen.voiceOver else { return }
        let keyboard = focusOnOpen.keyboard
        focusOnOpen = (false, false)
        DispatchQueue.main.async {
            titleHasVoiceOver = true
            if keyboard { focusedOpening = NightTokenizerContext.allCases.first }
        }
    }

    // MARK: The card

    private var fullCard: some View {
        VStack(alignment: .leading, spacing: 22) {
            header
            step(1, NightTokenizerCopy.step1) { typedLine }
            step(2, NightTokenizerCopy.step2) { tokenStep }
            step(3, NightTokenizerCopy.step3) { numbersStep }
            step(4, NightTokenizerCopy.step4) { mapStep }
                .id(Self.mapScrollID)
        }
        .padding(Night.Space.card)
        .onAppear(perform: focusAfterOpening)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            NightEyebrow(NightTokenizerCopy.eyebrow, systemImage: "hand.tap")
            Text(NightTokenizerCopy.title)
                .nightFont(.title2)
                .foregroundStyle(Night.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(NightTokenizerCopy.cardAccessibility)
        .accessibilityAddTraits(.isHeader)
        .accessibilityFocused($titleHasVoiceOver)
    }

    private func step<Content: View>(_ number: Int, _ title: String,
                                     @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Text("\(number)")
                    .font(NightType.lexend(13, semibold: true))
                    .foregroundStyle(Night.accentText)
                    .frame(width: 26, height: 26)
                    .background(Night.lumen.opacity(Night.Tint.well), in: Circle())
                    .overlay(Circle().strokeBorder(night.increasedContrast ? Night.accentText : Night.lumen.opacity(0.45),
                                                   lineWidth: 1))
                Text(title)
                    .nightFont(.headline)
                    .foregroundStyle(Night.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(NightTokenizerCopy.stepAccessibility(number, title))
            .accessibilityAddTraits(.isHeader)
            content()
        }
    }

    // MARK: 1. You type

    private var typedLine: some View {
        NightTypedSentence()
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(NightTokenizerCopy.typedAccessibility)
    }

    // MARK: 2. Tokens

    private var tokenStep: some View {
        VStack(alignment: .leading, spacing: 10) {
            NightFlow(spacing: 8, lineSpacing: 10) {
                ForEach(Array(NightTokenizer.tokens.enumerated()), id: \.offset) { _, token in
                    VStack(spacing: 5) {
                        NightTokenizerChip(token: token, isFollowed: token == NightTokenizer.bank)
                        Text(String(token.id))
                            .font(NightType.lexend(12))
                            .monospacedDigit()
                            .foregroundStyle(Night.ink3)
                    }
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(NightTokenizerCopy.tokensAccessibility)
            VStack(alignment: .leading, spacing: 3) {
                note(NightTokenizerCopy.spaceNote)
                note(NightTokenizerCopy.idNote)
            }
        }
    }

    // MARK: 3. A list of numbers

    private var numbersStep: some View {
        VStack(alignment: .leading, spacing: 10) {
            ViewThatFits(in: .horizontal) {
                numbersLine(count: 8)
                numbersLine(count: 5)
                VStack(alignment: .leading, spacing: 8) {
                    NightTokenizerChip(token: NightTokenizer.bank, isFollowed: true)
                    NightNumberList(count: 5)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(NightTokenizerCopy.numbersAccessibility)
            note(NightTokenizerCopy.listNote)
        }
    }

    private func numbersLine(count: Int) -> some View {
        HStack(spacing: 10) {
            NightTokenizerChip(token: NightTokenizer.bank, isFollowed: true)
            Image(systemName: "arrow.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Night.ink3)
                .accessibilityHidden(true)
            NightNumberList(count: count)
        }
    }

    // MARK: 4. The map of meaning

    private var mapStep: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(NightTokenizerCopy.startPrompt)
                .nightFont(.callout)
                .foregroundStyle(Night.ink2)
                .accessibilityHidden(true)
            NightFlow(spacing: 8, lineSpacing: 8) {
                ForEach(NightTokenizerContext.allCases, id: \.self) { context in
                    NightOpeningChip(context: context, isSelected: state.context == context,
                                     focus: $focusedOpening) { choose(context) }
                }
            }
            NightFinishedSentence(context: state.context)
                .padding(.top, 4)
            NightMeaningSkyView(context: state.context)
                .frame(height: NightMeaningMap.height(forWidth: max(width - 2 * Night.Space.card, 0)))
            Text(NightTokenizerCopy.sketch)
                .nightFont(.caption)
                .foregroundStyle(Night.ink3)
                .fixedSize(horizontal: false, vertical: true)
            Text(NightTokenizerCopy.howItMoves)
                .nightFont(.callout)
                .foregroundStyle(Night.ink2)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func choose(_ context: NightTokenizerContext) {
        guard state.context != context else { return }
        withAnimation(night.animation(.smooth(duration: 0.7))) { state.context = context }
        AccessibilityNotification.Announcement(NightTokenizerCopy.pickedAnnouncement(context)).post()
    }

    private func note(_ text: String) -> some View {
        Text(text)
            .nightFont(.caption)
            .foregroundStyle(Night.ink3)
            .fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: - Pieces

/// "I went to the bank", as the student's own turn is drawn: the tinted
/// card of what they typed.
private struct NightTypedSentence: View {
    @Environment(\.colorScheme) private var scheme
    @NightSettings private var night

    var body: some View {
        let dark = scheme == .dark
        let shape = UnevenRoundedRectangle(topLeadingRadius: 14, bottomLeadingRadius: 14,
                                           bottomTrailingRadius: 4, topTrailingRadius: 14, style: .continuous)
        Text(NightTokenizer.sentence)
            .nightFont(.body)
            .foregroundStyle(Night.ink)
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(Night.accent.opacity(Night.Tint.student(dark: dark)), in: shape)
            .overlay(shape.strokeBorder(night.increasedContrast ? Night.hairline
                                            : Night.lumen.opacity(Night.Tint.studentEdge(dark: dark)),
                                        lineWidth: 1))
    }
}

/// A token as machine text, its leading space drawn as a dot. The token
/// the map follows ("·bank") is lit: white on the hero's indigo.
struct NightTokenizerChip: View {
    let token: NightTokenizer.Token
    let isFollowed: Bool
    @Environment(\.colorScheme) private var scheme
    @NightSettings private var night

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Night.Radius.chip, style: .continuous)
        HStack(spacing: 0) {
            if token.leadingSpace {
                Text("\u{00B7}")
                    .foregroundStyle(isFollowed ? Color.white.opacity(0.85) : Night.ink3)
            }
            Text(token.text)
                .foregroundStyle(isFollowed ? Color.white : Night.accentText)
        }
        .nightFont(.machine)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background {
            if isFollowed {
                shape.fill(LinearGradient(colors: NightSky.bankStops, startPoint: .leading, endPoint: .trailing))
            } else {
                shape.fill(Night.lumen.opacity(scheme == .dark ? 0.16 : 0.12))
            }
        }
        .overlay {
            if !isFollowed {
                shape.strokeBorder(night.increasedContrast ? Night.accentText : Night.lumen.opacity(0.55), lineWidth: 1)
            }
        }
        .fixedSize()
    }
}

/// "·bank"'s first numbers, labelled as what they are: a list of numbers
/// (each with its value, a bar up or down from zero), and thousands more.
private struct NightNumberList: View {
    let count: Int
    @NightSettings private var night

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 12) {
                Text(NightTokenizerCopy.listLabel)
                    .nightFont(.caption)
                    .foregroundStyle(Night.ink2)
                Spacer(minLength: 0)
                Text(NightTokenizerCopy.listMore)
                    .nightFont(.caption)
                    .foregroundStyle(Night.ink3)
            }
            HStack(alignment: .bottom, spacing: 2) {
                ForEach(Array(NightTokenizer.bankNumbers.prefix(count).enumerated()), id: \.offset) { _, value in
                    cell(value)
                }
                Text("\u{2026}")
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundStyle(Night.ink3)
                    .padding(.bottom, 1)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Night.surfaceRaised, in: RoundedRectangle(cornerRadius: Night.Radius.row, style: .continuous))
        .overlay {
            if night.increasedContrast {
                RoundedRectangle(cornerRadius: Night.Radius.row, style: .continuous)
                    .strokeBorder(Night.hairline, lineWidth: 1)
            }
        }
        .fixedSize()
    }

    private func cell(_ value: Double) -> some View {
        let half: CGFloat = 14
        let length = max(2, CGFloat(min(abs(value), 0.35) / 0.35) * half)
        return VStack(spacing: 5) {
            ZStack {
                // Zero: each bar goes up (positive) or down (negative) from it.
                Rectangle()
                    .fill(night.increasedContrast ? Night.ink3 : Night.ink3.opacity(0.45))
                    .frame(height: 1)
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(Night.progressLight(increasedContrast: night.increasedContrast))
                    .frame(width: 10, height: length)
                    .offset(y: value >= 0 ? -length / 2 : length / 2)
            }
            .frame(width: 44, height: half * 2)
            Text(NightTokenizer.formatted(value))
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundStyle(Night.ink2)
                .lineLimit(1)
                .fixedSize()
        }
        .frame(width: 44)
    }
}

/// "I went to the bank" and, once picked, the context before it.
private struct NightFinishedSentence: View {
    let context: NightTokenizerContext?

    var body: some View {
        Text(attributed)
            .nightFont(.headline)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityLabel(context?.sentence ?? NightTokenizer.sentence)
    }

    private var attributed: AttributedString {
        var opening: AttributedString
        if let context {
            opening = AttributedString(context.opening + " ")
            opening.foregroundColor = Night.accentText
        } else {
            opening = AttributedString("\u{2026} ")
            opening.foregroundColor = Night.ink3
        }
        var rest = AttributedString(NightTokenizer.sentence + (context == nil ? "" : "."))
        rest.foregroundColor = Night.ink
        return opening + rest
    }
}

/// A way the student can start the sentence: a capsule, `prominent`
/// with a check once picked. In the Tab loop whatever the Full Keyboard
/// Access setting (as the lesson's check is); Space or Return picks it.
private struct NightOpeningChip: View {
    let context: NightTokenizerContext
    let isSelected: Bool
    var focus: FocusState<NightTokenizerContext?>.Binding
    let onChoose: () -> Void
    @NightSettings private var night
    @State private var hovering = false

    var body: some View {
        let shape = Capsule()
        HStack(spacing: 6) {
            if isSelected {
                Image(systemName: "checkmark")
                    .font(.system(size: 11, weight: .bold))
                    .accessibilityHidden(true)
            }
            Text(context.chipTitle)
        }
        .nightFont(.calloutStrong)
        .foregroundStyle(isSelected ? Color.white : Night.ink)
        .padding(.horizontal, 14)
        .frame(minHeight: 36)
        .background {
            shape.fill(isSelected ? Night.prominent : Night.surfaceRaised)
            if !isSelected && hovering {
                shape.fill(Night.lumen.opacity(Night.Tint.hover))
            }
        }
        .overlay {
            if !isSelected {
                shape.strokeBorder(night.increasedContrast ? Night.hairline : Night.ink3.opacity(0.5), lineWidth: 1)
            }
        }
        .contentShape(shape)
        .onHover { hovering = $0 }
        .onTapGesture {
            onChoose()
            // A click picks without keeping the keyboard (a click focuses an
            // `.edit` view): the check's A–D and Return keep working.
            if focus.wrappedValue != nil { focus.wrappedValue = nil }
        }
        .focusable(true, interactions: .edit)
        .focused(focus, equals: context)
        .focusEffectDisabled()
        .overlay {
            if focus.wrappedValue == context {
                shape.inset(by: -3 - night.focusRingWidth / 2)
                    .stroke(Night.focusRing, lineWidth: night.focusRingWidth)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }
        .onKeyPress(keys: [.space, .return], phases: .down) { _ in
            onChoose()
            return .handled
        }
        .help(NightTokenizerCopy.chipHelp(context))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(NightTokenizerCopy.chipAccessibility(context))
        .accessibilityHint(NightTokenizerCopy.chipHint)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        .accessibilityAction { onChoose() }
    }
}

/// "Try it": a capsule inside a lit card (`surfaceRaised` with an `ink3`
/// edge, solid under Increase Contrast; an `accentText` label; Night's
/// hover). In the Tab loop whatever the Full Keyboard Access setting, as
/// the openings are, with Night's ring; Space or Return opens the card.
private struct NightTryItControl: View {
    var focus: FocusState<Bool>.Binding
    /// `true`: opened from the keyboard.
    let onOpen: (Bool) -> Void
    @NightSettings private var night
    @State private var hovering = false

    var body: some View {
        let shape = Capsule()
        Label(NightTokenizerCopy.tryIt, systemImage: "hand.tap")
            .nightFont(.headline)
            .foregroundStyle(Night.accentText)
            .padding(.horizontal, 16)
            .frame(minHeight: 36)
            .background {
                shape.fill(Night.surfaceRaised)
                shape.fill(Night.lumen.opacity(hovering ? Night.Tint.hover : 0))
            }
            .overlay(shape.strokeBorder(night.increasedContrast ? Night.hairline : Night.ink3.opacity(0.5), lineWidth: 1))
            .contentShape(shape)
            .onHover { hovering = $0 }
            .onTapGesture { onOpen(false) }
            .focusable(true, interactions: .edit)
            .focused(focus)
            .focusEffectDisabled()
            .overlay {
                if focus.wrappedValue {
                    shape.inset(by: -3 - night.focusRingWidth / 2)
                        .stroke(Night.focusRing, lineWidth: night.focusRingWidth)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
            }
            .onKeyPress(keys: [.space, .return], phases: .down) { _ in
                onOpen(true)
                return .handled
            }
            .help(NightTokenizerCopy.tryItHint)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(NightTokenizerCopy.tryIt)
            .accessibilityHint(NightTokenizerCopy.tryItHint)
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { onOpen(false) }
    }
}

// MARK: - The map of meaning

/// The meaning sky: night in both appearances, four words in two
/// neighbourhoods, "bank"'s starting ring between them, and "bank" itself
/// with lines to the words it lands near. Positions are
/// `NightMeaningMap`'s. Moving "bank" animates its place and its lines;
/// under Reduce Motion the moved state crossfades in instead.
struct NightMeaningSkyView: View {
    let context: NightTokenizerContext?
    @NightSettings private var night

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)
        GeometryReader { geo in
            let size = geo.size
            ZStack(alignment: .topLeading) {
                sky
                constellations(size)
                startRing(size)
                if night.reduceMotion {
                    moving(size)
                        .id(context)
                        .transition(.opacity)
                } else {
                    moving(size)
                }
                words(size)
                bank(size)
            }
            .frame(width: size.width, height: size.height)
        }
        .clipShape(shape)
        .overlay(shape.strokeBorder(Color.white.opacity(night.increasedContrast ? 0.55 : 0.14), lineWidth: 1))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(NightTokenizerCopy.mapSummary(context))
        .accessibilityAddTraits(.isImage)
    }

    @ViewBuilder private var sky: some View {
        if night.increasedContrast {
            NightSky.top
        } else {
            LinearGradient(colors: [NightSky.top, NightSky.bottom], startPoint: .top, endPoint: .bottom)
            NightStarField(count: 60, brightness: 0.9)
        }
    }

    /// Each neighbourhood: its glow (not under Increase Contrast) and the
    /// line between its two words.
    private func constellations(_ size: CGSize) -> some View {
        ZStack(alignment: .topLeading) {
            ForEach(NightTokenizerContext.allCases, id: \.self) { group in
                let points = NightMeaningMap.words.filter { $0.group == group }
                    .map { NightMeaningMap.scaled($0.point, in: size) }
                let lit = context == group
                if !night.increasedContrast {
                    let centre = CGPoint(x: points.map(\.x).reduce(0, +) / CGFloat(points.count),
                                         y: points.map(\.y).reduce(0, +) / CGFloat(points.count))
                    let radius = min(size.width, size.height) * 0.55
                    Circle()
                        .fill(RadialGradient(colors: [(group == .money ? Night.accent : Night.violet)
                                                        .opacity(NightSky.glowAlpha(lit: lit, increasedContrast: false)),
                                                      (group == .money ? Night.accent : Night.violet).opacity(0)],
                                             center: .center, startRadius: 0, endRadius: radius))
                        .frame(width: radius * 2, height: radius * 2)
                        .position(centre)
                }
                Path { path in
                    path.move(to: points[0])
                    path.addLine(to: points[1])
                }
                .stroke(night.increasedContrast ? NightSky.ink2 : Color.white.opacity(lit ? 0.5 : 0.24),
                        style: StrokeStyle(lineWidth: 1, dash: night.increasedContrast ? [] : [3, 4]))
            }
        }
    }

    /// Where "bank"'s first numbers put it: the same for every opening.
    private func startRing(_ size: CGSize) -> some View {
        let p = NightMeaningMap.scaled(NightMeaningMap.start, in: size)
        let r = NightMeaningMap.startRingRadius
        return Circle()
            .strokeBorder(night.increasedContrast ? NightSky.ink2 : Color.white.opacity(0.5),
                          style: StrokeStyle(lineWidth: 1.2, dash: [3, 3]))
            .frame(width: r * 2, height: r * 2)
            .position(p)
    }

    /// What moves with the opening: the trail from the start and the lines
    /// to the neighbours; and the start's caption (shown in every state).
    private func moving(_ size: CGSize) -> some View {
        let bankPoint = NightMeaningMap.scaled(NightMeaningMap.bank(context), in: size)
        let start = NightMeaningMap.scaled(NightMeaningMap.start, in: size)
        let caption = NightMeaningMap.startCaptionFrame(in: size)
        return ZStack(alignment: .topLeading) {
            NightLinkLines(from: bankPoint, to: [start])
                .stroke(NightSky.link.opacity(context == nil ? 0 : 0.7),
                        style: StrokeStyle(lineWidth: 1.2, lineCap: .round, dash: [2, 4]))
            ForEach(NightTokenizerContext.allCases, id: \.self) { group in
                let neighbours = NightMeaningMap.words.filter { $0.group == group }
                    .map { NightMeaningMap.scaled($0.point, in: size) }
                NightLinkLines(from: bankPoint, to: neighbours)
                    .stroke(NightSky.link, style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
                    .shadow(color: night.increasedContrast ? .clear : Night.lumen.opacity(0.8), radius: 4)
                    .opacity(context == group ? 1 : 0)
            }
            Text(NightMeaningMap.startCaption)
                .font(NightType.lexend(12))
                .foregroundStyle(NightSky.ink2)
                .fixedSize()
                .position(x: caption.midX, y: caption.midY)
        }
    }

    private func words(_ size: CGSize) -> some View {
        ZStack(alignment: .topLeading) {
            ForEach(NightMeaningMap.words, id: \.text) { word in
                let lit = context == word.group
                let p = NightMeaningMap.scaled(word.point, in: size)
                let label = NightMeaningMap.labelFrame(word, in: size)
                Circle()
                    .fill(Color.white)
                    .frame(width: lit ? 9 : 6, height: lit ? 9 : 6)
                    .shadow(color: night.increasedContrast ? .clear : .white.opacity(lit ? 0.9 : 0.4),
                            radius: lit ? 6 : 3)
                    .position(p)
                Text(word.text)
                    .font(.system(size: 13, weight: .medium, design: .monospaced))
                    .foregroundStyle(lit ? NightSky.ink : NightSky.ink2)
                    .fixedSize()
                    .position(x: label.midX, y: label.midY)
            }
        }
    }

    /// "bank": a glow, a white dot and its pill. Under Reduce Motion the
    /// whole of it crossfades to its new place.
    @ViewBuilder
    private func bank(_ size: CGSize) -> some View {
        if night.reduceMotion {
            bankMark(size)
                .id(context)
                .transition(.opacity)
        } else {
            bankMark(size)
        }
    }

    private func bankMark(_ size: CGSize) -> some View {
        let p = NightMeaningMap.scaled(NightMeaningMap.bank(context), in: size)
        let pill = NightMeaningMap.pillFrame(context, in: size)
        return ZStack(alignment: .topLeading) {
            if !night.increasedContrast {
                Circle()
                    .fill(RadialGradient(colors: [NightSky.link.opacity(0.75), NightSky.link.opacity(0)],
                                         center: .center, startRadius: 0, endRadius: 24))
                    .frame(width: 48, height: 48)
                    .position(p)
            }
            Circle()
                .fill(Color.white)
                .frame(width: 12, height: 12)
                .position(p)
            Text("bank")
                .font(.system(size: 14, weight: .medium, design: .monospaced))
                .foregroundStyle(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 3)
                .background(LinearGradient(colors: NightSky.bankStops, startPoint: .leading, endPoint: .trailing),
                            in: Capsule())
                .overlay(Capsule().strokeBorder(Color.white.opacity(night.increasedContrast ? 0.9 : 0.25), lineWidth: 1))
                .fixedSize()
                .position(x: pill.midX, y: pill.midY)
        }
    }
}

/// Lines from one moving point to fixed ones. Only `from` animates, so the
/// lines stay attached while "bank" glides.
struct NightLinkLines: Shape {
    var from: CGPoint
    var to: [CGPoint]

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(from.x, from.y) }
        set { from = CGPoint(x: newValue.first, y: newValue.second) }
    }

    func path(in rect: CGRect) -> Path {
        var path = Path()
        for point in to {
            path.move(to: from)
            path.addLine(to: point)
        }
        return path
    }
}
#endif
