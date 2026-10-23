import SwiftUI
import DesignSystem

/// One counter: a printed number and what it counts ("Fakes you'd share").
public struct CounterTile: Equatable, Sendable {
    public let label: String
    public let value: String

    public init(_ label: String, value: Int) {
        self.label = label
        self.value = String(value)
    }

    public init(_ label: String, text: String) {
        self.label = label
        value = text
    }
}

/// The counters of `ThresholdCounters`: two or three tiles side by side
/// (a comparison's "=" or "≠" between two), or at the accessibility sizes
/// a text table. Numbers are always printed; a comparison is a symbol and
/// its word, never colour alone. VoiceOver reads the whole row as one
/// sentence (`summary`), which a card also announces when a stop changes.
public struct CounterTiles: View {
    private let tiles: [CounterTile]
    private let comparison: MeterComparison?
    @Environment(\.interactiveTheme) private var theme

    public init(_ tiles: [CounterTile], comparison: MeterComparison? = nil) {
        self.tiles = tiles
        self.comparison = comparison
    }

    /// The row in one sentence: "Fakes you'd share: 3. Real stories you'd
    /// wave away: 1."
    public static func summary(_ tiles: [CounterTile], comparison: MeterComparison? = nil) -> String {
        var line = tiles.map { "\($0.label): \($0.value)." }.joined(separator: " ")
        if let comparison { line += " \(comparison.spoken.prefix(1).uppercased() + comparison.spoken.dropFirst())." }
        return line
    }

    public var body: some View {
        Group {
            if theme.usesTables {
                InteractiveTextTable(tiles.map { InteractiveTextTable.Row($0.label, $0.value) }
                                     + (comparison.map { [InteractiveTextTable.Row($0.symbol, $0.spoken)] } ?? []))
            } else {
                HStack(alignment: .center, spacing: theme.chipSpacing) {
                    ForEach(Array(tiles.enumerated()), id: \.offset) { index, tile in
                        if index == 1, let comparison {
                            Text(comparison.symbol)
                                .interactiveText(.number)
                                .foregroundStyle(theme.accentText)
                                .accessibilityHidden(true)
                        }
                        tileView(tile)
                    }
                }
                // Every tile as tall as the tallest (a label that wraps
                // doesn't leave its neighbour short).
                .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Self.summary(tiles, comparison: comparison))
    }

    private func tileView(_ tile: CounterTile) -> some View {
        let shape = RoundedRectangle(cornerRadius: theme.platform == .phone ? BrandRadius.md : 10, style: .continuous)
        return VStack(alignment: .leading, spacing: 2) {
            Text(tile.value)
                .interactiveText(.number)
                .foregroundStyle(theme.ink)
                // A count changes at once: animated, two numbers overlap.
                .contentTransition(.identity)
            Text(tile.label)
                .interactiveText(.caption)
                .foregroundStyle(theme.ink2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(theme.raised, in: shape)
        .overlay(shape.strokeBorder(theme.increasedContrast ? theme.hairline : theme.wash(theme.lit ? 0.35 : 0.5),
                                    lineWidth: 1))
    }
}
