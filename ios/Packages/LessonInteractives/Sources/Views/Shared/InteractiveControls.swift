import SwiftUI
import DesignSystem

// MARK: - The lesson's keys (the Mac)

/// The lesson's key routing, as a card's controls see it (ChatFeature's
/// `NightCheckKeyRouter` on the Mac): while a card control has the keyboard
/// it holds Return, so the lesson's waiting check doesn't lock in from it;
/// A–D, 1–4 and ↑/↓ still answer the check. When the check gets a pick
/// (`checkPicks` changes) a control lets go of the keyboard.
@MainActor
public protocol InteractiveKeyRouting: AnyObject {
    func hold(_ id: UUID, _ holds: Bool)
    var checkPicks: Int { get }
}

private struct InteractiveKeyRouterKey: EnvironmentKey {
    static let defaultValue: (any InteractiveKeyRouting)? = nil
}

private struct InteractiveFocusFirstKey: EnvironmentKey {
    static let defaultValue = 0
}

extension EnvironmentValues {
    /// The lesson's key routing (nil outside a Mac lesson: the gallery, the
    /// iPhone).
    public var interactiveKeyRouter: (any InteractiveKeyRouting)? {
        get { self[InteractiveKeyRouterKey.self] }
        set { self[InteractiveKeyRouterKey.self] = newValue }
    }

    /// Bumped by the Mac's shell when "Try it" opens the card from the
    /// keyboard: the card's first control (`isFirst`) takes the keyboard.
    public var interactiveFocusFirst: Int {
        get { self[InteractiveFocusFirstKey.self] }
        set { self[InteractiveFocusFirstKey.self] = newValue }
    }
}

/// An arrow key a focused control may use. ↑/↓ reach a control only while
/// the lesson has no waiting check (the check takes them first), so cards
/// use ←/→ and treat ↑/↓ as the same moves.
public enum InteractiveArrow: Sendable {
    case previous, next
}

#if os(macOS)
/// A card control on the Mac, the tokenizer's contract: in the Tab loop
/// whatever the Full Keyboard Access setting, Night's ring when it has the
/// keyboard, Space or Return activates it, arrows act only while it has
/// focus, a click acts without keeping the keyboard (so the check's keys
/// keep working), and it holds Return from the lesson's check while
/// focused.
struct InteractiveMacControl<S: InsettableShape>: ViewModifier {
    let shape: S
    let isFirst: Bool
    let isEnabled: Bool
    let onActivate: () -> Void
    let onArrow: ((InteractiveArrow) -> Void)?

    @Environment(\.interactiveKeyRouter) private var router
    @Environment(\.interactiveFocusFirst) private var focusFirst
    @Environment(\.interactiveTheme) private var theme
    @FocusState private var focused: Bool
    @State private var holder = UUID()

    func body(content: Content) -> some View {
        content
            .contentShape(shape)
            .onTapGesture {
                guard isEnabled else { return }
                onActivate()
                if focused { focused = false }
            }
            .focusable(isEnabled, interactions: .edit)
            .focused($focused)
            .focusEffectDisabled()
            .overlay {
                if focused {
                    shape.inset(by: -3 - theme.focusRingWidth / 2)
                        .stroke(theme.focusRing, lineWidth: theme.focusRingWidth)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
            }
            .onKeyPress(keys: [.space, .return], phases: .down) { _ in
                guard isEnabled else { return .ignored }
                onActivate()
                return .handled
            }
            .onKeyPress(keys: [.leftArrow, .rightArrow, .upArrow, .downArrow], phases: .down) { press in
                guard isEnabled, let onArrow else { return .ignored }
                onArrow(press.key == .leftArrow || press.key == .upArrow ? .previous : .next)
                return .handled
            }
            .onChange(of: focused) { _, now in router?.hold(holder, now) }
            .onChange(of: router?.checkPicks) { _, _ in if focused { focused = false } }
            .onChange(of: focusFirst) { _, _ in if isFirst && isEnabled { focused = true } }
            .onDisappear { router?.hold(holder, false) }
    }
}
#endif

#if os(iOS)
/// The iPhone's card controls draw their own off state (`ink3` words, no
/// faded fill), so their button style must not fade them again: `.plain`
/// dims a disabled button's whole label to about half, which took a
/// locked guess's white words on `prominent` to 4.18:1 and the other
/// choice's to 2.56:1. Pressed, the label dims a little for a moment.
struct InteractiveSteadyButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.8 : 1)
    }
}
#endif

extension View {
    /// This view as one card control: a button on the iPhone (the caller
    /// sizes it to `theme.minTarget`), a keyboard control on the Mac
    /// (`InteractiveMacControl`). `onArrow`: the Mac's ←/→ while focused.
    @ViewBuilder
    func interactiveControl<S: InsettableShape>(shape: S, isFirst: Bool = false, isEnabled: Bool = true,
                                                onArrow: ((InteractiveArrow) -> Void)? = nil,
                                                action: @escaping () -> Void) -> some View {
        #if os(macOS)
        modifier(InteractiveMacControl(shape: shape, isFirst: isFirst, isEnabled: isEnabled,
                                       onActivate: action, onArrow: onArrow))
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { if isEnabled { action() } }
        #else
        Button(action: action) { self.contentShape(shape) }
            .buttonStyle(InteractiveSteadyButtonStyle())
            .disabled(!isEnabled)
        #endif
    }
}

// MARK: - A chip

/// One choice: a prediction, a rule, an option. On the iPhone a rounded
/// button at least 44 pt tall; on the Mac a 36 pt capsule. `prominent` with
/// white words and a check once picked (the check, not colour alone, says
/// it is picked); dimmed (still readable) when it can't be picked yet.
///
/// `isLocked`: the choice is settled (a locked-in guess), so the chip is no
/// longer a control. It draws as itself, not as a disabled button (on the
/// iPhone a disabled button dims its words below 4.5:1 just when the
/// student compares their guess with the reveal): the pick keeps white on
/// `prominent`, the others read in `ink2` on `raised`, and VoiceOver hears
/// a choice ("selected" on the pick), not a dimmed button.
public struct InteractiveChip: View {
    /// A chip's words' colour role (pure, so a test holds the rule).
    public enum Ink: Equatable, Sendable { case white, ink, ink2, ink3 }

    public static func ink(isSelected: Bool, isEnabled: Bool, isLocked: Bool) -> Ink {
        if isSelected { return .white }
        if isLocked { return .ink2 }
        return isEnabled ? .ink : .ink3
    }

    private let title: String
    private let isSelected: Bool
    private let isEnabled: Bool
    private let isLocked: Bool
    private let isFirst: Bool
    private let accessibilityLabel: String?
    private let accessibilityHint: String?
    private let onArrow: ((InteractiveArrow) -> Void)?
    private let action: () -> Void
    @Environment(\.interactiveTheme) private var theme
    @State private var hovering = false

    public init(_ title: String, isSelected: Bool, isEnabled: Bool = true, isLocked: Bool = false,
                isFirst: Bool = false, accessibilityLabel: String? = nil, accessibilityHint: String? = nil,
                onArrow: ((InteractiveArrow) -> Void)? = nil, action: @escaping () -> Void) {
        self.title = title
        self.isSelected = isSelected
        self.isEnabled = isEnabled && !isLocked
        self.isLocked = isLocked
        self.isFirst = isFirst
        self.accessibilityLabel = accessibilityLabel
        self.accessibilityHint = accessibilityHint
        self.onArrow = onArrow
        self.action = action
    }

    public var body: some View {
        if isLocked {
            face
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(accessibilityLabel ?? title)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
        } else {
            face
                .onHover { hovering = $0 }
                .interactiveControl(shape: shape, isFirst: isFirst, isEnabled: isEnabled, onArrow: onArrow,
                                    action: action)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(accessibilityLabel ?? title)
                .accessibilityHint(isEnabled ? (accessibilityHint ?? "") : "")
                .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
                // The off state on the element VoiceOver and XCUITest see
                // ("dimmed"), not only on the button inside it. Nothing
                // fades: the colours draw the off state
                // (`InteractiveSteadyButtonStyle`). A locked chip (above) is
                // no longer a control, so it isn't "dimmed" either.
                .disabled(!isEnabled)
        }
    }

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: theme.platform == .phone ? 22 : 18, style: .continuous)
    }

    private var inkColor: Color {
        switch Self.ink(isSelected: isSelected, isEnabled: isEnabled, isLocked: isLocked) {
        case .white: return .white
        case .ink: return theme.ink
        case .ink2: return theme.ink2
        case .ink3: return theme.ink3
        }
    }

    private var face: some View {
        let layout = theme.usesTables
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 2))
            : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: 6))
        return layout {
            if isSelected {
                // On the iPhone the check grows with the text (13 pt at the
                // default size, as before), so it isn't a speck at AX5.
                Image(systemName: "checkmark")
                    .font(theme.platform == .phone ? .system(.footnote, design: .rounded, weight: .bold)
                                                   : .system(size: 11, weight: .bold))
                    .accessibilityHidden(true)
            }
            Text(title)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
        }
        .interactiveText(.calloutStrong)
        .foregroundStyle(inkColor)
        .padding(.horizontal, theme.platform == .phone ? BrandSpacing.lg : 14)
        .padding(.vertical, theme.platform == .phone ? BrandSpacing.sm + 2 : 6)
        .frame(minHeight: theme.minTarget)
        .background {
            shape.fill(isSelected ? theme.prominent : theme.raised)
            if !isSelected && hovering && isEnabled { shape.fill(theme.wash(0.08)) }
        }
        .overlay {
            if isSelected {
                if theme.increasedContrast { shape.strokeBorder(Color.white.opacity(0.9), lineWidth: 1) }
            } else {
                shape.strokeBorder(theme.wellEdge, lineWidth: 1)
            }
        }
    }
}

// MARK: - An action button

/// A card's action ("Show me", "Check first", "Next", "Write it again"):
/// `prominent` with white words for the one main action, else a raised
/// capsule with accent words. 44 pt on the iPhone, 36 pt on the Mac.
public struct InteractiveActionButton: View {
    private let title: String
    private let systemImage: String?
    private let prominent: Bool
    private let isEnabled: Bool
    private let isFirst: Bool
    private let accessibilityHint: String?
    private let onArrow: ((InteractiveArrow) -> Void)?
    private let action: () -> Void
    @Environment(\.interactiveTheme) private var theme
    @State private var hovering = false

    public init(_ title: String, systemImage: String? = nil, prominent: Bool = false, isEnabled: Bool = true,
                isFirst: Bool = false, accessibilityHint: String? = nil,
                onArrow: ((InteractiveArrow) -> Void)? = nil, action: @escaping () -> Void) {
        self.title = title
        self.systemImage = systemImage
        self.prominent = prominent
        self.isEnabled = isEnabled
        self.isFirst = isFirst
        self.accessibilityHint = accessibilityHint
        self.onArrow = onArrow
        self.action = action
    }

    public var body: some View {
        let shape = Capsule()
        // Off, the main action is drawn as a plain one with `ink3` words
        // (no faded fill, so its words still read).
        let filled = prominent && isEnabled
        HStack(spacing: 6) {
            // The icon is decoration: it goes at the accessibility sizes.
            if let systemImage, !theme.usesTables {
                Image(systemName: systemImage)
                    .accessibilityHidden(true)
            }
            Text(title)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
        }
        .interactiveText(.calloutStrong)
        .foregroundStyle(filled ? Color.white : (isEnabled ? theme.accentText : theme.ink3))
        .padding(.horizontal, theme.platform == .phone ? BrandSpacing.lg : 16)
        .padding(.vertical, theme.platform == .phone ? BrandSpacing.sm : 6)
        .frame(minHeight: theme.minTarget)
        .background {
            shape.fill(filled ? theme.prominent : theme.raised)
            if hovering && isEnabled { shape.fill(theme.wash(filled ? 0.12 : 0.08)) }
        }
        .overlay {
            if filled {
                if theme.increasedContrast { shape.strokeBorder(Color.white.opacity(0.9), lineWidth: 1) }
            } else {
                shape.strokeBorder(theme.wellEdge, lineWidth: 1)
            }
        }
        .onHover { hovering = $0 }
        .interactiveControl(shape: shape, isFirst: isFirst, isEnabled: isEnabled, onArrow: onArrow, action: action)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityHint(accessibilityHint ?? "")
        .accessibilityAddTraits(.isButton)
        // As the chip: "dimmed" on the outer element, with no fade.
        .disabled(!isEnabled)
    }
}
