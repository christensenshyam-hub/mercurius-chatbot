import SwiftUI
import DesignSystem

/// The prediction: a question and two to four chips. One tap locks a guess
/// in (it can't be changed); the picked chip keeps its check and the others
/// dim, still readable. In spoiled mode a card doesn't draw this at all.
///
/// - iPhone: chips side by side when they fit, else one under another;
///   44 pt or taller; a selection haptic on the lock.
/// - Mac: every chip is in the Tab loop (Tab and Shift-Tab move between
///   them); Space or Return locks it. Return stays the chip's while it has
///   focus, so the lesson's check never locks in from it.
/// - VoiceOver: the question is a header; each chip says its choice, and
///   once locked "Your guess, locked in".
public struct PredictChips<Choice: Hashable & Sendable>: View {
    private let prompt: String
    private let machine: PredictReveal<Choice>
    private let title: (Choice) -> String
    private let onLock: (Choice) -> Void
    @Environment(\.interactiveTheme) private var theme

    public init(_ prompt: String, machine: PredictReveal<Choice>, title: @escaping (Choice) -> String,
                onLock: @escaping (Choice) -> Void) {
        self.prompt = prompt
        self.machine = machine
        self.title = title
        self.onLock = onLock
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: theme.rowSpacing) {
            Text(prompt)
                .interactiveText(.heading)
                .foregroundStyle(theme.ink)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            chips
        }
        #if os(iOS)
        .sensoryFeedback(.selection, trigger: machine.guess)
        #endif
    }

    @ViewBuilder private var chips: some View {
        if theme.usesTables {
            VStack(alignment: .leading, spacing: theme.chipSpacing) { chipViews }
        } else {
            NightFlow(spacing: theme.chipSpacing, lineSpacing: theme.chipSpacing) { chipViews }
        }
    }

    @ViewBuilder private var chipViews: some View {
        ForEach(Array(machine.choices.enumerated()), id: \.offset) { index, choice in
            let picked = machine.guess == choice
            InteractiveChip(title(choice), isSelected: picked, isEnabled: machine.canLock, isFirst: index == 0,
                            accessibilityLabel: title(choice),
                            accessibilityHint: InteractiveShellCopy.lockHint) {
                onLock(choice)
            }
            .accessibilityValue(picked ? InteractiveShellCopy.lockedValue : "")
        }
    }
}

/// The reveal: the guess beside what happened, never a score. In spoiled
/// mode only what happened. One VoiceOver element that reads both
/// (`InteractiveRevealLines.spoken`); a card announces it as it appears
/// and marks it `.id(InteractiveScrollID.reveal)`.
public struct RevealBox: View {
    private let lines: InteractiveRevealLines
    private let takeaway: String?
    @Environment(\.interactiveTheme) private var theme

    public init(_ lines: InteractiveRevealLines, takeaway: String? = nil) {
        self.lines = lines
        self.takeaway = takeaway
    }

    public var body: some View {
        let shape = RoundedRectangle(cornerRadius: theme.platform == .phone ? BrandRadius.lg : 12, style: .continuous)
        VStack(alignment: .leading, spacing: theme.rowSpacing) {
            if let guess = lines.guess {
                row(InteractiveShellCopy.youGuessed, guess)
            }
            row(InteractiveShellCopy.whatHappened, lines.result)
            if let takeaway {
                Text(takeaway)
                    .interactiveText(.heading)
                    .foregroundStyle(theme.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(theme.platform == .phone ? BrandSpacing.md : 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.wash(0.14), in: shape)
        .overlay(shape.strokeBorder(theme.increasedContrast ? theme.hairline : theme.wash(0.45), lineWidth: 1))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(([lines.spoken] + (takeaway.map { [$0] } ?? [])).joined(separator: " "))
    }

    private func row(_ label: String, _ text: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label.uppercased())
                .interactiveText(.eyebrow)
                .foregroundStyle(theme.accentText)
                // Wraps at AX5 on an SE everywhere: the device already did,
                // an ImageRenderer render truncated it ("YOU GUESS…").
                .fixedSize(horizontal: false, vertical: true)
            Text(text)
                .interactiveText(.callout)
                .foregroundStyle(theme.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// A label on the canvas, never a footnote: "A made-up feed…", "Example,
/// written for this lesson…". Reading text (`ink2`), with an info glyph
/// that goes at the accessibility sizes.
public struct LabelLine: View {
    private let text: String
    @Environment(\.interactiveTheme) private var theme

    public init(_ label: InteractiveLabel) {
        text = label.text
    }

    public init(_ text: String) {
        self.text = text
    }

    public var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            if !theme.usesTables {
                Image(systemName: "info.circle")
                    .font(.system(size: theme.platform == .phone ? 12 : 11, weight: .semibold))
                    .accessibilityHidden(true)
            }
            Text(text)
                .interactiveText(.caption)
                .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(theme.ink2)
        .accessibilityElement(children: .combine)
    }
}

/// Rows of a label and a value, for the accessibility sizes, where a chart
/// or grid would break: the label above its value, both wrapping, so
/// nothing scrolls sideways. One VoiceOver element per row.
public struct InteractiveTextTable: View {
    public struct Row: Equatable, Sendable {
        public let label: String
        public let value: String

        public init(_ label: String, _ value: String) {
            self.label = label
            self.value = value
        }
    }

    private let rows: [Row]
    @Environment(\.interactiveTheme) private var theme

    public init(_ rows: [Row]) {
        self.rows = rows
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: theme.rowSpacing) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                VStack(alignment: .leading, spacing: 2) {
                    Text(row.label)
                        .interactiveText(.caption)
                        .foregroundStyle(theme.ink2)
                    Text(row.value)
                        .interactiveText(.calloutStrong)
                        .foregroundStyle(theme.ink)
                }
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(row.label): \(row.value)")
            }
        }
    }
}
