import SwiftUI
import DesignSystem
import PersistenceKit

/// The gamified stats bar that pins above the learning path — streak, XP, and
/// level, Duolingo-style. Tapping anywhere opens the Progress hub.
///
/// COMPOSED AT THE APP ROOT. The learning path lives in `CurriculumFeature`,
/// which (per the architecture layering rules) may not depend on this feature;
/// so `AppShellView` builds this bar and injects it into the path's `topBar`
/// slot, exactly as it already injects `StreakChip` into the chat header.
///
/// GRACEFUL DEGRADATION. The streak is always live, so it always shows. The XP
/// and level stats render ONLY when `gamificationStore.enabled` (client flag on
/// AND the server reports the feature live) — when the server feature is off the
/// bar quietly shows the streak alone rather than a row of zeros.
public struct GamifiedTopBar: View {
    private let streakStore: StreakStore
    private let gamificationStore: GamificationStore
    private let onOpenProfile: () -> Void

    /// Scales the level ring in step with the streak/XP numbers at large
    /// Dynamic Type sizes so the bar stays visually balanced.
    @ScaledMetric private var levelRingSize: CGFloat = 26

    public init(
        streakStore: StreakStore,
        gamificationStore: GamificationStore,
        onOpenProfile: @escaping () -> Void
    ) {
        self.streakStore = streakStore
        self.gamificationStore = gamificationStore
        self.onOpenProfile = onOpenProfile
    }

    public var body: some View {
        Button(action: onOpenProfile) {
            HStack(spacing: BrandSpacing.lg) {
                streakStat
                if gamificationStore.enabled {
                    statDivider
                    xpStat
                    statDivider
                    levelStat
                }
                Spacer(minLength: BrandSpacing.sm)
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(BrandColor.textSecondary)
            }
            .padding(.horizontal, BrandSpacing.lg)
            .padding(.vertical, BrandSpacing.sm)
            .frame(maxWidth: .infinity)
            .background(BrandColor.surface)
            .overlay(alignment: .bottom) {
                Rectangle().fill(BrandColor.border).frame(height: 0.5)
            }
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityAddTraits(.isButton)
        .accessibilityHint("Opens your progress")
    }

    // MARK: - Stats

    private var streakStat: some View {
        HStack(spacing: BrandSpacing.xs) {
            Image(systemName: "flame.fill")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(streakStore.current > 0 ? BrandColor.streakFlame : BrandColor.textSecondary)
            Text("\(streakStore.current)")
                .font(BrandFont.roundedTitle3)
                .foregroundStyle(BrandColor.text)
                .monospacedDigit()
        }
    }

    private var xpStat: some View {
        HStack(spacing: BrandSpacing.xs) {
            Image(systemName: "bolt.fill")
                .font(.system(size: 16, weight: .bold))
                // Deeper gold so the glyph clears 3:1 contrast on the white
                // light-mode surface (bright xpGold is reserved for fills on
                // dark/gradient plates).
                .foregroundStyle(BrandColor.xpGoldDeep)
            Text("\(gamificationStore.xp)")
                .font(BrandFont.roundedTitle3)
                .foregroundStyle(BrandColor.text)
                .monospacedDigit()
        }
    }

    private var levelStat: some View {
        HStack(spacing: BrandSpacing.xs) {
            ZStack {
                Circle()
                    .stroke(BrandColor.surfaceElevated, lineWidth: 3)
                Circle()
                    .trim(from: 0, to: min(1, max(0, gamificationStore.levelProgress)))
                    .stroke(BrandGradient.mercHorizontal, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text("\(gamificationStore.level)")
                    .font(.system(.caption2, design: .rounded, weight: .bold))
                    .foregroundStyle(BrandColor.text)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
            .frame(width: levelRingSize, height: levelRingSize)
            Text("Level")
                .font(BrandFont.roundedCaption)
                .foregroundStyle(BrandColor.textSecondary)
        }
    }

    private var statDivider: some View {
        Rectangle()
            .fill(BrandColor.border)
            .frame(width: 1, height: 22)
    }

    private var accessibilityLabel: String {
        var parts = ["Your progress.", "Current streak: \(streakStore.current) days."]
        if gamificationStore.enabled {
            parts.append("\(gamificationStore.xp) XP.")
            parts.append("Level \(gamificationStore.level).")
        }
        return parts.joined(separator: " ")
    }
}

#if DEBUG
#Preview("GamifiedTopBar — enabled") {
    VStack {
        GamifiedTopBar(
            streakStore: StreakStore(),
            gamificationStore: .preview(enabled: true, xp: 340, level: 3, levelProgress: 0.6, streak: 5),
            onOpenProfile: {}
        )
        Spacer()
    }
    .background(BrandColor.background)
}
#endif
