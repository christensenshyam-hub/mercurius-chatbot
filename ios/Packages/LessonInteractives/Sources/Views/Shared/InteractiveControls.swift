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
            .buttonStyle(.plain)
            .disabled(!isEnabled)
        #endif
    }
}

// MARK: - A chip

/// One choice: a prediction, a rule, an option. On the iPhone a rounded
/// button at least 44 pt tall; on the Mac a 36 pt capsule. `prominent` with
/// white words and a check once picked (the check, not colour alone, says
/// it is picked); dimmed (still readable) when it can no longer be picked.
public struct InteractiveChip: View {
    private let title: String
    private let isSelected: Bool
    private let isEnabled: Bool
    private let isFirst: Bool
    private let accessibilityLabel: String?
    private let accessibilityHint: String?
    private let onArrow: ((InteractiveArrow) -> Void)?
    private let action: () -> Void
    @Environment(\.interactiveTheme) private var theme
    @State private var hovering = false

    public init(_ title: String, isSelected: Bool, isEnabled: Bool = true, isFirst: Bool = false,
                accessibilityLabel: String? = nil, accessibilityHint: String? = nil,
                onArrow: ((InteractiveArrow) -> Void)? = nil, action: @escaping () -> Void) {
        self.title = title
        self.isSelected = isSelected
        self.isEnabled = isEnabled
        self.isFirst = isFirst
        self.accessibilityLabel = accessibilityLabel
        self.accessibilityHint = accessibilityHint
        self.onArrow = onArrow
        self.action = action
    }

    public var body: some View {
        let shape = RoundedRectangle(cornerRadius: theme.platform == .phone ? 22 : 18, style: .continuous)
        let layout = theme.usesTables
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 2))
            : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: 6))
        layout {
            if isSelected {
                Image(systemName: "checkmark")
                    .font(.system(size: theme.platform == .phone ? 13 : 11, weight: .bold))
                    .accessibilityHidden(true)
            }
            Text(title)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
        }
        .interactiveText(.calloutStrong)
        .foregroundStyle(isSelected ? Color.white : (isEnabled ? theme.ink : theme.ink3))
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
        .onHover { hovering = $0 }
        .interactiveControl(shape: shape, isFirst: isFirst, isEnabled: isEnabled, onArrow: onArrow, action: action)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel ?? title)
        .accessibilityHint(isEnabled ? (accessibilityHint ?? "") : "")
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
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
    }
}
