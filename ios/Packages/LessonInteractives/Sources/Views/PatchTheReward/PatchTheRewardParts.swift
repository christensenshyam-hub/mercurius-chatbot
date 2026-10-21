import SwiftUI
import DesignSystem

/// Patch the Reward's content, in the order both platforms show it: the
/// hook, the track and its counters (the stage), its label, what the picked
/// rule is doing (the panel: play, guess, the run, its result), the rules
/// (the one control), then the reveal and the takeaway. The iPhone stacks
/// it all; the Mac puts the rules beside the panel when the card is wide
/// (`wide`). Every word is `PatchTheRewardCopy`'s.
struct PatchTheRewardBody: View {
    let state: PatchTheRewardState
    /// The Mac at full width: the rules table to the right of the panel.
    let wide: Bool
    /// The Mac: the boat's wake is lit.
    let lit: Bool

    @Environment(\.interactiveTheme) private var theme
    #if os(iOS)
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOver
    #endif

    /// Runs play out on the track, unless Reduce Motion is on (then a run's
    /// still and its result show at once) or VoiceOver is (the result is
    /// spoken at once instead of after a silent run).
    private var animated: Bool {
        #if os(iOS)
        return InteractiveMotion.autoplays(reduceMotion: theme.reduceMotion) && !voiceOver
        #else
        return InteractiveMotion.autoplays(reduceMotion: theme.reduceMotion)
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
            VStack(alignment: .leading, spacing: theme.rowSpacing) {
                PatchStage(state: state, lit: lit)
                LabelLine(PatchTheRewardCopy.toyLabel)
            }
            if wide {
                HStack(alignment: .top, spacing: theme.sectionSpacing) {
                    PatchPanel(state: state, animated: animated)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    PatchRuleList(state: state, animated: animated)
                        .frame(width: 236, alignment: .leading)
                }
            } else {
                PatchPanel(state: state, animated: animated)
                PatchRuleList(state: state, animated: animated)
            }
            if let reveal = state.overallReveal {
                VStack(alignment: .leading, spacing: theme.rowSpacing) {
                    RevealBox(reveal, takeaway: PatchTheRewardCopy.scoring)
                        .id(InteractiveScrollID.reveal)
                    Text(PatchTheRewardCopy.takeaway)
                        .interactiveText(.body)
                        .foregroundStyle(theme.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    LabelLine(PatchTheRewardCopy.madeUpLabel)
                }
                .transition(theme.transition())
            }
        }
        .animation(theme.animation(InteractiveMotion.change), value: state.isRevealed)
        .onChange(of: state.finishedRuns) { _, _ in announceRun() }
        #if DEBUG
        .task { await state.debugAutoRun(animated: animated) }
        #endif
    }

    /// Says what the run did (and, after the third patch, the reveal).
    private func announceRun() {
        guard let rule = state.lastFinished else { return }
        var line = PatchTheRewardCopy.spokenRun(rule) + " " + PatchTheRewardCopy.caption(rule)
        if let reveal = state.overallReveal, state.revealedOnRun == state.finishedRuns {
            line += " " + reveal.spoken
            if !line.contains(PatchTheRewardCopy.scoring) { line += " " + PatchTheRewardCopy.scoring }
        }
        InteractiveAccessibility.announce(line)
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
