import SwiftUI
import DesignSystem

/// A control with a few discrete stops (the Doubt Dial's five settings, a
/// risk line's positions): the `ThresholdCounters` block's one knob.
///
/// - iPhone: the current stop's name over a track of stop marks, each a
///   44 pt target, with the end stops named under it; a selection haptic on
///   each change. At the accessibility sizes the track goes (decoration)
///   and two buttons step through the stops, the name in text.
/// - Mac: the track is in the Tab loop; ←/→ move a stop only while it has
///   focus (so A–D and 1–4 still answer the lesson's check); a click on a
///   mark picks it.
/// - VoiceOver: one adjustable element (swipe up or down), its value the
///   stop and what it does (`value`).
/// - Off (`isEnabled` false) until the card's prediction is locked: it says
///   "Make your guess first."
public struct StopControl: View {
    private let name: String
    private let stops: [String]
    private let selection: Int
    private let isEnabled: Bool
    private let value: (Int) -> String
    private let decreaseLabel: String
    private let increaseLabel: String
    private let onSelect: (Int) -> Void
    @Environment(\.interactiveTheme) private var theme

    /// - Parameters:
    ///   - name: what the control is ("The doubt dial"), for VoiceOver.
    ///   - stops: each stop's name, in order.
    ///   - value: what VoiceOver says at a stop (its name and its effect).
    ///   - decreaseLabel / increaseLabel: the accessibility-size buttons.
    public init(_ name: String, stops: [String], selection: Int, isEnabled: Bool = true,
                value: @escaping (Int) -> String, decreaseLabel: String, increaseLabel: String,
                onSelect: @escaping (Int) -> Void) {
        self.name = name
        self.stops = stops
        self.selection = min(max(selection, 0), max(stops.count - 1, 0))
        self.isEnabled = isEnabled
        self.value = value
        self.decreaseLabel = decreaseLabel
        self.increaseLabel = increaseLabel
        self.onSelect = onSelect
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: theme.rowSpacing) {
            Text(stops.isEmpty ? "" : stops[selection])
                .interactiveText(.heading)
                .foregroundStyle(isEnabled ? theme.ink : theme.ink3)
                .fixedSize(horizontal: false, vertical: true)
                .contentTransition(.identity)
            if theme.usesTables {
                stepButtons
            } else {
                track
                HStack(alignment: .firstTextBaseline) {
                    Text(stops.first ?? "")
                    Spacer(minLength: theme.chipSpacing)
                    Text(stops.last ?? "")
                        .multilineTextAlignment(.trailing)
                }
                .interactiveText(.caption)
                .foregroundStyle(theme.ink2)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(name)
        .accessibilityValue(isEnabled ? value(selection) : InteractiveShellCopy.guessFirst)
        .accessibilityAdjustableAction { direction in
            guard isEnabled else { return }
            switch direction {
            case .increment: step(1)
            case .decrement: step(-1)
            @unknown default: break
            }
        }
        #if os(iOS)
        .sensoryFeedback(.selection, trigger: selection)
        #endif
    }

    private func step(_ delta: Int) {
        let next = min(max(selection + delta, 0), stops.count - 1)
        if next != selection { onSelect(next) }
    }

    // MARK: The track

    private var track: some View {
        let mark = theme.minTarget
        return ZStack {
            Capsule()
                .fill(theme.increasedContrast ? theme.hairline : theme.wash(0.35))
                .frame(height: 3)
                .padding(.horizontal, mark / 2)
            HStack(spacing: 0) {
                ForEach(stops.indices, id: \.self) { index in
                    stopMark(index, size: mark)
                    if index < stops.count - 1 { Spacer(minLength: 0) }
                }
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: mark)
        .modifier(TrackKeyboard(isEnabled: isEnabled, onArrow: { arrow in step(arrow == .next ? 1 : -1) }))
    }

    private func stopMark(_ index: Int, size: CGFloat) -> some View {
        let selected = index == selection
        let dot: CGFloat = selected ? 18 : 12
        return ZStack {
            Circle()
                .fill(selected ? theme.prominent : theme.raised)
                .frame(width: dot, height: dot)
            Circle()
                .strokeBorder(selected ? Color.white.opacity(theme.increasedContrast ? 0.9 : 0.6)
                                       : (theme.increasedContrast ? theme.hairline : theme.ink3), lineWidth: selected ? 2 : 1.5)
                .frame(width: dot, height: dot)
        }
        .frame(width: size, height: size)
        .contentShape(Rectangle())
        .onTapGesture {
            guard isEnabled, index != selection else { return }
            onSelect(index)
        }
    }

    // MARK: The accessibility sizes

    private var stepButtons: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: theme.chipSpacing) { buttons }
            VStack(alignment: .leading, spacing: theme.chipSpacing) { buttons }
        }
    }

    @ViewBuilder private var buttons: some View {
        InteractiveActionButton(decreaseLabel, systemImage: "chevron.left",
                                isEnabled: isEnabled && selection > 0) { step(-1) }
        InteractiveActionButton(increaseLabel, systemImage: "chevron.right",
                                isEnabled: isEnabled && selection < stops.count - 1) { step(1) }
    }
}

/// The Mac: the track takes the keyboard (Tab), with Night's ring, and
/// ←/→ while focused. The iPhone: nothing (its marks are the targets).
private struct TrackKeyboard: ViewModifier {
    let isEnabled: Bool
    let onArrow: (InteractiveArrow) -> Void

    @ViewBuilder
    func body(content: Content) -> some View {
        #if os(macOS)
        content.modifier(InteractiveMacControl(shape: Capsule(), isFirst: false, isEnabled: isEnabled,
                                               onActivate: {}, onArrow: onArrow))
        #else
        content
        #endif
    }
}

/// Two or three options, one picked: a toggle like "What you see | What
/// the agent reads" or "Gender box: kept | deleted". Chips side by side
/// when they fit, else stacked; the picked one has a check. On the Mac
/// ←/→ move the pick while an option has focus; Space or Return picks.
public struct InteractiveSegmented<Option: Hashable & Sendable>: View {
    private let name: String
    private let options: [Option]
    private let title: (Option) -> String
    private let selection: Option
    private let isEnabled: Bool
    private let onSelect: (Option) -> Void
    @Environment(\.interactiveTheme) private var theme

    public init(_ name: String, options: [Option], selection: Option, isEnabled: Bool = true,
                title: @escaping (Option) -> String, onSelect: @escaping (Option) -> Void) {
        self.name = name
        self.options = options
        self.selection = selection
        self.isEnabled = isEnabled
        self.title = title
        self.onSelect = onSelect
    }

    public var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: theme.chipSpacing) { chips }
            VStack(alignment: .leading, spacing: theme.chipSpacing) { chips }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(name)
        #if os(iOS)
        .sensoryFeedback(.selection, trigger: selection)
        #endif
    }

    @ViewBuilder private var chips: some View {
        ForEach(Array(options.enumerated()), id: \.offset) { index, option in
            InteractiveChip(title(option), isSelected: option == selection, isEnabled: isEnabled, isFirst: index == 0,
                            onArrow: { arrow in move(arrow) }) {
                if option != selection { onSelect(option) }
            }
        }
    }

    private func move(_ arrow: InteractiveArrow) {
        guard let current = options.firstIndex(of: selection) else { return }
        let next = min(max(current + (arrow == .next ? 1 : -1), 0), options.count - 1)
        if next != current { onSelect(options[next]) }
    }
}

/// Back and Next for a `StepThrough`, with the step's position ("Step 2 of
/// 6"). Next is the main action; Back shows once there is a step behind.
/// On the Mac → and ← also step while either has focus.
public struct StepControls: View {
    private let steps: StepThrough
    private let nextTitle: String
    private let onBack: () -> Void
    private let onNext: () -> Void
    @Environment(\.interactiveTheme) private var theme

    public init(_ steps: StepThrough, nextTitle: String = InteractiveShellCopy.next,
                onBack: @escaping () -> Void, onNext: @escaping () -> Void) {
        self.steps = steps
        self.nextTitle = nextTitle
        self.onBack = onBack
        self.onNext = onNext
    }

    public var body: some View {
        let layout = theme.usesTables
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: theme.chipSpacing))
            : AnyLayout(HStackLayout(alignment: .center, spacing: theme.chipSpacing))
        layout {
            Text(steps.position)
                .interactiveText(.caption)
                .foregroundStyle(theme.ink2)
                .accessibilityHidden(true)
            if !theme.usesTables { Spacer(minLength: 0) }
            if steps.canGoBack {
                InteractiveActionButton(InteractiveShellCopy.back, systemImage: "chevron.left",
                                        onArrow: arrow) { onBack() }
            }
            InteractiveActionButton(nextTitle, systemImage: "chevron.right", prominent: true,
                                    isEnabled: steps.canGoNext, isFirst: true,
                                    accessibilityHint: steps.position, onArrow: arrow) { onNext() }
        }
        #if os(iOS)
        .sensoryFeedback(.selection, trigger: steps.index)
        #endif
    }

    private func arrow(_ arrow: InteractiveArrow) {
        switch arrow {
        case .next: if steps.canGoNext { onNext() }
        case .previous: if steps.canGoBack { onBack() }
        }
    }
}
