import SwiftUI
import DesignSystem

/// The Citation That Wasn't inside its shell, on both platforms: the hook
/// (the student's question and the example reply), the walk through the
/// five slots, the five drawn pieces, the step question, the reveal,
/// "Write it again" and the takeaway. The platforms differ in the reply
/// (the iPhone's dashed well, the Mac's night sky that glows once when the
/// reference is finished) and the candidates (rows on the iPhone, columns
/// on a wide Mac card) and in keys (the Mac's).
///
/// - Predict first: each slot's tap is a guess before the model's draw;
///   the step question is locked before the reveal; "Write it again" waits
///   for the reveal.
/// - Nothing plays by itself: the next slot, the reveal and the second
///   reference each wait for a tap (DEBUG's `-CitationAutoplay` aside).
/// - Reduce Motion: pieces crossfade in; the second reference is written all
///   at once; the Mac's glow doesn't pulse.
/// - VoiceOver: the steps are headers; each candidate says its slot, its
///   chance (illustrative) and "1 of 3"; what the student caused is
///   announced (the draw, the finished reference, the reveal, the rewrite).
struct CitationCardBody: View {
    let state: CitationState

    @Environment(\.interactiveTheme) private var theme
    @Environment(\.interactiveFocusFirst) private var shellFocusFirst
    @FocusState private var candidateFocus: Int?
    /// The Mac: the walk is being driven from the keyboard, so focus follows
    /// it to the next control.
    @State private var keyboardFlow = false
    @State private var nextFocus = 0
    @State private var chipsFocus = 0
    @State private var showMeFocus = 0
    @State private var rewriteFocus = 0
    /// The Mac's one glow when the reference is finished.
    @State private var glow = 0.0
    @State private var width: CGFloat = 0

    var body: some View {
        ScrollViewReader { proxy in
            VStack(alignment: .leading, spacing: theme.sectionSpacing) {
                hook
                if state.walk.finished {
                    finishedSection
                        .id(CitationScrollID.finished)
                    afterWalk
                } else {
                    walkSection
                        .id(CitationScrollID.walk)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(alignment: .bottom) {
                Color.clear.frame(height: 1).id(CitationScrollID.end).accessibilityHidden(true)
            }
            .onGeometryChange(for: CGFloat.self) { geo in
                geo.size.width
            } action: { newWidth in
                width = newWidth
            }
            .onChange(of: shellFocusFirst) { _, _ in focusFirstControl() }
            .onChange(of: state.walk.isComplete) { _, complete in
                if complete { glowOnce() }
            }
            #if os(iOS)
            .sensoryFeedback(.selection, trigger: state.walk.drawnCount)
            .sensoryFeedback(.selection, trigger: state.walk.slot)
            .sensoryFeedback(.selection, trigger: state.rewritten)
            #endif
            .task(id: state.rewritten) { await writeAgainPieces() }
            #if DEBUG
            .task { await autoplay(proxy) }
            .task { await debugScroll(proxy) }
            #endif
        }
    }

    // MARK: The hook

    private var hook: some View {
        VStack(alignment: .leading, spacing: theme.rowSpacing) {
            CitationStudentBubble()
            reply(header: nil, picks: state.walk.picks, current: state.walk.finished ? nil : state.walk.slot,
                  glow: glow)
            LabelLine(CitationCopy.replyLabel)
        }
    }

    @ViewBuilder
    private func reply(header: String?, picks: [Int?], current: CitationSlot?, glow: Double) -> some View {
        #if os(macOS)
        NightCitationSkyReply(header: header, picks: picks, current: current, glow: glow)
        #else
        CitationReplyWell(header: header, picks: picks, current: current)
        #endif
    }

    // MARK: Be the model

    private var walkSection: some View {
        let walk = state.walk
        let slot = walk.slot
        return VStack(alignment: .leading, spacing: theme.rowSpacing) {
            Text(CitationCopy.walkHeading)
                .interactiveText(.heading)
                .foregroundStyle(theme.ink)
                .accessibilityAddTraits(.isHeader)
            CitationSlotStrip(walk: walk)
            Text(CitationCopy.stepHeading(walk))
                .interactiveText(.calloutStrong)
                .foregroundStyle(theme.accentText)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityLabel(CitationCopy.stripAccessibility(walk))
                .accessibilityAddTraits(.isHeader)
            if walk.canGuess {
                Text(CitationCopy.walkPrompt)
                    .interactiveText(.callout)
                    .foregroundStyle(theme.ink2)
                    .fixedSize(horizontal: false, vertical: true)
                    .transition(.opacity)
            }
            candidates(slot)
                .id(slot)
                .transition(theme.transition(edge: .trailing))
            Text(CitationCopy.moreLine(slot))
                .interactiveText(.caption)
                .foregroundStyle(theme.ink2)
            // The draw's result right under its bars; the label stays on
            // the canvas below them, at every step.
            if walk.isDrawn(slot) {
                drawn(slot)
                    .transition(theme.transition())
            }
            LabelLine(CitationCopy.chancesLabel)
        }
    }

    @ViewBuilder
    private func candidates(_ slot: CitationSlot) -> some View {
        let group = VStack(alignment: .leading, spacing: theme.chipSpacing) {
            ForEach(CitationContent.candidates(slot).indices, id: \.self) { index in
                candidateRow(slot, index)
            }
        }
        #if os(macOS)
        if NightCitationColumns.fits(width: width) {
            NightCitationColumns(walk: state.walk, focus: $candidateFocus) { index, fromKeyboard in
                guess(index, fromKeyboard: fromKeyboard)
            }
        } else {
            group
                .accessibilityElement(children: .contain)
                .accessibilityLabel(CitationCopy.slotName(slot))
        }
        #else
        group
            .accessibilityElement(children: .contain)
            .accessibilityLabel(CitationCopy.slotName(slot))
        #endif
    }

    @ViewBuilder
    private func candidateRow(_ slot: CitationSlot, _ index: Int) -> some View {
        let walk = state.walk
        let picked = walk.isDrawn(slot) && walk.pick(slot) == index
        let row = CitationCandidateRow(walk: walk, slot: slot, index: index)
        #if os(macOS)
        row
            .modifier(NightCitationCandidateKeys(slot: slot, index: index,
                                                 focus: $candidateFocus, isEnabled: walk.canGuess,
                                                 shape: RoundedRectangle(cornerRadius: 10, style: .continuous)) {
                guess(index, fromKeyboard: $0)
            })
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(CitationCopy.candidateAccessibility(slot, index: index))
            .accessibilityValue(CitationCopy.candidateValue(walk, slot: slot, index: index))
            .accessibilityHint(walk.canGuess ? CitationCopy.walkPrompt : "")
            .accessibilityAddTraits(CitationCandidateTraits.traits(canGuess: walk.canGuess, picked: picked))
        #else
        if walk.canGuess {
            row
                .interactiveControl(shape: RoundedRectangle(cornerRadius: 14, style: .continuous)) {
                    guess(index, fromKeyboard: false)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(CitationCopy.candidateAccessibility(slot, index: index))
                .accessibilityHint(CitationCopy.walkPrompt)
                .accessibilityAddTraits(.isButton)
        } else {
            // Drawn: no longer a control. Drawn as itself, since a disabled
            // button would dim the pick that just lit up (and its words
            // below 4.5:1), and read as the slot's choice with its state.
            row
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(CitationCopy.candidateAccessibility(slot, index: index))
                .accessibilityValue(CitationCopy.candidateValue(walk, slot: slot, index: index))
                .accessibilityAddTraits(CitationCandidateTraits.traits(canGuess: false, picked: picked))
        }
        #endif
    }

    /// After a guess: what was drawn, "not always the top bar" where it
    /// applies, and the button on.
    private func drawn(_ slot: CitationSlot) -> some View {
        let walk = state.walk
        let last = slot == CitationSlot.allCases.last
        return VStack(alignment: .leading, spacing: theme.rowSpacing) {
            VStack(alignment: .leading, spacing: 4) {
                Text(CitationCopy.drawnLine(walk, slot: slot))
                    .interactiveText(.callout)
                    .foregroundStyle(theme.ink)
                if !CitationContent.isTopBar(path: walk.path, slot: slot) {
                    Text(CitationCopy.notTopLine)
                        .interactiveText(.calloutStrong)
                        .foregroundStyle(theme.accentText)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityElement(children: .combine)
            InteractiveActionButton(last ? CitationCopy.finishWalk : CitationCopy.nextPiece,
                                    systemImage: last ? "text.badge.checkmark" : "arrow.right", prominent: true,
                                    isFirst: true) {
                advance()
            }
            .environment(\.interactiveFocusFirst, nextFocus)
        }
    }

    // MARK: The finished reference

    private var finishedSection: some View {
        VStack(alignment: .leading, spacing: theme.rowSpacing) {
            Text(CitationCopy.finishedHeading)
                .interactiveText(.heading)
                .foregroundStyle(theme.ink)
                .accessibilityAddTraits(.isHeader)
            CitationPickRows(path: state.walk.path, lit: state.isRevealed)
            LabelLine(CitationCopy.chancesLabel)
            Text(CitationCopy.finishedCaption)
                .interactiveText(.callout)
                .foregroundStyle(theme.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
        .transition(theme.transition())
    }

    // MARK: Predict, reveal, write it again

    @ViewBuilder private var afterWalk: some View {
        if state.machine.asksForPrediction {
            PredictChips(CitationCopy.predictionPrompt, machine: state.machine, title: CitationCopy.choiceTitle) { choice in
                lock(choice)
            }
            .environment(\.interactiveFocusFirst, chipsFocus)
        }
        if state.showsShowMe {
            InteractiveActionButton(InteractiveShellCopy.showMe, systemImage: "eye", prominent: true, isFirst: true,
                                    accessibilityHint: InteractiveShellCopy.showMeHint) {
                reveal()
            }
            .environment(\.interactiveFocusFirst, showMeFocus)
            .id(CitationScrollID.showMe)
            .transition(theme.transition())
        }
        if state.isRevealed {
            VStack(alignment: .leading, spacing: theme.rowSpacing) {
                RevealBox(state.revealLines)
                Text(CitationCopy.topicNote)
                    .interactiveText(.callout)
                    .foregroundStyle(theme.ink2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .id(InteractiveScrollID.reveal)
            .transition(theme.transition())
            if state.canRewrite {
                InteractiveActionButton(CitationCopy.rewrite, systemImage: "arrow.clockwise", isFirst: true,
                                        accessibilityHint: CitationCopy.rewriteHint) {
                    rewrite()
                }
                .environment(\.interactiveFocusFirst, rewriteFocus)
            }
            if state.rewritten {
                VStack(alignment: .leading, spacing: theme.rowSpacing) {
                    reply(header: CitationCopy.askedAgain, picks: secondPicks, current: nil, glow: 0)
                    Text(CitationCopy.rewriteCaption)
                        .interactiveText(.callout)
                        .foregroundStyle(theme.ink)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .id(CitationScrollID.askedAgain)
                .transition(theme.transition())
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(CitationCopy.takeawayHeading)
                    .interactiveText(.heading)
                    .foregroundStyle(theme.ink)
                Text(CitationCopy.takeaway)
                    .interactiveText(.callout)
                    .foregroundStyle(theme.ink)
            }
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityElement(children: .combine)
        }
    }

    /// The second reference, as far as it is written.
    private var secondPicks: [Int?] {
        CitationSlot.allCases.map { slot in
            slot.rawValue < state.rewriteShown ? CitationContent.pick(path: CitationContent.rewritePath, slot: slot) : nil
        }
    }

    // MARK: What the student does

    private func guess(_ index: Int, fromKeyboard: Bool) {
        keyboardFlow = fromKeyboard
        var line: String?
        withAnimation(theme.animation(InteractiveMotion.change)) { line = state.guess(index) }
        guard let line else { return }
        InteractiveAccessibility.announce(line)
        if fromKeyboard { bump { nextFocus += 1 } }
    }

    private func advance() {
        var line: String?
        withAnimation(theme.animation(InteractiveMotion.change)) { line = state.advance() }
        guard let line else { return }
        InteractiveAccessibility.announce(line)
        guard keyboardFlow else { return }
        if state.walk.finished {
            bump { if state.machine.asksForPrediction { chipsFocus += 1 } else { rewriteFocus += 1 } }
        } else {
            bump { candidateFocus = 0 }
        }
    }

    private func lock(_ choice: CitationStepGuess) {
        withAnimation(theme.animation(InteractiveMotion.change)) { _ = state.lock(choice) }
        if keyboardFlow { bump { showMeFocus += 1 } }
    }

    private func reveal() {
        var line: String?
        withAnimation(theme.animation(InteractiveMotion.change)) { line = state.reveal() }
        if let line { InteractiveAccessibility.announce(line) }
        if keyboardFlow { bump { rewriteFocus += 1 } }
    }

    private func rewrite() {
        var line: String?
        withAnimation(theme.animation(InteractiveMotion.change)) { line = state.rewrite() }
        if let line { InteractiveAccessibility.announce(line) }
    }

    /// The second reference's pieces, one after another (all at once under
    /// Reduce Motion). Resumes where it was if the view is redrawn.
    private func writeAgainPieces() async {
        guard state.rewritten else { return }
        if theme.reduceMotion {
            withAnimation(InteractiveMotion.crossfade) { state.rewriteShown = CitationContent.slotCount }
            return
        }
        while state.rewriteShown < CitationContent.slotCount {
            try? await Task.sleep(for: .milliseconds(320))
            if Task.isCancelled { return }
            withAnimation(InteractiveMotion.crossfade) { state.rewriteShown += 1 }
        }
    }

    /// The Mac: the finished reference glows once (not under Reduce Motion,
    /// Increase Contrast or Reduce Transparency).
    private func glowOnce() {
        guard theme.platform == .mac, theme.lit, !theme.reduceMotion else { return }
        withAnimation(.easeOut(duration: 0.35)) { glow = 1 }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(450))
            withAnimation(.easeIn(duration: 0.9)) { glow = 0 }
        }
    }

    /// The Mac's "Try it" opened from the keyboard: the card's next control
    /// takes the keyboard.
    private func focusFirstControl() {
        keyboardFlow = true
        if state.walk.canGuess {
            bump { candidateFocus = 0 }
        } else if state.walk.canAdvance {
            bump { nextFocus += 1 }
        } else if state.asksStepQuestion && state.machine.canLock {
            bump { chipsFocus += 1 }
        } else if state.showsShowMe {
            bump { showMeFocus += 1 }
        } else if state.canRewrite {
            bump { rewriteFocus += 1 }
        }
    }

    /// Focus moves once the control it moves to is on screen.
    private func bump(_ change: @escaping @MainActor () -> Void) {
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(80))
            change()
        }
    }

    #if DEBUG
    /// `-CitationScroll …` (the shots): the part asked for, in view.
    private func debugScroll(_ proxy: ScrollViewProxy) async {
        guard let target = CitationDebug.current.scroll else { return }
        try? await Task.sleep(for: .milliseconds(2500))
        if Task.isCancelled { return }
        switch target {
        case .walk: proxy.scrollTo(CitationScrollID.walk, anchor: .top)
        case .finished: proxy.scrollTo(CitationScrollID.finished, anchor: .top)
        case .reveal: proxy.scrollTo(InteractiveScrollID.reveal, anchor: .top)
        case .end: proxy.scrollTo(CitationScrollID.end, anchor: .bottom)
        }
    }

    /// `-CitationAutoplay YES` (the reveal clip): the card's next actions
    /// play by themselves, about 1.5 s apart, keeping the newest part in
    /// view. Never under Reduce Motion.
    private func autoplay(_ proxy: ScrollViewProxy) async {
        guard CitationDebug.current.autoplay, !theme.reduceMotion, !CitationAutoplayRun.started else { return }
        CitationAutoplayRun.started = true
        if state.showsShowMe { proxy.scrollTo(CitationScrollID.showMe, anchor: .bottom) }
        try? await Task.sleep(for: .seconds(2))
        while !Task.isCancelled {
            if state.walk.canGuess {
                guess(0, fromKeyboard: false)
            } else if state.walk.canAdvance {
                advance()
            } else if state.asksStepQuestion && state.machine.canLock {
                lock(.author)
            } else if state.showsShowMe {
                reveal()
                try? await Task.sleep(for: .milliseconds(150))
                withAnimation(.smooth(duration: 0.6)) { proxy.scrollTo(InteractiveScrollID.reveal, anchor: .center) }
            } else if state.canRewrite {
                rewrite()
                try? await Task.sleep(for: .milliseconds(150))
                withAnimation(.smooth(duration: 0.6)) { proxy.scrollTo(CitationScrollID.askedAgain, anchor: .center) }
            } else {
                return
            }
            try? await Task.sleep(for: .milliseconds(1500))
        }
    }
    #endif
}

#if DEBUG
@MainActor
private enum CitationAutoplayRun {
    static var started = false
}
#endif
