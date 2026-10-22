import SwiftUI
import DesignSystem

// The Doubt Dial's pieces, drawn the same way on both platforms with the
// card's theme (`\.interactiveTheme`): a post in the feed, its surprise
// dots, and the "mistakes at each setting" row under the dial. The
// platform cards (`DoubtDialPhoneCard`, `NightDoubtDialCard`) arrange them.

/// A post's state glyph: never the only sign, the word sits beside it.
enum DoubtDialGlyph {
    static func name(_ verdict: DoubtDialVerdict) -> String {
        switch verdict {
        case .shared: return "arrow.up.right"
        case .wavedAway, .notShared: return "nosign"
        case .notSureYet: return "ellipsis"
        }
    }
}

/// "How surprising": `surprise` of 5 dots filled. Decoration beside words
/// VoiceOver says ("Surprise 4 of 5"); gone at the accessibility sizes,
/// where the row says it in text.
struct DoubtDialDots: View {
    let surprise: Int
    @Environment(\.interactiveTheme) private var theme
    /// The iPhone's dots grow with the text, up to the accessibility sizes
    /// (where they go).
    @ScaledMetric(relativeTo: .caption) private var phoneDot: CGFloat = 7

    var body: some View {
        let size: CGFloat = theme.platform == .phone ? min(phoneDot, 10) : 6
        HStack(spacing: size * 0.45) {
            ForEach(1...DoubtDialContent.maxSurprise, id: \.self) { dot in
                let filled = dot <= surprise
                Circle()
                    .fill(filled ? theme.accentText : Color.clear)
                    .overlay(Circle().strokeBorder(filled ? theme.accentText : theme.wellEdge, lineWidth: 1))
                    .frame(width: size, height: size)
            }
        }
        .accessibilityHidden(true)
    }
}

/// "✕ Mistake" in a small well, beside a post the setting got wrong: the
/// counters' posts, marked one by one. Decoration plus a word (VoiceOver
/// says "A mistake" in the post's line).
struct DoubtDialMistakeTag: View {
    @Environment(\.interactiveTheme) private var theme

    var body: some View {
        HStack(alignment: .center, spacing: 3) {
            Image(systemName: "xmark")
                .font(.system(size: theme.platform == .phone ? 9 : 8, weight: .heavy))
            Text(DoubtDialCopy.mistakeTag)
                .interactiveText(.caption)
        }
        .foregroundStyle(theme.ink)
        .padding(.horizontal, 7)
        .padding(.vertical, 2)
        .background(theme.wash(theme.increasedContrast ? 0.3 : 0.22), in: Capsule())
        .overlay(Capsule().strokeBorder(theme.increasedContrast ? theme.hairline : theme.accentText.opacity(0.6),
                                        lineWidth: 1))
        .accessibilityHidden(true)
    }
}

/// One post: its glyph and verdict word (once there is one), its title,
/// whether we wrote it real or fake, its surprise dots, and under
/// "Check first" what checking found. One VoiceOver element that ends in
/// its state. The verdict crossfades in place.
struct DoubtDialPostRow: View {
    let post: DoubtDialPost
    let verdict: DoubtDialVerdict?
    let checking: Bool
    @Environment(\.interactiveTheme) private var theme
    @ScaledMetric(relativeTo: .callout) private var glyphWidth: CGFloat = 16

    var body: some View {
        Group {
            if theme.usesTables {
                textForm
            } else {
                drawn
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(DoubtDialCopy.postAccessibility(post, verdict: verdict, checking: checking))
    }

    /// Waved away, not shared or not sure: the title steps back a shade
    /// (still 4.5:1 or better), and the glyph and the word say why.
    private var titleColor: Color {
        guard let verdict else { return theme.ink }
        return verdict.isShared ? theme.ink : theme.ink2
    }

    private var drawn: some View {
        HStack(alignment: .firstTextBaseline, spacing: theme.platform == .phone ? 10 : 8) {
            ZStack {
                if let verdict {
                    Image(systemName: DoubtDialGlyph.name(verdict))
                        .font(.system(size: theme.platform == .phone ? 13 : 11, weight: .bold))
                        .foregroundStyle(verdict.isShared ? theme.accentText : theme.ink2)
                        .transition(.opacity)
                        .id(verdict)
                }
            }
            .frame(width: theme.platform == .phone ? glyphWidth : 14)
            VStack(alignment: .leading, spacing: 3) {
                Text(post.title)
                    .interactiveText(.callout)
                    .foregroundStyle(titleColor)
                    .fixedSize(horizontal: false, vertical: true)
                // The facts and the verdict on one line, or the verdict on
                // its own line when they don't fit (a narrow Mac column,
                // the larger text sizes).
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .center, spacing: 8) {
                        facts
                        Spacer(minLength: 4)
                        verdictLabel
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        facts
                        verdictLabel
                    }
                }
                if checking {
                    Text(post.checkLine)
                        .interactiveText(.caption)
                        .foregroundStyle(theme.ink2)
                        .fixedSize(horizontal: false, vertical: true)
                        .transition(.opacity)
                }
            }
        }
        .padding(.vertical, theme.platform == .phone ? 8 : 6)
    }

    /// Whether the dial (or checking) got this post wrong: a fake shared,
    /// or a real story waved away.
    private var isMistake: Bool {
        verdict.map { DoubtDialContent.isMistake(post, $0) } ?? false
    }

    /// Its surprise dots and what we wrote it as.
    private var facts: some View {
        HStack(alignment: .center, spacing: 8) {
            DoubtDialDots(surprise: post.surprise)
            Text(DoubtDialCopy.tag(post))
                .interactiveText(.caption)
                .foregroundStyle(post.isReal ? theme.ink2 : theme.accentText)
        }
    }

    /// The verdict word, and "Mistake" beside it when the setting got the
    /// post wrong (a glyph and a word in a well, never colour alone).
    @ViewBuilder
    private var verdictLabel: some View {
        if let verdict {
            HStack(alignment: .center, spacing: 6) {
                if isMistake {
                    DoubtDialMistakeTag()
                        .transition(.opacity)
                }
                Text(DoubtDialCopy.verdictWord(verdict))
                    .interactiveText(.caption)
                    .foregroundStyle(verdict.isShared ? theme.accentText : theme.ink2)
                    .transition(.opacity)
                    .id(verdict)
            }
        }
    }

    /// The accessibility sizes: the title, then its facts in words.
    private var textForm: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(post.title)
                .interactiveText(.body)
                .foregroundStyle(titleColor)
                .fixedSize(horizontal: false, vertical: true)
            Text(DoubtDialCopy.postTextLine(post, verdict: verdict))
                .interactiveText(.caption)
                .foregroundStyle(theme.ink2)
                .fixedSize(horizontal: false, vertical: true)
            if checking {
                Text(post.checkLine)
                    .interactiveText(.caption)
                    .foregroundStyle(theme.ink2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 8)
    }
}

/// The posts as a list with hairlines between them.
struct DoubtDialPostList: View {
    let posts: [DoubtDialPost]
    let verdict: (DoubtDialPost) -> DoubtDialVerdict?
    let checking: Bool
    @Environment(\.interactiveTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(posts.enumerated()), id: \.element.id) { index, post in
                if index > 0 {
                    Rectangle()
                        .fill(theme.increasedContrast ? theme.hairline : theme.wellEdge.opacity(0.6))
                        .frame(height: 1)
                        .accessibilityHidden(true)
                }
                DoubtDialPostRow(post: post, verdict: verdict(post), checking: checking)
            }
        }
    }
}

/// Once revealed: each setting's mistakes, under the dial's stop marks
/// (the same widths the dial's track uses), the current one lit. At the
/// accessibility sizes, where the dial is two buttons, a text table.
struct DoubtDialMistakesRow: View {
    let current: Int
    @Environment(\.interactiveTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(DoubtDialCopy.mistakesRowTitle)
                .interactiveText(.caption)
                .foregroundStyle(theme.ink2)
                .fixedSize(horizontal: false, vertical: true)
            if theme.usesTables {
                InteractiveTextTable(DoubtDialContent.mistakesByStop.enumerated().map {
                    InteractiveTextTable.Row(DoubtDialCopy.stopName($0.offset), DoubtDialCopy.mistakesCell($0.element))
                })
            } else {
                HStack(spacing: 0) {
                    ForEach(Array(DoubtDialContent.mistakesByStop.enumerated()), id: \.offset) { index, mistakes in
                        cell(mistakes, isCurrent: index == current)
                        if index < DoubtDialContent.mistakesByStop.count - 1 { Spacer(minLength: 0) }
                    }
                }
                .frame(maxWidth: .infinity)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(DoubtDialCopy.mistakesRowSpoken)
    }

    private func cell(_ mistakes: Int, isCurrent: Bool) -> some View {
        Text("\(mistakes)")
            .interactiveText(.calloutStrong)
            .monospacedDigit()
            .foregroundStyle(isCurrent ? Color.white : theme.ink)
            .frame(width: theme.minTarget - 8, height: theme.minTarget - 8)
            .background {
                Circle().fill(isCurrent ? theme.prominent : theme.raised)
            }
            .overlay {
                Circle().strokeBorder(isCurrent ? Color.white.opacity(theme.increasedContrast ? 0.9 : 0)
                                                : theme.wellEdge, lineWidth: 1)
            }
            .frame(width: theme.minTarget)
    }
}

/// The feed in one strip under the dial, least surprising first: each post
/// a cell with R (real) or F (fake) and its glyph (↗ shared, ⊘ waved
/// away), a ring and a ✕ under each the setting gets wrong, and the dial's
/// cut between the shared posts and the rest. Turning the dial moves the
/// cut and flips posts in place, all in view, with no scrolling to the
/// feed. Display only (the dial stays the one control); it never moves:
/// cells and the cut crossfade, with or without Reduce Motion. One
/// VoiceOver element, the strip in words ("Mistakes at this setting: …").
/// Not drawn at the accessibility sizes, where that line is text.
struct DoubtDialFeedStrip: View {
    let stop: Int
    @Environment(\.interactiveTheme) private var theme

    var body: some View {
        let posts = DoubtDialContent.posts
        let shared = DoubtDialContent.sharedCount(atStop: stop, checking: false)
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 0) {
                ForEach(Array(posts.enumerated()), id: \.element.id) { index, post in
                    cut(isHere: index == shared)
                    cell(post)
                }
                cut(isHere: shared == posts.count)
            }
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: theme.platform == .phone ? .infinity : 500, alignment: .leading)
            key
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(DoubtDialCopy.mistakesHere(atStop: stop))
    }

    /// The dial's cut: drawn in the one gap where the shared posts end.
    private func cut(isHere: Bool) -> some View {
        Capsule()
            .fill(theme.increasedContrast ? theme.ink : theme.accentText)
            .frame(width: 2.5)
            .frame(maxHeight: .infinity)
            .padding(.horizontal, theme.platform == .phone ? 2 : 3)
            .opacity(isHere ? 1 : 0)
    }

    private func cell(_ post: DoubtDialPost) -> some View {
        let verdict = DoubtDialContent.verdict(post, atStop: stop)
        let isMistake = DoubtDialContent.isMistake(post, verdict)
        let shape = RoundedRectangle(cornerRadius: 7, style: .continuous)
        return VStack(spacing: 3) {
            VStack(spacing: 1) {
                Text(DoubtDialCopy.stripLetter(post))
                    .interactiveText(.calloutStrong)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                // Both glyphs always there, one shown: a flip crossfades in
                // place and never changes the cell's layout (an inserted
                // glyph overlapped the letter while the card moved). One
                // height for ↗ and ⊘, so every cell and its ✕ line up.
                ZStack {
                    Image(systemName: DoubtDialGlyph.name(.shared))
                        .opacity(verdict.isShared ? 1 : 0)
                    Image(systemName: DoubtDialGlyph.name(.wavedAway))
                        .opacity(verdict.isShared ? 0 : 1)
                }
                .font(.system(size: theme.platform == .phone ? 10 : 9, weight: .bold))
                .frame(height: theme.platform == .phone ? 13 : 12)
            }
            .foregroundStyle(verdict.isShared ? theme.ink : theme.ink2)
            .padding(.vertical, 5)
            .frame(maxWidth: .infinity)
            .background(shape.fill(verdict.isShared ? theme.wash(theme.increasedContrast ? 0.4 : 0.3) : theme.raised))
            .overlay(shape.strokeBorder(isMistake ? theme.ink : (theme.increasedContrast ? theme.hairline : theme.wellEdge),
                                        lineWidth: isMistake ? 2 : 1))
            Image(systemName: "xmark")
                .font(.system(size: theme.platform == .phone ? 9 : 8, weight: .heavy))
                .frame(height: 10)
                .foregroundStyle(theme.ink)
                .opacity(isMistake ? 1 : 0)
        }
        .frame(minWidth: 0, maxWidth: theme.platform == .phone ? .infinity : 40)
    }

    /// What the letters and marks mean, in one caption.
    /// (One literal, so the glyphs are drawn as images in the line.)
    private var key: some View {
        let letters = DoubtDialCopy.stripKeyLetters
        let up = Image(systemName: DoubtDialGlyph.name(.shared))
        let away = Image(systemName: DoubtDialGlyph.name(.wavedAway))
        let cross = Image(systemName: "xmark")
        let shared = DoubtDialCopy.stripKeyShared
        let waved = DoubtDialCopy.stripKeyWavedAway
        let mistake = DoubtDialCopy.stripKeyMistake
        return Text("\(letters) \u{00B7} \(up) \(shared) \u{00B7} \(away) \(waved) \u{00B7} \(cross) \(mistake)")
            .interactiveText(.caption)
            .foregroundStyle(theme.ink2)
            .fixedSize(horizontal: false, vertical: true)
    }
}
