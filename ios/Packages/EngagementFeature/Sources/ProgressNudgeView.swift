import SwiftUI
import DesignSystem
import PersistenceKit

/// The brief, factual acknowledgment that appears when a reasoning move is
/// credited — the quiet replacement for the old character pop-up. States the
/// MOVE ("Revised your position") and the points; no voice, no "correct".
public struct ProgressNudgeView: View {
    let nudge: ProgressNudge

    public init(nudge: ProgressNudge) {
        self.nudge = nudge
    }

    public var body: some View {
        HStack(spacing: BrandSpacing.sm) {
            Image(systemName: nudge.leveledUp ? "arrow.up.circle.fill" : "checkmark.circle.fill")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(BrandColor.accent)
            VStack(alignment: .leading, spacing: 1) {
                Text(nudge.leveledUp ? "Level up" : nudge.label)
                    .font(BrandFont.bodyEmphasized)
                    .foregroundStyle(BrandColor.text)
                if nudge.leveledUp {
                    Text(nudge.label)
                        .font(BrandFont.caption)
                        .foregroundStyle(BrandColor.textSecondary)
                }
            }
            Spacer(minLength: BrandSpacing.sm)
            Text("+\(nudge.xp) XP")
                .font(BrandFont.bodyEmphasized)
                .foregroundStyle(BrandColor.accent)
                .monospacedDigit()
        }
        .padding(.horizontal, BrandSpacing.md)
        .padding(.vertical, BrandSpacing.sm)
        .background(BrandColor.surface, in: RoundedRectangle(cornerRadius: BrandRadius.lg, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: BrandRadius.lg, style: .continuous)
                .strokeBorder(BrandColor.border, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.12), radius: 12, y: 4)
        .padding(.horizontal, BrandSpacing.lg)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(nudge.leveledUp ? "Level up. \(nudge.label). Plus \(nudge.xp) XP." : "\(nudge.label). Plus \(nudge.xp) XP.")
    }
}

/// Watches `GamificationStore.lastNudge` and shows the nudge briefly at the
/// bottom, auto-dismissing. Attach once at the app shell. Renders nothing when
/// the feature is disabled (the store never sets a nudge).
public struct ProgressNudgePresenter: ViewModifier {
    private let store: GamificationStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(store: GamificationStore) {
        self.store = store
    }

    public func body(content: Content) -> some View {
        content.overlay(alignment: .bottom) {
            if let nudge = store.lastNudge {
                ProgressNudgeView(nudge: nudge)
                    .padding(.bottom, BrandSpacing.sm)
                    .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
                    .task(id: nudge.id) {
                        try? await Task.sleep(nanoseconds: 3_000_000_000)
                        store.dismissNudge()
                    }
            }
        }
        .animation(reduceMotion ? nil : .spring(response: 0.4, dampingFraction: 0.85), value: store.lastNudge)
    }
}

public extension View {
    /// Present brief progress nudges driven by the shared store.
    func progressNudge(_ store: GamificationStore) -> some View {
        modifier(ProgressNudgePresenter(store: store))
    }
}
