#if os(iOS)
import SwiftUI
import DesignSystem

/// The Doubt Dial on the iPhone (U6L4): today's lesson design, the
/// night-sky island Lesson 1.1's card uses, in one column. The hook, the
/// guess, the dial with its two counters, "Show me", the reveal, "Check
/// first", then the feed, least surprising first, each post changing in
/// place as the dial turns (a crossfade, never a slide).
///
/// - 44 pt targets and a selection haptic on every pick, stop and check
///   (the shared controls give both).
/// - The accessibility sizes: the dial is two step buttons with its stop in
///   words, the counters and the mistakes row are text tables, and each post
///   is its title and a line of words. Decoration (dots, glyphs) goes,
///   never a word.
/// - VoiceOver: the title says the card's state in one sentence; the dial
///   is one adjustable element; each post is one element ending in its
///   state; the reveal and "Check first" are announced.
public struct DoubtDialPhoneCard: View {
    private let context: InteractiveCardContext

    public init(_ context: InteractiveCardContext) {
        self.context = context
    }

    public var body: some View {
        let state = context.state { DoubtDialState(spoiled: $0.spoiled) }
        InteractiveCardShell(id: context.id, title: DoubtDialCopy.title, summary: state.summary,
                             compactLine: DoubtDialCopy.compactLine) {
            DoubtDialPhoneBody(state: state)
        }
    }
}

private struct DoubtDialPhoneBody: View {
    let state: DoubtDialState
    @Environment(\.interactiveTheme) private var theme

    var body: some View {
        let actions = DoubtDialActions(state: state, theme: theme)
        VStack(alignment: .leading, spacing: theme.sectionSpacing) {
            DoubtDialHook()
            if state.machine.asksForPrediction {
                PredictChips(DoubtDialCopy.predictPrompt, machine: state.machine, title: DoubtDialCopy.guessTitle,
                             onLock: actions.lock)
            }
            DoubtDialDialSection(state: state, onTurn: actions.turn)
            DoubtDialProgress(state: state, onShowMe: actions.showMe)
            if state.machine.isRevealed {
                RevealBox(state.revealLines)
                    .modifier(DoubtDialScrollMark(isFeed: false))
                    .transition(theme.doubtDialArrival)
                DoubtDialCheckSection(state: state, onCheck: actions.checkFirst, onBack: actions.backToDial)
                    .transition(theme.doubtDialArrival)
            }
            feed
        }
        .sensoryFeedback(.selection, trigger: state.checking)
    }

    private var feed: some View {
        VStack(alignment: .leading, spacing: 4) {
            let layout = theme.usesTables
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: 2))
                : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: theme.chipSpacing))
            layout {
                Text(DoubtDialCopy.feedTitle)
                    .interactiveText(.heading)
                    .foregroundStyle(theme.ink)
                    .accessibilityAddTraits(.isHeader)
                    .modifier(DoubtDialScrollMark(isFeed: true))
                if !theme.usesTables { Spacer(minLength: 0) }
                Text(DoubtDialCopy.feedOrder)
                    .interactiveText(.caption)
                    .foregroundStyle(theme.ink2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            DoubtDialPostList(posts: DoubtDialContent.posts, verdict: state.verdict(for:), checking: state.checking)
        }
    }
}
#endif
