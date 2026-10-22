import SwiftUI
import DesignSystem

// The Doubt Dial's sections, shared by the iPhone card and the Mac card:
// the hook, the dial with its counters, "Show me", and "Check first". Each
// platform card stacks them in the same order and draws the feed its own
// way (one column on the iPhone; Shared | Waved away on the Mac).

extension InteractiveTheme {
    /// How the reveal and "Check first" arrive: a fade that waits for the
    /// card's layout to settle, so the new text never draws over the feed
    /// while it is still moving down. Only a fade, with or without Reduce
    /// Motion. Leaving, it fades at once.
    var doubtDialArrival: AnyTransition {
        .asymmetric(insertion: .opacity.animation(InteractiveMotion.crossfade.delay(reduceMotion ? 0.2 : 0.3)),
                    removal: .opacity.animation(InteractiveMotion.crossfade.speed(2)))
    }
}

/// The card's DEBUG scroll mark (`InteractiveScrollID.reveal`): on the
/// reveal, or with `-DoubtDialScrollFeed YES` on the feed's heading instead
/// (shots of the feed's columns). Release reads no arguments, so the mark
/// stays on the reveal.
struct DoubtDialScrollMark: ViewModifier {
    /// Whether this is the feed's heading (else the reveal).
    let isFeed: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if DoubtDialDebug.current.scrollToFeed == isFeed {
            content.id(InteractiveScrollID.reveal)
        } else {
            content
        }
    }
}

/// What the student does, with the card's motion (a crossfade under Reduce
/// Motion) and VoiceOver's announcements of what they caused. The dial's
/// own moves aren't announced: VoiceOver reads an adjustable control's new
/// value itself, and the title's value says the state.
@MainActor
struct DoubtDialActions {
    let state: DoubtDialState
    let theme: InteractiveTheme

    func lock(_ guess: DoubtDialGuess) {
        withAnimation(theme.animation(InteractiveMotion.change)) { _ = state.lock(guess) }
    }

    func turn(_ stop: Int) {
        withAnimation(theme.animation(InteractiveMotion.change)) { _ = state.turn(to: stop) }
    }

    func showMe() {
        var shown = false
        withAnimation(theme.animation(InteractiveMotion.change)) { shown = state.showMe() }
        if shown { InteractiveAccessibility.announce(state.revealLines.spoken) }
    }

    func checkFirst() {
        var shown = false
        withAnimation(theme.animation(InteractiveMotion.change)) { shown = state.checkFirst() }
        if shown {
            InteractiveAccessibility.announce("\(DoubtDialCopy.accessibilitySummary(.checked)) \(DoubtDialCopy.takeaway)")
        }
    }

    func backToDial() {
        var back = false
        withAnimation(theme.animation(InteractiveMotion.change)) { back = state.backToDial() }
        if back { InteractiveAccessibility.announce(DoubtDialCopy.dialValue(atStop: state.stop)) }
    }
}

/// The hook: ten made-up posts, 5 real and 5 fake; what the dots mean; the
/// slate's label on the canvas.
struct DoubtDialHook: View {
    @Environment(\.interactiveTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: theme.rowSpacing) {
            Text(DoubtDialCopy.hook)
                .interactiveText(.body)
                .foregroundStyle(theme.ink)
                .fixedSize(horizontal: false, vertical: true)
            Text(DoubtDialCopy.dotsLine)
                .interactiveText(.callout)
                .foregroundStyle(theme.ink2)
                .fixedSize(horizontal: false, vertical: true)
            LabelLine(DoubtDialCopy.feedLabel)
        }
    }
}

/// The one control and what it counts: the dial (off until the guess is
/// locked), once revealed each setting's mistakes under its stops, the
/// stop's rule in words, the feed in one strip with the dial's cut through
/// it (so each turn visibly moves the cut and flips posts), and the two
/// counters. At the accessibility sizes the strip is a line of words under
/// the counters.
struct DoubtDialDialSection: View {
    let state: DoubtDialState
    let onTurn: (Int) -> Void
    /// The Mac: the counters glow in lumen.
    var glowingCounters = false
    @Environment(\.interactiveTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: theme.rowSpacing) {
            Text(DoubtDialCopy.dialName)
                .interactiveText(.caption)
                .foregroundStyle(theme.ink2)
                .accessibilityHidden(true)
            StopControl(DoubtDialCopy.dialAccessibilityName, stops: DoubtDialCopy.stops, selection: state.stop,
                        isEnabled: state.machine.canExplore, value: DoubtDialCopy.dialValue(atStop:),
                        decreaseLabel: DoubtDialCopy.lessDoubt, increaseLabel: DoubtDialCopy.moreDoubt,
                        onSelect: onTurn)
            if state.machine.isRevealed {
                DoubtDialMistakesRow(current: state.stop)
                    .padding(.top, 2)
                    .transition(theme.doubtDialArrival)
            }
            if state.machine.canExplore {
                Text(DoubtDialCopy.rule(atStop: state.stop))
                    .interactiveText(.callout)
                    .foregroundStyle(theme.ink2)
                    .fixedSize(horizontal: false, vertical: true)
                    .contentTransition(.opacity)
                if !theme.usesTables {
                    DoubtDialFeedStrip(stop: state.stop)
                        .transition(.opacity)
                }
                counters
                    .padding(.top, 2)
                    .transition(theme.transition())
                if theme.usesTables {
                    // The strip in words, under the counters.
                    Text(DoubtDialCopy.mistakesHere(atStop: state.stop))
                        .interactiveText(.callout)
                        .foregroundStyle(theme.ink)
                        .fixedSize(horizontal: false, vertical: true)
                        .contentTransition(.opacity)
                }
            }
        }
    }

    private var counters: some View {
        let tally = state.dialTally
        return VStack(alignment: .leading, spacing: 6) {
            CounterTiles([CounterTile(DoubtDialCopy.fakesSharedLabel, value: tally.fakesShared),
                          CounterTile(DoubtDialCopy.realWavedAwayLabel, value: tally.realWavedAway)])
                .shadow(color: theme.lumen.opacity(glowingCounters && theme.lit ? 0.35 : 0), radius: 12)
            Text(DoubtDialCopy.mistakesLine(atStop: state.stop))
                .interactiveText(.caption)
                .foregroundStyle(theme.ink2)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityHidden(true)
        }
    }
}

/// Between the dial and the reveal: what to do next ("Turn the dial…"),
/// then "Show me" once the dial has been turned enough.
struct DoubtDialProgress: View {
    let state: DoubtDialState
    let onShowMe: () -> Void
    @Environment(\.interactiveTheme) private var theme

    var body: some View {
        if state.machine.showsShowMe {
            InteractiveActionButton(InteractiveShellCopy.showMe, systemImage: "eye", prominent: true,
                                    accessibilityHint: InteractiveShellCopy.showMeHint, action: onShowMe)
                .transition(theme.transition())
        } else if state.machine.canExplore && !state.machine.isRevealed {
            Text(DoubtDialCopy.turnPrompt)
                .interactiveText(.callout)
                .foregroundStyle(theme.ink2)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// After the reveal, the move that works: "Check first", then checking's
/// three counters, what checking did (8 of 10 sorted, 2 held back), and
/// the label that the checks are made up too, and real checking messier. "Back to the dial" leaves it (so does turning the dial).
struct DoubtDialCheckSection: View {
    let state: DoubtDialState
    let onCheck: () -> Void
    let onBack: () -> Void
    var glowingCounters = false
    @Environment(\.interactiveTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: theme.rowSpacing) {
            Text(DoubtDialCopy.checkIntro)
                .interactiveText(.callout)
                .foregroundStyle(theme.ink)
                .fixedSize(horizontal: false, vertical: true)
            if state.checking {
                let tally = DoubtDialContent.checkTally
                CounterTiles([CounterTile(DoubtDialCopy.checkedFakesLabel, value: tally.fakesShared),
                              CounterTile(DoubtDialCopy.checkedRealLabel, value: tally.realWavedAway),
                              CounterTile(DoubtDialCopy.notSureYetLabel, value: tally.notSureYet)])
                    .shadow(color: theme.lumen.opacity(glowingCounters && theme.lit ? 0.35 : 0), radius: 12)
                    .transition(theme.doubtDialArrival)
                Text(DoubtDialCopy.takeaway)
                    .interactiveText(.heading)
                    .foregroundStyle(theme.ink)
                    .fixedSize(horizontal: false, vertical: true)
                    .transition(theme.doubtDialArrival)
                LabelLine(DoubtDialCopy.checkLabel)
                InteractiveActionButton(DoubtDialCopy.backToDial, systemImage: "arrow.uturn.backward",
                                        accessibilityHint: DoubtDialCopy.backHint, action: onBack)
            } else {
                InteractiveActionButton(DoubtDialCopy.checkFirst, systemImage: "magnifyingglass", prominent: true,
                                        accessibilityHint: DoubtDialCopy.checkHint, action: onCheck)
            }
        }
    }
}
