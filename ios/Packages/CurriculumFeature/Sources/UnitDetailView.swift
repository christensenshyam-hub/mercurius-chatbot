import SwiftUI
import DesignSystem

struct UnitDetailView: View {
    let unit: Unit
    @Bindable var progress: CurriculumProgressStore
    let onStartLesson: (Lesson) -> Void
    let onStartUnitTest: (Unit) -> Void

    var body: some View {
        List {
            overviewSection
            lessonsSection
            unitTestSection
        }
#if os(iOS)
        .listStyle(.insetGrouped)
#endif
        .scrollContentBackground(.hidden)
        .background(BrandColor.background)
        .navigationTitle(unit.title)
#if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
#endif
    }

    private var overviewSection: some View {
        Section {
            VStack(alignment: .leading, spacing: BrandSpacing.sm) {
                Text("UNIT \(unit.number)")
                    .font(BrandFont.caption)
                    .tracking(1.5)
                    .foregroundStyle(BrandColor.accent)
                Text(unit.title)
                    .font(BrandFont.title)
                    .foregroundStyle(BrandColor.text)
                Text(unit.summary)
                    .font(BrandFont.body)
                    .foregroundStyle(BrandColor.textSecondary)
            }
            .padding(.vertical, 4)
        }
    }

    private var lessonsSection: some View {
        Section("Lessons") {
            ForEach(unit.lessons) { lesson in
                LessonRow(
                    lesson: lesson,
                    state: progress.state(of: lesson.id),
                    unlocked: progress.isLessonUnlocked(lesson, in: unit),
                    onStart: { onStartLesson(lesson) }
                )
            }
        }
    }

    private var unitTestSection: some View {
        Section("Unit test") {
            UnitTestRow(
                unlocked: progress.isUnitTestUnlocked(unit),
                mastered: progress.isUnitMastered(unit.id),
                onStart: { onStartUnitTest(unit) }
            )
        }
    }
}

private struct LessonRow: View {
    let lesson: Lesson
    let state: CurriculumProgressStore.LessonState
    /// Sequential gating: when false, the lesson is locked behind the previous
    /// lesson in the unit and renders a locked state with no Start/Resume button.
    let unlocked: Bool
    let onStart: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: BrandSpacing.md) {
            statusGlyph

            VStack(alignment: .leading, spacing: 4) {
                Text("Lesson \(lesson.number)")
                    .font(.caption2)
                    .tracking(1.2)
                    .foregroundStyle(BrandColor.textSecondary)

                Text(lesson.title)
                    .font(BrandFont.bodyEmphasized)
                    .foregroundStyle(unlocked ? BrandColor.text : BrandColor.textSecondary)

                Text(lesson.objective)
                    .font(BrandFont.caption)
                    .foregroundStyle(BrandColor.textSecondary)
                    .opacity(unlocked ? 1 : 0.6)
                    .padding(.top, 2)

                if !unlocked {
                    Text("Complete the previous lesson to unlock")
                        .font(.caption2)
                        .fontWeight(.semibold)
                        .foregroundStyle(BrandColor.textSecondary)
                        .padding(.top, 2)
                        .accessibilityLabel("Locked. Complete the previous lesson to unlock.")
                } else {
                    if state == .inProgress {
                        Label("In progress", systemImage: "clock.fill")
                            .font(.caption2)
                            .fontWeight(.semibold)
                            .foregroundStyle(BrandColor.accent)
                            .padding(.top, 2)
                            .accessibilityLabel("In progress")
                    }

                    Button(action: onStart) {
                        Label(actionTitle, systemImage: actionIcon)
                            .font(BrandFont.caption)
                            .fontWeight(.semibold)
                            .foregroundStyle(.white)
                            .padding(.vertical, 6)
                            .padding(.horizontal, BrandSpacing.md)
                            .background(BrandColor.accent)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .frame(minHeight: 44)
                    .padding(.top, 4)
                    .accessibilityLabel("\(actionTitle): \(lesson.title)")
                }
            }
        }
        .padding(.vertical, 4)
    }

    /// Primary action label/icon: Start (not started) → Resume (in progress) →
    /// Review (completed).
    private var actionTitle: String {
        switch state {
        case .notStarted: return "Start lesson"
        case .inProgress: return "Resume"
        case .completed: return "Review"
        }
    }

    private var actionIcon: String {
        switch state {
        case .notStarted: return "play.circle.fill"
        case .inProgress: return "arrow.forward.circle.fill"
        case .completed: return "arrow.counterclockwise.circle.fill"
        }
    }

    /// Non-interactive leading status indicator. Completion happens only via the
    /// proficiency checkpoint, so this is a plain glyph (no tap target): a lock
    /// when gated, otherwise the lesson's three-state status.
    private var statusGlyph: some View {
        Image(systemName: glyphName)
            .font(.system(size: 22))
            .foregroundStyle(glyphColor)
            .frame(width: 44, height: 44)
            .accessibilityHidden(true)
    }

    private var glyphName: String {
        guard unlocked else { return "lock.fill" }
        switch state {
        case .notStarted: return "circle"
        case .inProgress: return "clock.fill"
        case .completed: return "checkmark.circle.fill"
        }
    }

    private var glyphColor: Color {
        guard unlocked else { return BrandColor.textSecondary }
        switch state {
        case .notStarted: return BrandColor.textSecondary
        case .inProgress: return BrandColor.accent
        case .completed: return BrandColor.success
        }
    }
}

/// The cumulative unit-test row at the bottom of a unit. Locked until every
/// lesson is complete, then "Take unit test"; once passed, shows a mastery
/// glyph and a "Retake test" option.
private struct UnitTestRow: View {
    let unlocked: Bool
    let mastered: Bool
    let onStart: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: BrandSpacing.md) {
            Image(systemName: glyph)
                .font(.system(size: 22))
                .foregroundStyle(glyphColor)
                .frame(width: 44, height: 44)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text("Cumulative unit test")
                    .font(BrandFont.bodyEmphasized)
                    .foregroundStyle(unlocked ? BrandColor.text : BrandColor.textSecondary)

                Text(subtitle)
                    .font(BrandFont.caption)
                    .foregroundStyle(BrandColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 2)

                if mastered {
                    Label("Mastered", systemImage: "rosette")
                        .font(.caption2)
                        .fontWeight(.semibold)
                        .foregroundStyle(BrandColor.success)
                        .padding(.top, 2)
                }

                if unlocked {
                    Button(action: onStart) {
                        Label(buttonTitle, systemImage: buttonIcon)
                            .font(BrandFont.caption)
                            .fontWeight(.semibold)
                            .foregroundStyle(.white)
                            .padding(.vertical, 6)
                            .padding(.horizontal, BrandSpacing.md)
                            .background(BrandColor.accent)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .frame(minHeight: 44)
                    .padding(.top, 4)
                    .accessibilityLabel(buttonTitle)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private var glyph: String {
        if mastered { return "rosette" }
        return unlocked ? "checklist" : "lock.fill"
    }

    private var glyphColor: Color {
        if mastered { return BrandColor.success }
        return unlocked ? BrandColor.accent : BrandColor.textSecondary
    }

    private var subtitle: String {
        if mastered { return "Mastered — you passed the quiz and the written defense." }
        if unlocked { return "A quiz across the whole unit plus one written question, graded by Mercurius." }
        return "Finish all the lessons in this unit to unlock the test."
    }

    private var buttonTitle: String { mastered ? "Retake test" : "Take unit test" }
    private var buttonIcon: String { mastered ? "arrow.counterclockwise.circle.fill" : "play.circle.fill" }
}
