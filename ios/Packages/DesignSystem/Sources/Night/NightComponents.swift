#if os(macOS)
import SwiftUI

// MARK: - Eyebrow

/// The one eyebrow style (§3.1): Lexend SemiBold 12, uppercase, +1.2, with an
/// optional 11 pt symbol 6 pt before it. `accentText` by default; `ink3` for
/// neutral ones; white 92% on the hero.
public struct NightEyebrow: View {
    private let text: String
    private let systemImage: String?
    private let color: Color

    public init(_ text: String, systemImage: String? = nil, color: Color = Night.accentText) {
        self.text = text
        self.systemImage = systemImage
        self.color = color
    }

    public var body: some View {
        HStack(spacing: 6) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: 11, weight: .bold))
                    .accessibilityHidden(true)
            }
            Text(text.uppercased())
                .nightFont(.eyebrow)
        }
        .foregroundStyle(color)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(text)
    }
}

// MARK: - Buttons (§3.2, §4.2–4.4)

/// The sizes of Night's capsule buttons: 36 pt, or 44 on Today's hero and
/// the complete card.
public enum NightButtonSize: Sendable {
    case regular
    case large

    var minHeight: CGFloat { self == .large ? 44 : 36 }
    var horizontalPadding: CGFloat { self == .large ? 22 : 18 }
}

/// The one prominent button per screen: white Lexend on opaque `prominent`
/// (never glass, so its contrast is computed), `prominentHover` under the
/// pointer, `prominentPressed` while pressed. Disabled: `surfaceRaised` with
/// an `ink3` label. No scale on press.
public struct NightPrimaryButtonStyle: ButtonStyle {
    private let size: NightButtonSize

    public init(size: NightButtonSize = .regular) {
        self.size = size
    }

    public func makeBody(configuration: Configuration) -> some View {
        NightCapsuleButtonBody(configuration: configuration, size: size, kind: .primary)
    }
}

/// A secondary action: `ink` Lexend on floating chrome.
public struct NightSecondaryButtonStyle: ButtonStyle {
    private let size: NightButtonSize

    public init(size: NightButtonSize = .regular) {
        self.size = size
    }

    public func makeBody(configuration: Configuration) -> some View {
        NightCapsuleButtonBody(configuration: configuration, size: size, kind: .secondary)
    }
}

/// The hero's button: a white capsule with a `prominent` label (7.90:1).
public struct NightOnHeroButtonStyle: ButtonStyle {
    private let size: NightButtonSize

    public init(size: NightButtonSize = .large) {
        self.size = size
    }

    public func makeBody(configuration: Configuration) -> some View {
        NightCapsuleButtonBody(configuration: configuration, size: size, kind: .onHero)
    }
}

/// A text-only action ("Learning Path", "Not now"): `headline` in `color`,
/// underlined under the pointer.
public struct NightTextButtonStyle: ButtonStyle {
    private let color: Color

    public init(color: Color = Night.accentText) {
        self.color = color
    }

    public func makeBody(configuration: Configuration) -> some View {
        NightTextButtonBody(configuration: configuration, color: color)
    }
}

private struct NightCapsuleButtonBody: View {
    enum Kind { case primary, secondary, onHero }

    let configuration: ButtonStyleConfiguration
    let size: NightButtonSize
    let kind: Kind
    @Environment(\.isEnabled) private var isEnabled
    @State private var hovering = false

    var body: some View {
        configuration.label
            .nightFont(.headline)
            .lineLimit(1)
            .foregroundStyle(foreground)
            .padding(.horizontal, size.horizontalPadding)
            .frame(minHeight: size.minHeight)
            .background { background }
            .contentShape(Capsule())
            .onHover { hovering = $0 }
    }

    private var foreground: Color {
        guard isEnabled else { return Night.ink3 }
        switch kind {
        case .primary: return .white
        case .secondary: return Night.ink
        case .onHero: return Night.prominent
        }
    }

    @ViewBuilder private var background: some View {
        let shape = Capsule()
        if !isEnabled {
            shape.fill(Night.surfaceRaised)
        } else {
            switch kind {
            case .primary:
                shape.fill(configuration.isPressed ? Night.prominentPressed
                           : (hovering ? Night.prominentHover : Night.prominent))
            case .secondary:
                Color.clear
                    .nightChrome(in: shape, interactive: true)
                    .overlay {
                        shape.fill(configuration.isPressed ? Night.ink.opacity(0.08)
                                   : (hovering ? Night.lumen.opacity(NightPalette.Tint.hover) : .clear))
                    }
            case .onHero:
                shape.fill(Color.white)
                    .overlay {
                        shape.fill(configuration.isPressed ? Night.ink.opacity(0.08)
                                   : (hovering ? Night.ink.opacity(0.04) : .clear))
                    }
            }
        }
    }
}

private struct NightTextButtonBody: View {
    let configuration: ButtonStyleConfiguration
    let color: Color
    @Environment(\.isEnabled) private var isEnabled
    @State private var hovering = false

    var body: some View {
        configuration.label
            .nightFont(.headline)
            .foregroundStyle(isEnabled ? color : Night.ink3)
            .underline(hovering && isEnabled)
            .opacity(configuration.isPressed ? 0.7 : 1)
            .frame(minHeight: 36)
            .contentShape(Rectangle())
            .onHover { hovering = $0 }
    }
}

/// A clickable lit card or row: Night's hover (§4.2) and, while pressed, an
/// `ink` 8% overlay on its shape (§4.3). No scale, so nothing moves under
/// Reduce Motion. Pair with `nightFocusRing` on the same shape.
public struct NightCardButtonStyle: ButtonStyle {
    private let cornerRadius: CGFloat

    public init(cornerRadius: CGFloat = Night.Radius.card) {
        self.cornerRadius = cornerRadius
    }

    public func makeBody(configuration: Configuration) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        return configuration.label
            .overlay {
                shape.fill(Night.ink.opacity(configuration.isPressed ? 0.08 : 0))
                    .allowsHitTesting(false)
            }
            .nightHover(cornerRadius: cornerRadius)
            .contentShape(shape)
    }
}

/// Night's prominent button with its focus ring: the screen's one.
public struct NightPrimaryButton: View {
    private let title: String
    private let systemImage: String?
    private let size: NightButtonSize
    private let action: () -> Void

    public init(_ title: String, systemImage: String? = nil, size: NightButtonSize = .regular,
                action: @escaping () -> Void) {
        self.title = title
        self.systemImage = systemImage
        self.size = size
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            NightButtonLabel(title: title, systemImage: systemImage)
        }
        .buttonStyle(NightPrimaryButtonStyle(size: size))
        .nightFocusRing(Capsule())
    }
}

/// Night's secondary button with its focus ring.
public struct NightSecondaryButton: View {
    private let title: String
    private let systemImage: String?
    private let size: NightButtonSize
    private let action: () -> Void

    public init(_ title: String, systemImage: String? = nil, size: NightButtonSize = .regular,
                action: @escaping () -> Void) {
        self.title = title
        self.systemImage = systemImage
        self.size = size
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            NightButtonLabel(title: title, systemImage: systemImage, leading: true)
        }
        .buttonStyle(NightSecondaryButtonStyle(size: size))
        .nightFocusRing(Capsule())
    }
}

/// Night's text button with its focus ring.
public struct NightTextButton: View {
    private let title: String
    private let color: Color
    private let action: () -> Void

    public init(_ title: String, color: Color = Night.accentText, action: @escaping () -> Void) {
        self.title = title
        self.color = color
        self.action = action
    }

    public var body: some View {
        Button(title, action: action)
            .buttonStyle(NightTextButtonStyle(color: color))
            .nightFocusRing(RoundedRectangle(cornerRadius: 6, style: .continuous), color: color)
    }
}

/// A button's title and its symbol: trailing (an arrow) by default, leading
/// for a secondary action's icon.
public struct NightButtonLabel: View {
    private let title: String
    private let systemImage: String?
    private let leading: Bool

    public init(title: String, systemImage: String? = nil, leading: Bool = false) {
        self.title = title
        self.systemImage = systemImage
        self.leading = leading
    }

    public var body: some View {
        HStack(spacing: 8) {
            if leading, let systemImage { symbol(systemImage) }
            Text(title)
            if !leading, let systemImage { symbol(systemImage) }
        }
    }

    private func symbol(_ name: String) -> some View {
        Image(systemName: name)
            .font(.system(size: 13, weight: .semibold))
            .accessibilityHidden(true)
    }
}

/// A 30 pt circle of floating chrome with a 14 pt semibold symbol in `ink`.
/// Always labelled for VoiceOver and with a help tag.
public struct NightIconButton: View {
    private let systemName: String
    private let label: String
    private let help: String
    private let action: () -> Void
    @State private var hovering = false

    public init(systemName: String, label: String, help: String? = nil, action: @escaping () -> Void) {
        self.systemName = systemName
        self.label = label
        self.help = help ?? label
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Night.ink)
                .frame(width: 30, height: 30)
                .nightChrome(in: Circle(), interactive: true)
                .overlay { Circle().fill(Night.lumen.opacity(hovering ? NightPalette.Tint.hover : 0)) }
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .nightFocusRing(Circle())
        .help(help)
        .accessibilityLabel(label)
    }
}

// MARK: - The weekly rhythm ring

/// One arc per lesson in the weekly goal, with 3.5% gaps: unlit arcs in
/// `hairline`, lit ones in the brand light (flat `accentText` under Increase
/// Contrast). No glow. Hidden from VoiceOver: its card says the count.
public struct NightRhythmRing: View {
    private let done: Int
    private let goal: Int
    private let lineWidth: CGFloat
    private let showsLabel: Bool
    @NightSettings private var night

    public init(done: Int, goal: Int, lineWidth: CGFloat = 6, showsLabel: Bool = true) {
        self.done = done
        self.goal = goal
        self.lineWidth = lineWidth
        self.showsLabel = showsLabel
    }

    public var body: some View {
        let segments = max(goal, 1)
        let gap = 0.035
        let lit = Night.progressLight(increasedContrast: night.increasedContrast)
        ZStack {
            ZStack {
                ForEach(0..<segments, id: \.self) { index in
                    let start = Double(index) / Double(segments) + gap / 2
                    let end = Double(index + 1) / Double(segments) - gap / 2
                    Circle()
                        .trim(from: CGFloat(start), to: CGFloat(end))
                        .stroke(Night.hairline, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                    if index < done {
                        Circle()
                            .trim(from: CGFloat(start), to: CGFloat(end))
                            .stroke(lit, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                    }
                }
            }
            .rotationEffect(.degrees(-90))
            .padding(lineWidth / 2)
            if showsLabel {
                Text("\(min(done, goal))/\(goal)")
                    .font(NightType.lexend(14, semibold: true))
                    .monospacedDigit()
                    .foregroundStyle(Night.ink)
            }
        }
        .accessibilityHidden(true)
    }
}

// MARK: - Merc with his lamp

/// Merc with a soft lamp of `lumen` behind him (none under Increase
/// Contrast). Still under Reduce Motion. Decoration: hidden from VoiceOver.
public struct NightMercLamp: View {
    private let state: MercState
    private let size: CGFloat
    private let mood: MercMood
    @Environment(\.colorScheme) private var scheme
    @NightSettings private var night

    public init(_ state: MercState = .idle, size: CGFloat, mood: MercMood = .neutral) {
        self.state = state
        self.size = size
        self.mood = mood
    }

    public var body: some View {
        ZStack {
            if !night.increasedContrast {
                Circle()
                    .fill(RadialGradient(colors: [Night.lumen.opacity(scheme == .dark ? 0.5 : 0.3), Night.lumen.opacity(0)],
                                         center: .center, startRadius: 0, endRadius: size * 0.62))
                    .frame(width: size * 1.24, height: size * 1.24)
                    .offset(y: size * 0.04)
            }
            MercMascot(state, size: size, mood: mood, idleLife: !night.reduceMotion)
        }
        .frame(width: size * 1.24, height: size * 1.24)
        .accessibilityHidden(true)
    }
}

// MARK: - Flow layout

/// Wraps its children onto new lines when they run out of width (token
/// chips), with a rounding tolerance so a line measured as one never wraps.
public struct NightFlow: Layout {
    private let spacing: CGFloat
    private let lineSpacing: CGFloat

    public init(spacing: CGFloat = 8, lineSpacing: CGFloat = 8) {
        self.spacing = spacing
        self.lineSpacing = lineSpacing
    }

    public func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var lineHeight: CGFloat = 0
        var widest: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0 && x + size.width > maxWidth {
                y += lineHeight + lineSpacing
                x = 0
                lineHeight = 0
            }
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
            widest = max(widest, x - spacing)
        }
        return CGSize(width: min(widest, maxWidth), height: y + lineHeight)
    }

    public func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var lineHeight: CGFloat = 0
        let maxX = bounds.minX + max(proposal.width ?? bounds.width, bounds.width) + 0.5
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX && x + size.width > maxX {
                y += lineHeight + lineSpacing
                x = bounds.minX
                lineHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
    }
}
#endif
