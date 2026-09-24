#if os(iOS)
import SwiftUI
import DesignSystem

/// The Lock Screen banner — Aurora direction. Layout per the handoff:
/// min-height 108, radius 24, padding 15v/17h; glance order is progress →
/// streak → headline → line 2 → meta; Merc is emotional reinforcement,
/// full-bleed in a 118pt trailing art column.
struct LockCardView: View {
    let state: LearningActivityAttributes.ContentState
    let isStale: Bool

    @Environment(\.colorScheme) private var scheme
    private var theme: ActivityTheme { .current }

    /// The system's `isStale` OR an explicit pushed stale phase.
    private var effectivePhase: LearningActivityAttributes.ContentState.Phase {
        isStale && state.phase == .active ? .stale : state.phase
    }

    var body: some View {
        HStack(spacing: 11) {
            // Text + ring take the card's 15pt vertical inset; the art column
            // is exempt so the bust genuinely stretches full height and its
            // −16 bleed measures from the card edge, not the padding box.
            // The text column claims ALL leftover width itself (maxWidth
            // .infinity) — a Spacer sibling would out-compete the wrappable
            // Texts and crush them into truncation.
            textBlock
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 15)
            ProgressRing(
                state: stateForDisplay,
                size: 54, stroke: 6, labelSize: 15
            )
            .padding(.vertical, 15)
            artColumn
        }
        .padding(.leading, 17)
        .frame(minHeight: 108)
        .background(theme.panel(scheme))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(theme.border.resolved(scheme), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        // Stale: dim + desaturate the WHOLE presentation — never a new asset.
        .saturation(effectivePhase == .stale ? 0.42 : 1)
        .opacity(effectivePhase == .stale ? 0.92 : 1)
    }

    /// The ring renders the effective phase (so system-stale keeps the last
    /// known numbers but the card dims).
    private var stateForDisplay: LearningActivityAttributes.ContentState {
        var s = state
        s.phase = effectivePhase
        return s
    }

    // MARK: - Text block

    private var textBlock: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                StreakChipView(state: state)
                Spacer(minLength: 0)
                statusGlyph
            }
            Text(state.headline(for: effectivePhase))
                .font(.system(size: 20, weight: .heavy))
                .tracking(-0.4)
                .lineSpacing(-2)
                .foregroundStyle(theme.text.resolved(scheme))
                .lineLimit(1)
            Text(state.progressLine(for: effectivePhase))
                .font(.system(size: 13.5, weight: .semibold))
                .tracking(-0.1)
                .foregroundStyle(theme.sub.resolved(scheme))
                .lineLimit(1)
            state.metaLine(for: effectivePhase)
                .font(.system(size: 12, weight: .semibold))
                .tracking(-0.1)
                .foregroundStyle(theme.sub.resolved(scheme).opacity(0.85))
                .lineLimit(1)
                .truncationMode(.tail)
        }
    }

    @ViewBuilder private var statusGlyph: some View {
        switch effectivePhase {
        case .completed:
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 15))
                .foregroundStyle(ActivityTheme.success)
        case .error:
            Image(systemName: "wifi.slash")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(ActivityTheme.amber)
        default:
            EmptyView()
        }
    }

    // MARK: - Art column (Aurora: full-bleed bust, bleeds off right/bottom)

    private var artColumn: some View {
        // Bust framing (head + shoulders) per the handoff's mascot spec —
        // oversized inside a 118pt column so it bleeds off right/bottom.
        MercBust(phase: effectivePhase, size: 150)
            .frame(width: 118)
            .offset(x: 6, y: 16)
            .frame(maxHeight: .infinity, alignment: .bottom)
    }
}
#endif
