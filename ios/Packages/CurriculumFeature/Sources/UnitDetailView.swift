import SwiftUI
import DesignSystem

struct UnitDetailView: View {
    let unit: Unit
    @Bindable var progress: CurriculumProgressStore
    let onStartLesson: (Lesson) -> Void

    var body: some View {
        List {
            overviewSection
            lessonsSection
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
                    isCompleted: progress.isCompleted(lesson.id),
                    onStart: { onStartLesson(lesson) },
                    onToggleComplete: {
                        if progress.isCompleted(lesson.id) {
                            progress.markIncomplete(lesson.id)
                        } else {
                            progress.markCompleted(lesson.id)
                        }
                    }
                )
            }
        }
    }
}

private struct LessonRow: View {
    let lesson: Lesson
    let isCompleted: Bool
    let onStart: () -> Void
    let onToggleComplete: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: BrandSpacing.md) {
            completionButton

            VStack(alignment: .leading, spacing: 4) {
                Text("Lesson \(lesson.number)")
                    .font(.caption2)
                    .tracking(1.2)
                    .foregroundStyle(BrandColor.textSecondary)

                Text(lesson.title)
                    .font(BrandFont.bodyEmphasized)
                    .foregroundStyle(BrandColor.text)

                Text(lesson.objective)
                    .font(BrandFont.caption)
                    .foregroundStyle(BrandColor.textSecondary)
                    .padding(.top, 2)

                Button(action: onStart) {
                    Label("Start lesson", systemImage: "play.circle.fill")
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
                .accessibilityLabel("Start lesson: \(lesson.title)")
            }
        }
        .padding(.vertical, 4)
    }

    private var completionButton: some View {
        Button(action: onToggleComplete) {
            Image(systemName: isCompleted ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 22))
                .foregroundStyle(isCompleted ? BrandColor.success : BrandColor.textSecondary)
        }
        .buttonStyle(.plain)
        .frame(width: 44, height: 44)
        .accessibilityLabel(isCompleted ? "Mark incomplete" : "Mark complete")
    }
}
