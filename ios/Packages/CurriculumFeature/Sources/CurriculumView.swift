import SwiftUI
import DesignSystem

/// Root curriculum screen — a navigation stack of units. Tapping a
/// unit pushes `UnitDetailView`; tapping a lesson there invokes the
/// `onStartLesson` callback provided by the host.
public struct CurriculumView: View {
    @Bindable var progress: CurriculumProgressStore
    let onStartLesson: (Lesson) -> Void

    public init(
        progress: CurriculumProgressStore,
        onStartLesson: @escaping (Lesson) -> Void
    ) {
        self.progress = progress
        self.onStartLesson = onStartLesson
    }

    public var body: some View {
        NavigationStack {
            List {
                overallProgressSection
                unitsSection
            }
#if os(iOS)
            .listStyle(.insetGrouped)
#endif
            .scrollContentBackground(.hidden)
            .background(BrandColor.background)
            .navigationTitle("Curriculum")
        }
    }

    // MARK: - Sections

    private var overallProgressSection: some View {
        Section {
            CurriculumProgressBar(
                completed: progress.totalCompleted(),
                total: progress.totalLessons
            )
            .padding(.vertical, BrandSpacing.xs)
        } header: {
            Text("Overall progress")
        } footer: {
            Text("5 units, 4 lessons each. Each lesson starts a guided chat.")
        }
    }

    private var unitsSection: some View {
        Section("Units") {
            ForEach(MercuriusCurriculum.units) { unit in
                NavigationLink {
                    UnitDetailView(
                        unit: unit,
                        progress: progress,
                        onStartLesson: onStartLesson
                    )
                } label: {
                    UnitRow(unit: unit, progress: progress)
                }
            }
        }
    }
}

// MARK: - Unit row

private struct UnitRow: View {
    let unit: Unit
    let progress: CurriculumProgressStore

    var body: some View {
        HStack(spacing: BrandSpacing.md) {
            unitBadge

            VStack(alignment: .leading, spacing: 4) {
                Text(unit.title)
                    .font(BrandFont.bodyEmphasized)
                    .foregroundStyle(BrandColor.text)
                Text(unit.summary)
                    .font(BrandFont.caption)
                    .foregroundStyle(BrandColor.textSecondary)
                    .lineLimit(2)

                HStack(spacing: 4) {
                    Text("\(progress.completedCount(in: unit)) of \(unit.lessons.count) lessons")
                        .font(.caption2)
                        .foregroundStyle(BrandColor.textSecondary)
                    if progress.completedCount(in: unit) == unit.lessons.count {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.caption2)
                            .foregroundStyle(BrandColor.success)
                    }
                }
                .padding(.top, 2)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }

    private var unitBadge: some View {
        Text(unit.number)
            .font(.system(size: 14, weight: .bold, design: .default))
            .foregroundStyle(.white)
            .frame(width: 36, height: 36)
            .background(
                LinearGradient(
                    colors: [BrandColor.userBubbleTop, BrandColor.userBubbleBottom],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .accessibilityHidden(true)
    }
}

// MARK: - Progress bar

private struct CurriculumProgressBar: View {
    let completed: Int
    let total: Int

    var body: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.xs) {
            HStack {
                Text("\(completed) of \(total) lessons complete")
                    .font(BrandFont.caption)
                    .foregroundStyle(BrandColor.text)
                Spacer()
                Text("\(percent)%")
                    .font(BrandFont.caption)
                    .foregroundStyle(BrandColor.accent)
            }
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(BrandColor.surfaceElevated)
                    RoundedRectangle(cornerRadius: 6)
                        .fill(
                            LinearGradient(
                                colors: [BrandColor.accent, BrandColor.accentLight],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: max(0, proxy.size.width * fraction))
                }
            }
            .frame(height: 10)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(completed) of \(total) lessons complete")
    }

    private var fraction: CGFloat {
        guard total > 0 else { return 0 }
        return CGFloat(completed) / CGFloat(total)
    }

    private var percent: Int {
        Int((fraction * 100).rounded())
    }
}
