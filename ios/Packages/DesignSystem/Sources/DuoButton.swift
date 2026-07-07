import SwiftUI

/// A chunky, 3D "Duolingo-blueprint" button.
///
/// ADDITIVE — this does NOT replace `BrandButton`. The flat `BrandButton` stays
/// the default across chat, lessons, and settings (and every snapshot that pins
/// it). `DuoButton` is opted into only on the reward surfaces (the learning
/// path's START affordance, the gamified profile), where the playful press-down
/// feel is wanted.
///
/// The 3D look is a darker "plate" sitting `depth` points below a colored
/// "face." Pressing translates the face down onto the plate — the tactile
/// Duolingo press — instead of `BrandButton`'s subtle scale. Honors Reduce
/// Motion (no translate; the plate collapses to flat) and keeps a 44pt minimum
/// hit target.
public struct DuoButton: View {
    public enum Style {
        case primary    // brand gradient — the main CTA
        case secondary  // surface + border — a quieter action
        case reward     // warm gold — celebratory / "claim" moments
    }

    private let title: String
    private let style: Style
    private let isEnabled: Bool
    private let action: () -> Void

    public init(
        _ title: String,
        style: Style = .primary,
        isEnabled: Bool = true,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.style = style
        self.isEnabled = isEnabled
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            Text(title)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(DuoButtonStyle(style: style))
        .disabled(!isEnabled)
    }
}

/// The reusable `ButtonStyle` behind `DuoButton`. Exposed so callers can wrap a
/// custom label (an icon, a node) in the same chunky 3D treatment.
public struct DuoButtonStyle: ButtonStyle {
    private let style: DuoButton.Style
    private let depth: CGFloat

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isEnabled) private var isEnabled

    public init(style: DuoButton.Style = .primary, depth: CGFloat = 5) {
        self.style = style
        self.depth = depth
    }

    public func makeBody(configuration: Configuration) -> some View {
        let shape = RoundedRectangle(cornerRadius: BrandRadius.lg, style: .continuous)
        let pressed = configuration.isPressed
        // Reduce Motion collapses the 3D translate to a flat button.
        let activeDepth = reduceMotion ? 0 : depth

        return ZStack(alignment: .top) {
            // The darker base plate that gives the 3D edge.
            shape
                .fill(plateStyle)
                .offset(y: activeDepth)

            // The colored face. On press it drops onto the plate.
            configuration.label
                .font(BrandFont.roundedBodyEmphasized)
                .foregroundStyle(foreground)
                .frame(minHeight: 44)
                .padding(.horizontal, BrandSpacing.lg)
                .padding(.vertical, BrandSpacing.sm)
                .background(face(shape))
                .offset(y: pressed ? activeDepth : 0)
        }
        // Reserve the plate's protrusion so layout doesn't clip it.
        .padding(.bottom, activeDepth)
        // Under Reduce Motion the face can't translate, so dip the whole button
        // on press to still acknowledge the tap. Disabled state stays dimmed.
        .opacity(isEnabled ? (reduceMotion && pressed ? 0.82 : 1) : 0.55)
        .animation(reduceMotion ? nil : .interactiveSpring(response: 0.16, dampingFraction: 0.68),
                   value: pressed)
    }

    @ViewBuilder
    private func face(_ shape: RoundedRectangle) -> some View {
        switch style {
        case .primary:
            shape.fill(BrandGradient.merc)
        case .secondary:
            shape
                .fill(BrandColor.surface)
                .overlay(shape.strokeBorder(BrandColor.border, lineWidth: 1.5))
        case .reward:
            shape.fill(
                LinearGradient(
                    colors: [BrandColor.xpGold, BrandColor.xpGoldDeep],
                    startPoint: .top, endPoint: .bottom
                )
            )
        }
    }

    private var plateStyle: AnyShapeStyle {
        switch style {
        case .primary:   return AnyShapeStyle(BrandColor.accentDark)
        case .secondary: return AnyShapeStyle(BrandColor.border)
        case .reward:    return AnyShapeStyle(BrandColor.xpGoldDeep)
        }
    }

    private var foreground: Color {
        switch style {
        case .primary:   return .white
        case .secondary: return BrandColor.text
        case .reward:    return Color(red: 0x4A / 255, green: 0x2E / 255, blue: 0x00 / 255)
        }
    }
}

#if DEBUG
#Preview("DuoButton") {
    VStack(spacing: BrandSpacing.lg) {
        DuoButton("Start", style: .primary) {}
        DuoButton("Review", style: .secondary) {}
        DuoButton("Claim reward", style: .reward) {}
        DuoButton("Disabled", style: .primary, isEnabled: false) {}
    }
    .padding(BrandSpacing.xl)
    .background(BrandColor.background)
}
#endif
