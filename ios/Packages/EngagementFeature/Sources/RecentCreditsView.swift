import SwiftUI
import DesignSystem
import PersistenceKit

/// The factual "Recent" reasoning-move credit log — character-free rows, each a
/// move ("Revised your position") and the points it earned. The quiet
/// encouragement layer: it states what you did, never "correct". Renders
/// nothing when disabled or empty.
public struct RecentCreditsView: View {
    private let store: GamificationStore

    public init(store: GamificationStore) {
        self.store = store
    }

    public var body: some View {
        if store.enabled && !store.recentCredits.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                Text("Recent")
                    .font(BrandFont.caption)
                    .foregroundStyle(BrandColor.textSecondary)
                    .padding(.bottom, BrandSpacing.xs)

                ForEach(Array(store.recentCredits.enumerated()), id: \.element.id) { index, credit in
                    if index > 0 {
                        Divider().overlay(BrandColor.border.opacity(0.4))
                    }
                    row(credit)
                }
            }
            .padding(BrandSpacing.lg)
            .background(BrandColor.surfaceElevated, in: RoundedRectangle(cornerRadius: BrandRadius.lg))
            .overlay(
                RoundedRectangle(cornerRadius: BrandRadius.lg)
                    .strokeBorder(BrandColor.border.opacity(0.6), lineWidth: 1)
            )
        }
    }

    private func row(_ credit: ProgressCredit) -> some View {
        HStack(spacing: BrandSpacing.sm) {
            Image(systemName: "checkmark")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(BrandColor.accent)
            Text(credit.label)
                .font(BrandFont.body)
                .foregroundStyle(BrandColor.text)
            Spacer(minLength: BrandSpacing.sm)
            Text("+\(credit.xp) XP")
                .font(BrandFont.caption)
                .foregroundStyle(BrandColor.textSecondary)
                .monospacedDigit()
        }
        .padding(.vertical, BrandSpacing.sm)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(credit.label), plus \(credit.xp) XP")
    }
}

#if DEBUG
#Preview("Recent credits") {
    RecentCreditsView(store: .preview())
        .padding()
        .background(BrandColor.background)
}
#endif
