import SwiftUI
import DesignSystem
import PersistenceKit

/// Compact flame + streak count for the chat header. Persistently visible so the
/// streak stays top-of-mind; tapping opens the Progress hub. With no streak
/// yet it's the flame alone — the invitation is in its VoiceOver label and in
/// the hub it opens (the header has no room for a sentence).
public struct StreakChip: View {
    private let streakStore: StreakStore
    private let action: () -> Void

    public init(streakStore: StreakStore, action: @escaping () -> Void) {
        self.streakStore = streakStore
        self.action = action
    }

    public var body: some View {
        #if os(macOS)
        macToolbarButton
        #else
        phoneChip
        #endif
    }

    #if os(macOS)
    /// The Mac: a plain toolbar button — the flame, and the count once there
    /// is a streak — with a tooltip, sized by the toolbar (the iPhone's 44 pt
    /// capsule stood bigger than the buttons beside it).
    private var macToolbarButton: some View {
        let display = StreakDisplay(count: streakStore.current)
        return Button(action: action) {
            if let countText = display.countText {
                Label {
                    Text(countText).monospacedDigit()
                } icon: {
                    Image(systemName: "flame.fill")
                        .foregroundStyle(BrandColor.streakFlame)
                }
                .labelStyle(.titleAndIcon)
            } else {
                Label("Progress", systemImage: "flame")
            }
        }
        // A toolbar button's own look, whatever the host's button style.
        .buttonStyle(.automatic)
        .help(Self.macHelp(display))
        .accessibilityLabel("Your progress. \(display.spokenStreak)")
    }

    /// The toolbar button's tooltip.
    static func macHelp(_ display: StreakDisplay) -> String {
        display.isZero
            ? "Your progress and achievements. Finish a lesson to start a streak."
            : "Your progress and achievements. \(display.spokenStreak)"
    }
    #endif

    private var phoneChip: some View {
        let display = StreakDisplay(count: streakStore.current)
        return Button(action: action) {
            HStack(spacing: BrandSpacing.xs) {
                Image(systemName: "flame.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(display.isZero ? BrandColor.textSecondary : BrandColor.streakFlame)
                if let countText = display.countText {
                    Text(countText)
                        .font(BrandFont.bodyEmphasized)
                        .foregroundStyle(BrandColor.text)
                        .monospacedDigit()
                }
            }
            .padding(.horizontal, BrandSpacing.sm)
            .padding(.vertical, BrandSpacing.xs)
            .background(BrandColor.surfaceElevated, in: Capsule())
            // The capsule stays compact; the tap target around it is 44 pt
            // (it measured 29 x 24.5 pt, AUD-46).
            .frame(minWidth: 44, minHeight: 44)
            .contentShape(Rectangle())
        }
        // Header chrome: it stops growing at AX1 so the header row keeps its
        // shape at the largest sizes; a long press shows it large (AUD-48).
        .dynamicTypeSize(...DynamicTypeSize.accessibility1)
        .accessibilityShowsLargeContentViewer()
        .accessibilityLabel("Your progress. \(display.spokenStreak)")
    }
}
