#if os(iOS)
import SwiftUI
import WidgetKit
import ActivityKit
import DesignSystem

/// The Live Activity: Lock Screen banner + the three Dynamic Island
/// presentations, all pure functions of `ContentState` (no local state, no
/// timers except the system-driven countdown). Lives in the shared package so
/// the widget-extension target stays a thin `@main` bundle.
public struct MercuriusLiveActivityWidget: Widget {
    public init() {}

    public var body: some WidgetConfiguration {
        ActivityConfiguration(for: LearningActivityAttributes.self) { context in
            // ── Lock Screen / banner ──
            LockCardView(state: context.state, isStale: context.isStale)
                .activityBackgroundTint(Color.clear)   // we draw our own panel
                .widgetURL(URL(string: "mercurius://session"))
        } dynamicIsland: { context in
            // System-stale renders as the `.stale` phase on EVERY region —
            // the handoff dims the whole presentation, not just the bottom.
            let state = context.state.effective(isStale: context.isStale)
            let stale = state.phase == .stale
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    StreakChipView(state: state, onIsland: true)
                        .padding(.leading, 4)
                        .padding(.top, 2)
                        .staleDim(stale)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    ProgressRing(state: state, size: 44, stroke: 5, labelSize: 13, onIsland: true)
                        .padding(.trailing, 2)
                        .staleDim(stale)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    ExpandedBody(state: context.state, isStale: context.isStale)
                }
            } compactLeading: {
                // 🔥 24 — the whole side stays ≤ ~4 glyphs.
                StreakChipView(state: state, compact: true, onIsland: true)
                    .staleDim(stale)
            } compactTrailing: {
                ProgressRing(state: state, size: 26, stroke: 3.5, labelSize: 9, onIsland: true)
                    .staleDim(stale)
            } minimal: {
                // Ring only (no text) per the handoff's state table.
                ProgressRing(state: state, size: 26, stroke: 3.5, labelSize: 9, onIsland: true, showsLabel: false)
                    .staleDim(stale)
            }
            .widgetURL(URL(string: "mercurius://session"))
            .keylineTint(ActivityTheme.current.diRing.first)
        }
    }
}

/// DI expanded `.bottom` region: headline + single meta line, with a 66pt
/// circular Merc medallion on the trailing side.
struct ExpandedBody: View {
    let state: LearningActivityAttributes.ContentState
    let isStale: Bool

    private var theme: ActivityTheme { .current }

    private var effectivePhase: LearningActivityAttributes.ContentState.Phase {
        isStale && state.phase == .active ? .stale : state.phase
    }

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(headline)
                    .font(.system(size: 19, weight: .heavy))
                    .tracking(-0.4)
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text(sub)
                    .font(.system(size: 13, weight: .semibold))
                    .tracking(-0.1)
                    .foregroundStyle(.white.opacity(0.78))
                    .lineLimit(1)
                meta
                    .font(.system(size: 12, weight: .semibold))
                    .tracking(-0.1)
                    .foregroundStyle(metaColor)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            Spacer(minLength: 0)
            ZStack {
                Circle().fill(Color.white.opacity(0.08))
                MercBust(phase: effectivePhase, size: 60)
            }
            .frame(width: 66, height: 66)
        }
        .padding(.top, 4)
        .saturation(effectivePhase == .stale ? 0.42 : 1)
        .opacity(effectivePhase == .stale ? 0.92 : 1)
    }

    private var metaColor: Color {
        // Meta reads in the ACCENT color per the layout spec (amber when the
        // sync is broken). The island is always dark.
        effectivePhase == .error
            ? ActivityTheme.amber
            : theme.accent.resolved(.dark)
    }

    private var headline: String {
        switch effectivePhase {
        case .active:    return "On a roll"
        case .completed: return "Streak banked"
        case .stale:     return "Still there?"
        case .error:     return "Can't sync"
        }
    }

    private var sub: String {
        switch effectivePhase {
        case .active:    return "Lesson \(state.lessonsDone) of \(state.lessonsTotal)"
        case .completed: return "\(state.lessonsDone) of \(state.lessonsTotal) lessons"
        case .stale:     return "Paused on Lesson \(state.lessonsDone)"
        case .error:     return "We'll retry automatically"
        }
    }

    @ViewBuilder private var meta: some View {
        switch effectivePhase {
        case .active:
            (Text("\(state.lessonsToLevel) to Level \(state.level) · ")
             + Text(timerInterval: state.countdownRange, countsDown: true)
             + Text(" left"))
        case .completed:
            Text("Level \(state.level) unlocked")
        case .stale:
            (Text("Updated ") + Text(state.lastUpdated, style: .relative) + Text(" ago"))
        case .error:
            Text("Check your connection")
        }
    }
}
#endif
