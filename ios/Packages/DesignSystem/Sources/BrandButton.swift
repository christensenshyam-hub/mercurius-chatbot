import SwiftUI

/// A button styled to the Mercurius brand.
///
/// Three styles:
/// - `.primary` — solid accent, for the main call-to-action on a screen.
/// - `.secondary` — subtle fill, for secondary actions.
/// - `.ghost` — text only with tinted background on press.
///
/// All styles respect Dynamic Type, Reduce Motion, and include a minimum
/// 44x44 hit target per Apple HIG.
public struct BrandButton: View {
    public enum Style {
        case primary
        case secondary
        case ghost
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
                .font(BrandFont.bodyEmphasized)
                .frame(maxWidth: .infinity, minHeight: 44)
                .padding(.horizontal, BrandSpacing.lg)
        }
        .buttonStyle(BrandButtonStyle(style: style))
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.5)
    }
}

private struct BrandButtonStyle: ButtonStyle {
    let style: BrandButton.Style
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(foreground(pressed: configuration.isPressed))
            .background(background(pressed: configuration.isPressed))
            .clipShape(RoundedRectangle(cornerRadius: BrandRadius.lg, style: .continuous))
            .scaleEffect(scale(pressed: configuration.isPressed))
            .animation(reduceMotion ? nil : .interactiveSpring(response: 0.25, dampingFraction: 0.8),
                       value: configuration.isPressed)
    }

    private func scale(pressed: Bool) -> CGFloat {
        guard !reduceMotion else { return 1 }
        return pressed ? 0.97 : 1
    }

    private func foreground(pressed: Bool) -> Color {
        switch style {
        case .primary: return .white
        case .secondary: return BrandColor.text
        case .ghost: return BrandColor.accent
        }
    }

    @ViewBuilder
    private func background(pressed: Bool) -> some View {
        switch style {
        case .primary:
            (pressed ? BrandColor.accentDark : BrandColor.accent)
        case .secondary:
            BrandColor.surfaceElevated
                .overlay(
                    RoundedRectangle(cornerRadius: BrandRadius.lg, style: .continuous)
                        .strokeBorder(BrandColor.border, lineWidth: 1)
                )
        case .ghost:
            (pressed ? BrandColor.accent.opacity(0.15) : Color.clear)
        }
    }
}
