#if os(iOS)
import SwiftUI
import DesignSystem

// MARK: - Countdown range

extension LearningActivityAttributes.ContentState {
    /// Crash-safe range for `Text(timerInterval:)`: `Date.now...deadline`
    /// traps when the deadline is already past (ClosedRange requires
    /// lowerBound ≤ upperBound), which a long-lived activity hits the moment
    /// the system re-renders after the window closes. Clamped, the timer
    /// simply reads 0:00 until the stale flip takes over.
    var countdownRange: ClosedRange<Date> {
        let now = Date.now
        return now...max(now, deadline)
    }

    /// System-stale (the staleDate passed with no update landing) renders
    /// exactly like a pushed `.stale` phase — one code path for both.
    func effective(isStale: Bool) -> Self {
        guard isStale, phase == .active else { return self }
        var s = self
        s.phase = .stale
        return s
    }
}

extension View {
    /// Stale = desaturate + dim the ENTIRE presentation (per the handoff) —
    /// applied to every Live Activity surface, never a new asset.
    func staleDim(_ isStale: Bool) -> some View {
        self
            .saturation(isStale ? 0.42 : 1)
            .opacity(isStale ? 0.92 : 1)
    }
}

// MARK: - Progress ring

/// The circular progress element. Sizes/strokes per the handoff:
/// 54pt/6 (Aurora lock), 44pt/5 (DI expanded), 26pt/3.5 (DI compact/minimal).
/// Completed shows a checkmark at progress 1; error shows a muted track with
/// an em-dash and no fill.
struct ProgressRing: View {
    let state: LearningActivityAttributes.ContentState
    /// Fixed diameter — or nil to fit whatever the container proposes
    /// (the DI compact slot offers ~18pt between the sensor cutout and the
    /// island edge and SHEARS any fixed frame wider than that, so island
    /// compact/minimal must size adaptively).
    let size: CGFloat?
    let stroke: CGFloat
    let labelSize: CGFloat
    /// DI ring uses the direction's DI gradient over the island's black;
    /// the lock ring uses the panel's ring tokens.
    var onIsland: Bool = false
    /// DI minimal is "ring only (no text)" per the handoff's state table.
    var showsLabel: Bool = true

    @Environment(\.colorScheme) private var scheme
    private var theme: ActivityTheme { .current }

    var body: some View {
        ZStack {
            // Inset by half the stroke: `.stroke` straddles the path, so an
            // un-inset "26pt" ring paints 29.5pt and the Dynamic Island's
            // compact slot shears the overflow off at the island edge.
            // Inset, the ring's OUTER edge equals the stated size exactly.
            Circle()
                .inset(by: stroke / 2)
                .stroke(trackColor, lineWidth: stroke)
            if state.phase != .error {
                Circle()
                    .inset(by: stroke / 2)
                    .trim(from: 0, to: displayedProgress)
                    .stroke(fillStyle, style: StrokeStyle(lineWidth: stroke, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
            if showsLabel {
                label
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .frame(width: size, height: size)
    }

    private var displayedProgress: CGFloat {
        state.phase == .completed ? 1 : max(0, min(1, state.progress))
    }

    private var trackColor: Color {
        onIsland ? .white.opacity(0.20) : theme.ringTrack.resolved(scheme)
    }

    private var fillStyle: AnyShapeStyle {
        if state.phase == .error {
            return AnyShapeStyle(scheme == .dark ? ActivityTheme.errorFillDark : ActivityTheme.errorFillLight)
        }
        return onIsland
            ? AnyShapeStyle(theme.diRingGradient)
            : AnyShapeStyle(theme.ringFill(scheme))
    }

    @ViewBuilder private var label: some View {
        switch state.phase {
        case .completed:
            // Success green on every surface, per the per-state treatment.
            Image(systemName: "checkmark")
                .font(.system(size: labelSize, weight: .heavy))
                .foregroundStyle(ActivityTheme.success)
        case .error:
            Text("—")
                .font(.system(size: labelSize, weight: .heavy))
                .foregroundStyle(onIsland ? Color.white.opacity(0.6) : theme.sub.resolved(scheme))
        default:
            Text("\(state.lessonsDone)/\(state.lessonsTotal)")
                .font(.system(size: labelSize, weight: .heavy))
                .foregroundStyle(onIsland ? Color.white : theme.text.resolved(scheme))
                // Island rings are small — shrink the fraction to fit the
                // ring's inner well instead of overflowing it.
                .lineLimit(1)
                .minimumScaleFactor(0.55)
                .padding(.horizontal, stroke)
        }
    }
}

// MARK: - Streak chip

/// `🔥 24 day streak` — flame glyph on the flame gradient (gold in Dawn),
/// count 15/800, label 12/600 muted. Compact drops the label (DI budget:
/// ≤ ~4 glyphs per side).
struct StreakChipView: View {
    let state: LearningActivityAttributes.ContentState
    var compact: Bool = false
    var onIsland: Bool = false

    @Environment(\.colorScheme) private var scheme
    private var theme: ActivityTheme { .current }

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: "flame.fill")
                .font(.system(size: compact ? 17 : 13, weight: .semibold))
                .foregroundStyle(ActivityTheme.flame)
            // `fixedSize` — the chip must never wrap ("2\n4", "day\nstreak")
            // when the lock card's text column is width-squeezed.
            Text("\(state.streakCount)")
                .font(.system(size: 15, weight: .heavy))
                .tracking(-0.2)
                .foregroundStyle(onIsland ? .white : theme.text.resolved(scheme))
                .lineLimit(1)
                .fixedSize()
            if !compact {
                Text("day streak")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(onIsland ? .white.opacity(0.78) : theme.sub.resolved(scheme))
                    .lineLimit(1)
                    .fixedSize()
            }
        }
    }
}

// MARK: - Merc expressions

/// The handoff's four expressions, mapped onto the app's real (procedural)
/// mascot — no stand-in SVG, no raster assets. Rendered statically
/// (`idleLife: false`) because Live Activity views don't run animations.
enum MercExpression {
    case focused, cheer, sleepy, puzzled

    init(phase: LearningActivityAttributes.ContentState.Phase) {
        switch phase {
        case .active:    self = .focused
        case .completed: self = .cheer
        case .stale:     self = .sleepy
        case .error:     self = .puzzled
        }
    }

    var mercState: MercState {
        switch self {
        case .focused: return .idle       // determined, steady
        case .cheer:   return .celebrate  // arms up, sparkles
        case .sleepy:  return .sleep      // closed eyes, zzz
        case .puzzled: return .thinking   // cocked head, pondering
        }
    }
}

/// Bust-framed Merc for the lock card's full-bleed art column and the DI
/// medallion wells.
struct MercBust: View {
    let phase: LearningActivityAttributes.ContentState.Phase
    let size: CGFloat

    var body: some View {
        MercMascot(
            MercExpression(phase: phase).mercState,
            size: size,
            presentation: .bust,
            idleLife: false
        )
        .accessibilityHidden(true)
    }
}
#endif
