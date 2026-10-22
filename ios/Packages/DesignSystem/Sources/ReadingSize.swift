import SwiftUI

/// A reading size a learner picks for the Basics track ("A", "A+", "A++").
///
/// It is a floor, never a ceiling: the system's own Dynamic Type setting
/// still wins when it is larger. `.standard` adds nothing, so a learner who
/// keeps it sees exactly the app's usual sizes. The Mac has no Dynamic Type
/// (Night Studio's sizes are fixed), so the floor only changes anything on
/// iPhone and iPad.
public enum ReadingSize: String, CaseIterable, Sendable, Codable {
    case standard
    case larger
    case largest

    /// The smallest Dynamic Type size this choice allows; nil for none.
    public var minimumDynamicTypeSize: DynamicTypeSize? {
        switch self {
        case .standard: return nil
        case .larger: return .xLarge
        case .largest: return .xxxLarge
        }
    }

    /// The button's face: "A", "A+", "A++".
    public var symbol: String {
        switch self {
        case .standard: return "A"
        case .larger: return "A+"
        case .largest: return "A++"
        }
    }

    /// What VoiceOver reads for the button.
    public var spokenName: String {
        switch self {
        case .standard: return "Usual size"
        case .larger: return "Bigger"
        case .largest: return "Biggest"
        }
    }

    /// The size a sample line is drawn at on its button (Dynamic Type's
    /// own sizes, so the preview is what the learner will get).
    public var previewDynamicTypeSize: DynamicTypeSize {
        minimumDynamicTypeSize ?? .large
    }

    /// Whether a choice could still change anything, read from inside a
    /// view this floor already applies to (`current`, the floored size). At
    /// the largest floor's size or above, set by the system and not by this
    /// choice, every choice gives the same text, so the offer stays away.
    public func offersChoice(atFlooredSize current: DynamicTypeSize) -> Bool {
        let largest = ReadingSize.largest.minimumDynamicTypeSize ?? .xxxLarge
        guard current >= largest else { return true }
        // At or above the largest floor: only this choice's own floor can
        // have put it there (then the learner may want to come back down).
        guard let floor = minimumDynamicTypeSize else { return false }
        return current <= floor
    }

    /// The Dynamic Type size a view gets under this floor: the larger of the
    /// system's and the floor.
    public func applied(to system: DynamicTypeSize) -> DynamicTypeSize {
        guard let floor = minimumDynamicTypeSize else { return system }
        return max(system, floor)
    }
}

public extension View {
    /// Raise the Dynamic Type size to at least `size`'s floor. A larger
    /// system size is kept as it is.
    @ViewBuilder
    func readingSizeFloor(_ size: ReadingSize) -> some View {
        if let floor = size.minimumDynamicTypeSize {
            dynamicTypeSize(floor...)
        } else {
            self
        }
    }
}

// MARK: - The text-size offer

/// "Want the words bigger?" with three sample buttons (A, A+, A++), each
/// drawn at the size it gives. Tapping one applies it at once; the learner
/// sees the change and can tap another. "Keep this size" closes it.
public struct ReadingSizeOffer: View {
    let current: ReadingSize
    /// The question's detail line.
    let detail: String
    /// The closing button's title ("Keep this size", "Done").
    let dismissTitle: String
    let onChoose: (ReadingSize) -> Void
    let onDismiss: () -> Void

    public static let question = "Want the words bigger?"
    public static let firstTimeDetail = "Pick a size. You can change it any time with Text size on the Basics path."
    public static let keepTitle = "Keep this size"

    public init(
        current: ReadingSize,
        detail: String = ReadingSizeOffer.firstTimeDetail,
        dismissTitle: String = ReadingSizeOffer.keepTitle,
        onChoose: @escaping (ReadingSize) -> Void,
        onDismiss: @escaping () -> Void
    ) {
        self.current = current
        self.detail = detail
        self.dismissTitle = dismissTitle
        self.onChoose = onChoose
        self.onDismiss = onDismiss
    }

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    public var body: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.sm) {
            Text(Self.question)
                .font(BrandFont.bodyEmphasized)
                .foregroundStyle(BrandColor.text)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            Text(detail)
                .font(BrandFont.caption)
                .foregroundStyle(BrandColor.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            let row = dynamicTypeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(spacing: BrandSpacing.xs))
                : AnyLayout(HStackLayout(spacing: BrandSpacing.xs))
            row {
                ForEach(ReadingSize.allCases, id: \.self) { size in
                    sizeButton(size)
                }
            }
            Button(dismissTitle, action: onDismiss)
                .font(BrandFont.bodyEmphasized)
                .foregroundStyle(BrandColor.accentText)
                .frame(maxWidth: .infinity, minHeight: 44)
                .accessibilityIdentifier("basics.readingSize.keep")
        }
        .padding(BrandSpacing.md)
        .background(BrandColor.surface, in: RoundedRectangle(cornerRadius: BrandRadius.lg, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: BrandRadius.lg, style: .continuous)
                .strokeBorder(BrandColor.border, lineWidth: 1)
        )
    }

    private func sizeButton(_ size: ReadingSize) -> some View {
        let selected = size == current
        return Button { onChoose(size) } label: {
            VStack(spacing: 2) {
                Text(size.symbol)
                    .font(.system(.title3, design: .rounded).weight(.heavy))
                    // The sample is drawn at the size it gives.
                    .environment(\.dynamicTypeSize, size.previewDynamicTypeSize)
                if selected {
                    Image(systemName: "checkmark")
                        .font(.caption.weight(.bold))
                        .accessibilityHidden(true)
                }
            }
            .foregroundStyle(selected ? Color.white : BrandColor.text)
            .frame(maxWidth: .infinity, minHeight: 56)
            .background(
                RoundedRectangle(cornerRadius: BrandRadius.md, style: .continuous)
                    .fill(selected ? AnyShapeStyle(BrandGradient.merc) : AnyShapeStyle(BrandColor.surfaceElevated))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(size.spokenName)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier("basics.readingSize.\(size.rawValue)")
    }
}
