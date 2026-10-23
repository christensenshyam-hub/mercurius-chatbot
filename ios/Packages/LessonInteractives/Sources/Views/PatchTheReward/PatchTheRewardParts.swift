import SwiftUI
import DesignSystem

/// Patch the Reward's content: the hook, the track and its counters (the
/// stage), what the picked rule is doing (the panel: play, guess, the run,
/// its result), the toy label, the rules (the one control), and once all
/// three patches have run, the reveal and the takeaway.
///
/// - Stacked (the iPhone, a narrow Mac card): the panel sits right under
///   the stage, so a run and its result share a screen; the reveal follows
///   the panel (the last patch's result, then the reveal); the label comes
///   before the rules, so it is passed on the way to every guess.
/// - Wide (the Mac): the label under the stage, the rules beside the panel,
///   the reveal under both.
///
/// A run plays on the stage, but the student starts it from the panel or a
/// chip that may sit a screen below it: the lesson's list brings the stage
/// into view as the run starts (`InteractiveScrollAction`), the panel when
/// a picked patch asks its question, and the reveal when it arrives after a
/// run the student watched. At the accessibility text sizes the stage and
/// the panel can't share a screen, so a run shows at once there, as under
/// Reduce Motion: its still and result, where the student tapped. Every
/// word is `PatchTheRewardCopy`'s.
struct PatchTheRewardBody: View {
    let state: PatchTheRewardState
    /// The Mac at full width: the rules table to the right of the panel.
    let wide: Bool
    /// The Mac: the boat's wake is lit.
    let lit: Bool

    @Environment(\.interactiveTheme) private var theme
    @Environment(\.interactiveScrollIntoView) private var scrollIntoView
    #if os(iOS)
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOver
    #endif

    /// Runs play out on the track, unless Reduce Motion is on (then a run's
    /// still and its result show at once), VoiceOver is (the result is
    /// spoken at once instead of after a silent run), or the text is at an
    /// accessibility size (the stage is screens away from the panel).
    private var animated: Bool {
        #if os(iOS)
        return InteractiveMotion.autoplays(reduceMotion: theme.reduceMotion) && !voiceOver && !theme.usesTables
        #else
        return InteractiveMotion.autoplays(reduceMotion: theme.reduceMotion)
        #endif
    }

    private var voiceOverRunning: Bool {
        #if os(iOS)
        return voiceOver
        #else
        return false
        #endif
    }

    var body: some View {
        VStack(alignment: .leading, spacing: theme.sectionSpacing) {
            VStack(alignment: .leading, spacing: theme.rowSpacing) {
                Text(PatchTheRewardCopy.hook)
                    .interactiveText(.body)
                    .foregroundStyle(theme.ink)
                Text(PatchTheRewardCopy.trackLine)
                    .interactiveText(.callout)
                    .foregroundStyle(theme.ink2)
            }
            .fixedSize(horizontal: false, vertical: true)
            if wide {
                VStack(alignment: .leading, spacing: theme.rowSpacing) {
                    stage
                    LabelLine(PatchTheRewardCopy.toyLabel)
                }
                HStack(alignment: .top, spacing: theme.sectionSpacing) {
                    panel
                        .frame(maxWidth: .infinity, alignment: .leading)
                    PatchRuleList(state: state, animated: animated)
                        .frame(width: 236, alignment: .leading)
                }
                reveal
            } else {
                stage
                panel
                reveal
                LabelLine(PatchTheRewardCopy.toyLabel)
                PatchRuleList(state: state, animated: animated)
            }
        }
        .animation(theme.animation(InteractiveMotion.change), value: state.isRevealed)
        .onChange(of: state.finishedRuns) { _, _ in runEnded() }
        // A run started: the stage into view (the student may have tapped
        // its chip or guess a screen below it).
        .onChange(of: state.playing?.id) { _, id in
            guard id != nil else { return }
            scrollIntoView(InteractiveScrollID.stage, animated: !theme.reduceMotion)
        }
        // A picked patch asks its question in the panel, above the chips
        // (not under VoiceOver, whose focus stays on the chip and which
        // hears the question in the card's summary).
        .onChange(of: state.awaitsGuess ? state.selected : nil) { _, rule in
            guard rule != nil, !voiceOverRunning else { return }
            scrollIntoView(InteractiveScrollID.panel, animated: !theme.reduceMotion)
        }
        #if DEBUG
        .task { await state.debugAutoRun(animated: animated) }
        #endif
    }

    private var stage: some View {
        PatchStage(state: state, lit: lit)
            .interactiveScrollMark(InteractiveScrollID.stage)
    }

    private var panel: some View {
        PatchPanel(state: state, animated: animated)
            .interactiveScrollMark(InteractiveScrollID.panel)
    }

    /// The reveal, once all three patches have run: the guesses beside
    /// what happened, the takeaway and the made-up label. "It isn't
    /// cheating. It's scoring." isn't said again here: A's and B's results
    /// carry it.
    @ViewBuilder private var reveal: some View {
        if let reveal = state.overallReveal {
            VStack(alignment: .leading, spacing: theme.rowSpacing) {
                RevealBox(reveal)
                InteractiveTakeaway(PatchTheRewardCopy.takeawayLine, detail: PatchTheRewardCopy.takeawayDetail)
                LabelLine(PatchTheRewardCopy.madeUpLabel)
            }
            .interactiveScrollMark(InteractiveScrollID.reveal)
            .transition(theme.transition())
        }
    }

    /// A run ended: say what it did (and, after the third patch, the
    /// reveal); after a run the student watched on the stage, bring the
    /// reveal into view a beat later (the finished counters and the run's
    /// result are seen first, and the reveal has been laid out).
    private func runEnded() {
        guard let rule = state.lastFinished else { return }
        var line = PatchTheRewardCopy.spokenRun(rule) + " " + PatchTheRewardCopy.caption(rule)
        let bringsReveal = state.overallReveal != nil && state.revealedOnRun == state.finishedRuns
        if bringsReveal, let reveal = state.overallReveal {
            line += " " + reveal.spoken
        }
        InteractiveAccessibility.announce(line)
        guard bringsReveal, animated else { return }
        let scroll = scrollIntoView
        let smooth = !theme.reduceMotion
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 800_000_000)
            scroll(InteractiveScrollID.reveal, animated: smooth)
        }
    }
}

// MARK: - The stage: the track and its counters

/// The track and, under it, the points and laps so far. While a run plays
/// both follow the race clock; otherwise they show where the shown run
/// ended (or the start, before any run).
struct PatchStage: View {
    let state: PatchTheRewardState
    let lit: Bool
    @Environment(\.interactiveTheme) private var theme

    var body: some View {
        if let playing = state.playing {
            TimelineView(.animation) { timeline in
                content(rule: playing.rule, tick: playing.tick(at: timeline.date), live: true)
            }
        } else {
            content(rule: state.shownRule, tick: Double(PatchTrack.clockTicks), live: false)
        }
    }

    private func content(rule: PatchRule?, tick: Double, live: Bool) -> some View {
        let frame = rule.map { PatchTheRewardContent.run($0).frame(at: tick) }
        let tiles = [
            CounterTile(PatchTheRewardCopy.pointsTile, text: PatchTheRewardCopy.grouped(frame?.points ?? 0)),
            CounterTile(PatchTheRewardCopy.lapsTile, text: PatchTheRewardCopy.lapsValue(frame?.laps ?? 0)),
        ]
        return VStack(alignment: .leading, spacing: theme.rowSpacing) {
            PatchTrackPicture(rule: rule, tick: tick, live: live, lit: lit)
            // At the accessibility sizes the picture keeps its width but its
            // labels don't grow: what it shows is written under it as well
            // (VoiceOver hears it once, in the picture's label).
            if theme.usesTables {
                Text(PatchTheRewardCopy.trackCaption(rule, playing: live))
                    .interactiveText(.callout)
                    .foregroundStyle(theme.ink2)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityHidden(true)
            }
            CounterTiles(tiles)
        }
    }
}

// MARK: - The panel: what the picked rule is doing

/// The picked rule's part: before the first run, the 2016-style rule and
/// Play it; for a patch not yet run, its guess; while a run plays, Skip; and
/// once run, its result beside the guess.
struct PatchPanel: View {
    let state: PatchTheRewardState
    let animated: Bool
    @Environment(\.interactiveTheme) private var theme

    var body: some View {
        let rule = state.selected
        VStack(alignment: .leading, spacing: theme.rowSpacing) {
            if let playing = state.playing {
                ruleHeading(playing.rule)
                if let machine = state.machine(playing.rule), let guess = machine.guess, machine.asksForPrediction {
                    Text("\(InteractiveShellCopy.youGuessed): \(PatchTheRewardCopy.guessText(guess))")
                        .interactiveText(.callout)
                        .foregroundStyle(theme.ink2)
                }
                InteractiveActionButton(PatchTheRewardCopy.skip, systemImage: "forward.end.fill", isFirst: true,
                                        accessibilityHint: PatchTheRewardCopy.skipHint) {
                    state.skip()
                }
            } else if rule == .targets && !state.replayed {
                Text(PatchTheRewardCopy.replayRule)
                    .interactiveText(.heading)
                    .foregroundStyle(theme.ink)
                    .fixedSize(horizontal: false, vertical: true)
                InteractiveActionButton(PatchTheRewardCopy.playReplay, systemImage: "play.fill", prominent: true,
                                        isFirst: true, accessibilityHint: PatchTheRewardCopy.playReplayHint) {
                    state.play(.targets, animated: animated)
                }
            } else if state.awaitsGuess, let machine = state.machine(rule) {
                ruleHeading(rule)
                PredictChips(PatchTheRewardCopy.predictPrompt, machine: machine,
                             title: PatchTheRewardCopy.guessChoice) { guess in
                    state.lock(guess, animated: animated)
                }
            } else if state.hasRun(rule) {
                RevealBox(state.revealLines(rule), takeaway: PatchTheRewardCopy.caption(rule))
                InteractiveActionButton(PatchTheRewardCopy.playAgain, systemImage: "arrow.counterclockwise",
                                        accessibilityHint: PatchTheRewardCopy.playReplayHint) {
                    state.play(rule, animated: animated)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func ruleHeading(_ rule: PatchRule) -> some View {
        Text(PatchTheRewardCopy.chip(rule))
            .interactiveText(.heading)
            .foregroundStyle(theme.ink)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityLabel(PatchTheRewardCopy.spokenRule(rule))
    }
}

// MARK: - The rules: the one control

/// The goal, then a chip per rule: the 2016-style rule and patches A, B and
/// C (open once the 2016-style rule has run). A chip shows its rule on the
/// track (a patch not yet run asks for its guess); the picked rule's chip
/// plays it again. A tried rule's chip says how many laps it finished. The
/// Mac: Tab reaches each chip, Space or Return picks (or replays), ←/→ move
/// to the rule before or after.
struct PatchRuleList: View {
    let state: PatchTheRewardState
    let animated: Bool
    @Environment(\.interactiveTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: theme.rowSpacing) {
            Text(PatchTheRewardCopy.goal)
                .interactiveText(.heading)
                .foregroundStyle(theme.ink)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            VStack(alignment: .leading, spacing: theme.chipSpacing) {
                ForEach(PatchRule.allCases, id: \.self) { rule in
                    chip(rule)
                }
            }
        }
        #if os(iOS)
        .sensoryFeedback(.selection, trigger: state.selected)
        #endif
    }

    private func chip(_ rule: PatchRule) -> some View {
        let tried = state.hasRun(rule)
        let title = tried ? "\(PatchTheRewardCopy.chip(rule)) \u{00B7} \(PatchTheRewardCopy.chipStatus(rule))"
                          : PatchTheRewardCopy.chip(rule)
        let enabled = state.canPick(rule)
        return InteractiveChip(title, isSelected: state.selected == rule, isEnabled: enabled,
                               isFirst: rule == .targets,
                               accessibilityLabel: PatchTheRewardCopy.chipAccessibility(rule, tried: tried),
                               accessibilityHint: PatchTheRewardCopy.pickHint,
                               onArrow: { arrow in
                                   if let next = state.neighbour(of: rule, arrow) { state.pick(next, animated: animated) }
                               }) {
            state.pick(rule, animated: animated)
        }
        .accessibilityValue(enabled ? "" : PatchTheRewardCopy.pickFirst)
    }
}
