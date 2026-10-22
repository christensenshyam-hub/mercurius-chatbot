#if os(macOS)
import SwiftUI
import DesignSystem

/// The Doubt Dial on the Mac (U6L4): Night Studio's lit card, in the same
/// order as the iPhone's, with the feed in two columns, Shared | Waved
/// away. As the dial turns, posts crossfade from one column to the other
/// (a fade, with or without Reduce Motion; nothing slides). The counters
/// glow in lumen (not under Increase Contrast or Reduce Transparency).
/// Below 440 pt the shell shows the compact "Try it" card, which opens in
/// place.
///
/// - Keyboard: Tab reaches the guesses, the dial, "Show me" and "Check
///   first"; Space or Return presses; ←/→ turn the dial only while it has
///   focus, so A–D, 1–4 and ↑/↓ still answer the lesson's check, and a
///   focused control holds Return from it (the shared controls' contract).
/// - VoiceOver: as on the iPhone; each column is a header with its count.
public struct NightDoubtDialCard: View {
    private let context: InteractiveCardContext

    public init(_ context: InteractiveCardContext) {
        self.context = context
    }

    public var body: some View {
        let state = context.state { DoubtDialState(spoiled: $0.spoiled) }
        InteractiveCardShell(id: context.id, title: DoubtDialCopy.title, summary: state.summary,
                             compactLine: DoubtDialCopy.compactLine) {
            NightDoubtDialBody(state: state)
        }
    }
}

private struct NightDoubtDialBody: View {
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
            DoubtDialDialSection(state: state, onTurn: actions.turn, glowingCounters: true)
            DoubtDialProgress(state: state, onShowMe: actions.showMe)
            if state.machine.isRevealed {
                RevealBox(state.revealLines)
                    .id(InteractiveScrollID.reveal)
                    .transition(theme.transition())
                DoubtDialCheckSection(state: state, onCheck: actions.checkFirst, onBack: actions.backToDial,
                                      glowingCounters: true)
                    .transition(theme.transition())
            }
            feed
        }
    }

    // MARK: The feed

    private var feed: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: theme.chipSpacing) {
                Text(DoubtDialCopy.feedTitle)
                    .interactiveText(.heading)
                    .foregroundStyle(theme.ink)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 0)
                Text(DoubtDialCopy.feedOrder)
                    .interactiveText(.caption)
                    .foregroundStyle(theme.ink2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(alignment: .top, spacing: 12) {
                if let columns = sortedColumns {
                    column(columns.left.title, posts: columns.left.posts)
                    column(columns.right.title, posts: columns.right.posts)
                } else {
                    // No guess yet: no verdicts, the feed in two halves.
                    let half = (DoubtDialContent.posts.count + 1) / 2
                    column(nil, posts: Array(DoubtDialContent.posts.prefix(half)))
                    column(nil, posts: Array(DoubtDialContent.posts.dropFirst(half)))
                }
            }
        }
    }

    /// Shared | Waved away (the dial), or Shared | Not shared (checking).
    private var sortedColumns: (left: (title: String, posts: [DoubtDialPost]),
                                right: (title: String, posts: [DoubtDialPost]))? {
        guard state.machine.canExplore || state.checking else { return nil }
        let shared = DoubtDialContent.posts.filter { state.verdict(for: $0)?.isShared == true }
        let other = DoubtDialContent.posts.filter { state.verdict(for: $0)?.isShared != true }
        let right = state.checking ? DoubtDialCopy.notSharedColumn : DoubtDialCopy.wavedAwayColumn
        return ((DoubtDialCopy.sharedColumn, shared), (right, other))
    }

    private func column(_ title: String?, posts: [DoubtDialPost]) -> some View {
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
        return VStack(alignment: .leading, spacing: 4) {
            if let title {
                Text(DoubtDialCopy.column(title, count: posts.count).uppercased())
                    .interactiveText(.eyebrow)
                    .foregroundStyle(theme.accentText)
                    .contentTransition(.identity)
                    .accessibilityLabel(DoubtDialCopy.columnSpoken(title, count: posts.count))
                    .accessibilityAddTraits(.isHeader)
            }
            if posts.isEmpty {
                Text(DoubtDialCopy.emptyColumn)
                    .interactiveText(.caption)
                    .foregroundStyle(theme.ink2)
                    .padding(.vertical, 6)
                    .transition(.opacity)
            }
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(posts.enumerated()), id: \.element.id) { index, post in
                    if index > 0 {
                        Rectangle()
                            .fill(theme.increasedContrast ? theme.hairline : theme.wellEdge.opacity(0.6))
                            .frame(height: 1)
                            .accessibilityHidden(true)
                    }
                    DoubtDialPostRow(post: post, verdict: state.verdict(for: post), checking: state.checking)
                        .transition(.opacity)
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(theme.raised, in: shape)
        .overlay(shape.strokeBorder(theme.increasedContrast ? theme.hairline : theme.wellEdge.opacity(0.5),
                                    lineWidth: 1))
    }
}
#endif
