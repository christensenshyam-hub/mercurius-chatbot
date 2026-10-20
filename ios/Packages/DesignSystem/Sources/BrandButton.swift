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

    #if os(macOS)
    /// The crisis view keeps the pre-Night button (palette only).
    @Environment(\.brandButtonClassic) private var classicOnMac
    #endif

    public var body: some View {
        #if os(macOS)
        // Night Studio on the Mac (SPEC.md §3.2): the same title, action and
        // enabled state, drawn as Night's prominent, secondary or text
        // button — unless the view asked for the classic look.
        if classicOnMac {
            Button(action: action) {
                Text(title)
                    .font(BrandFont.bodyEmphasized)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .padding(.horizontal, BrandSpacing.lg)
            }
            .buttonStyle(BrandButtonStyle(style: style))
            .disabled(!isEnabled)
            .opacity(isEnabled ? 1 : 0.5)
        } else {
            switch style {
            case .primary:
                NightPrimaryButton(title, action: action).disabled(!isEnabled)
            case .secondary:
                NightSecondaryButton(title, action: action).disabled(!isEnabled)
            case .ghost:
                NightTextButton(title, action: action).disabled(!isEnabled)
            }
        }
        #else
        Button(action: action) {
            Text(title)
                .font(BrandFont.bodyEmphasized)
                .frame(maxWidth: .infinity, minHeight: 44)
                .padding(.horizontal, BrandSpacing.lg)
        }
        .buttonStyle(BrandButtonStyle(style: style))
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.5)
        #endif
    }
}

#if os(macOS)
private struct BrandButtonClassicKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    /// Mac: `BrandButton` keeps its pre-Night look below this point. The
    /// crisis view sets it: it takes Night's palette and nothing else.
    var brandButtonClassic: Bool {
        get { self[BrandButtonClassicKey.self] }
        set { self[BrandButtonClassicKey.self] = newValue }
    }
}
#endif

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
        case .ghost: return BrandColor.accentText   // text-only: the text token (AUD-21)
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
