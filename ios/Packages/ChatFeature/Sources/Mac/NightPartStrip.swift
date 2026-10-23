#if os(macOS)
import SwiftUI
import DesignSystem
import NetworkingKit

/// The lesson's part strip (SPEC.md §5.3.2): a floating capsule pinned at
/// the top of the reading column. "Part 3 · Tokenization" leads; one
/// segment per part so far trails, then a dashed one meaning "more may
/// come" until the lesson is complete. **There is never a total**: Merc's
/// reply is still being written, so nobody knows how many parts there will
/// be. A segment's click scrolls to its part.
struct NightPartStrip: View {
    let parts: [NightPartInfo]
    let current: Int
    /// False once the lesson is complete.
    let moreMayFollow: Bool
    let onSelect: (Int) -> Void

    @NightSettings private var night

    private var currentInfo: NightPartInfo? {
        parts.first { $0.number == current } ?? parts.first
    }

    var body: some View {
        let info = currentInfo
        HStack(spacing: 12) {
            if let info {
                HStack(spacing: 0) {
                    Text(NightReplyCopy.partLabel(info.number))
                        .nightFont(.calloutStrong)
                        .monospacedDigit()
                        .foregroundStyle(Night.ink)
                    if let name = info.name {
                        Text(" · \(name)")
                            .nightFont(.callout)
                            .foregroundStyle(Night.ink2)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                }
                .help(NightReplyCopy.partStripTitle(info.number, name: info.name))
                .layoutPriority(1)
            }
            Spacer(minLength: 8)
            HStack(spacing: 4) {
                ForEach(parts) { part in
                    Button { onSelect(part.number) } label: {
                        Capsule()
                            .fill(segmentStyle(part.number))
                            .frame(minWidth: 6, idealWidth: 18, maxWidth: 18)
                            .frame(height: 4)
                            .frame(height: 28)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help(NightReplyCopy.segmentHelp(part.number, name: part.name))
                }
                if moreMayFollow {
                    Capsule()
                        .strokeBorder(Night.hairline, style: StrokeStyle(lineWidth: 1, dash: [2, 2]))
                        .frame(width: 18, height: 4)
                        .help(NightReplyCopy.moreMayFollowHelp)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 16)
        .frame(height: 36)
        .nightChrome(in: Capsule())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(NightReplyCopy.stripAccessibilityLabel(count: parts.count, current: info?.number ?? 1,
                                                                   name: info?.name))
        .accessibilityHint(NightReplyCopy.stripAccessibilityHint)
        .accessibilityAdjustableAction { direction in
            let now = info?.number ?? 1
            switch direction {
            case .increment: if now < (parts.last?.number ?? 1) { onSelect(now + 1) }
            case .decrement: if now > 1 { onSelect(now - 1) }
            @unknown default: break
            }
        }
    }

    private func segmentStyle(_ number: Int) -> AnyShapeStyle {
        if number < current { return Night.progressLight(increasedContrast: night.increasedContrast) }
        if number == current { return AnyShapeStyle(night.increasedContrast ? Night.accentText : Night.lumen) }
        return AnyShapeStyle(Night.hairline)
    }
}

/// The free chat's mode switch in the window's toolbar, in Night's light: the
/// three modes on one track, the current one on the opaque `prominent`
/// capsule (white on it: 7.9:1), which slides between them (a crossfade under
/// Reduce Motion). It behaves as the native picker did: the same modes, the
/// same rule (no switch mid-reply or mid-switch), the same help and ⌥⌘1–3;
/// each mode is a button VoiceOver reads as selected or not.
///
/// On macOS 26 the toolbar's own glass is the track; elsewhere (macOS 14–25,
/// every CI build, `-NightNoGlass`) it is Night's floating chrome.
struct NightModeSwitcher: View {
    let current: ChatMode
    let isEnabled: Bool
    let onSelect: (ChatMode) -> Void

    @Namespace private var space
    @NightSettings private var night
    @State private var hovered: ChatMode?

    var body: some View {
        HStack(spacing: 2) {
            ForEach(ChatMode.allCases) { mode in
                segment(mode)
            }
        }
        .padding(3)
        .modifier(NightToolbarTrack())
        .animation(night.animation(Night.Motion.tap), value: current)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Mode")
    }

    private func segment(_ mode: ChatMode) -> some View {
        let selected = mode == current
        return Button {
            guard isEnabled else { return }
            onSelect(mode)
        } label: {
            Text(mode.displayName)
                .nightFont(.calloutStrong)
                .foregroundStyle(selected ? Color.white : (isEnabled ? Night.ink2 : Night.ink3))
                .padding(.horizontal, 12)
                .frame(height: 24)
                .background {
                    if selected {
                        if night.reduceMotion {
                            // Under Reduce Motion the capsule doesn't travel:
                            // each segment's own fades in place.
                            Capsule().fill(Night.prominent)
                                .transition(.opacity)
                        } else {
                            Capsule().fill(Night.prominent)
                                .matchedGeometryEffect(id: "selected-mode", in: space)
                        }
                    } else if hovered == mode && isEnabled {
                        Capsule().fill(Night.lumen.opacity(Night.Tint.hover * 2))
                    }
                }
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { inside in
            if inside { hovered = mode } else if hovered == mode { hovered = nil }
        }
        .allowsHitTesting(isEnabled)
        .accessibilityLabel(mode.displayName)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityHint(isEnabled ? "Switches the chat to \(mode.displayName)" : "Available when Merc has finished replying")
    }
}

/// The mode switch in a narrow window: a native pop-up menu ("Socratic ▾")
/// with the same modes and the same rule, so New Chat and Explain More keep
/// their room in the toolbar.
struct NightModeMenu: View {
    let current: ChatMode
    let isEnabled: Bool
    let onSelect: (ChatMode) -> Void

    var body: some View {
        Picker("Mode", selection: Binding(get: { current }, set: { mode in
            guard isEnabled, mode != current else { return }
            onSelect(mode)
        })) {
            ForEach(ChatMode.allCases) { mode in
                Text(mode.displayName).tag(mode)
            }
        }
        .pickerStyle(.menu)
        .labelsHidden()
        .fixedSize()
        .disabled(!isEnabled)
        .accessibilityLabel("Mode")
    }
}

/// The mode switch's track: none of our own where the toolbar is Liquid
/// Glass (its item already sits on glass), floating chrome elsewhere.
private struct NightToolbarTrack: ViewModifier {
    func body(content: Content) -> some View {
        #if compiler(>=6.2)
        if #available(macOS 26.0, *), !Night.debugForcesMaterial {
            content
        } else {
            content.nightChrome(in: Capsule())
        }
        #else
        content.nightChrome(in: Capsule())
        #endif
    }
}
#endif
