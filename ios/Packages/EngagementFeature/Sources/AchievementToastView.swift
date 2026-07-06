import SwiftUI
import DesignSystem
import PersistenceKit

/// Transient "Achievement unlocked" banner.
public struct AchievementToastView: View {
    let achievement: Achievement

    public init(achievement: Achievement) {
        self.achievement = achievement
    }

    public var body: some View {
        HStack(spacing: BrandSpacing.md) {
            Image(systemName: achievement.symbol)
                .font(.system(size: 22))
                .foregroundStyle(.white)
                .frame(width: 40, height: 40)
                .background(BrandColor.accent, in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text("Achievement unlocked")
                    .font(BrandFont.caption)
                    .foregroundStyle(BrandColor.textSecondary)
                Text(achievement.title)
                    .font(BrandFont.bodyEmphasized)
                    .foregroundStyle(BrandColor.text)
            }
            Spacer()
        }
        .padding(BrandSpacing.md)
        .background(BrandColor.surface, in: RoundedRectangle(cornerRadius: BrandRadius.lg, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: BrandRadius.lg, style: .continuous)
                .strokeBorder(BrandColor.border, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.12), radius: 12, y: 4)
        .padding(.horizontal, BrandSpacing.lg)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Achievement unlocked: \(achievement.title)")
    }
}

/// Watches `AchievementStore.lastEarned` and shows the toast at the top of the
/// screen, auto-dismissing after a few seconds. Attach at the app shell AND at
/// the root of each full-screen cover — a sheet/cover renders above the shell's
/// overlay, so awards fired while one is up need a presenter in that layer too.
/// Multiple attachments are safe: `clearLastEarned(_:)` is head-guarded, so
/// duplicate clears for the same achievement can't swallow the next queued one.
public struct AchievementToastPresenter: ViewModifier {
    private let store: AchievementStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(store: AchievementStore) {
        self.store = store
    }

    public func body(content: Content) -> some View {
        content.overlay(alignment: .top) {
            if let earned = store.lastEarned {
                AchievementToastView(achievement: earned)
                    .padding(.top, BrandSpacing.sm)
                    .transition(reduceMotion ? .opacity : .move(edge: .top).combined(with: .opacity))
                    .task(id: earned.id) {
                        try? await Task.sleep(nanoseconds: 3_200_000_000)
                        store.clearLastEarned(earned)
                    }
            }
        }
        .animation(reduceMotion ? nil : .spring(response: 0.4, dampingFraction: 0.85), value: store.lastEarned)
    }
}

public extension View {
    /// Present achievement-unlocked toasts driven by the shared store.
    func achievementToasts(_ store: AchievementStore) -> some View {
        modifier(AchievementToastPresenter(store: store))
    }
}
