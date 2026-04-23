import SwiftUI
import DesignSystem
import NetworkingKit

/// Report card sheet — hero grade, two score bars (Critical Thinking
/// and Curiosity), and lists of strengths / areas to revisit /
/// concepts / misconceptions addressed.
public struct ReportCardView: View {
    @State private var model: ReportCardViewModel
    private let dismissAction: () -> Void

    public init(
        model: ReportCardViewModel,
        dismissAction: @escaping () -> Void
    ) {
        _model = State(initialValue: model)
        self.dismissAction = dismissAction
    }

    public var body: some View {
        NavigationStack {
            Group {
                switch model.phase {
                case .loading:
                    loadingView
                case .ready(let card):
                    content(for: card)
                case .failed(let reason, let retryable):
                    failureView(reason: reason, retryable: retryable)
                }
            }
            .background(BrandColor.background)
            .navigationTitle("Report Card")
#if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
#endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", action: dismissAction)
                        .fontWeight(.semibold)
                        .foregroundStyle(BrandColor.accent)
                }
            }
        }
        .task { if case .loading = model.phase { await model.load() } }
    }

    // MARK: - States

    private var loadingView: some View {
        VStack(spacing: BrandSpacing.lg) {
            Spacer()
            ProgressView().controlSize(.large)
            Text("Grading the session…")
                .font(BrandFont.caption)
                .foregroundStyle(BrandColor.textSecondary)
            Spacer()
        }
    }

    private func failureView(reason: String, retryable: Bool) -> some View {
        VStack(spacing: BrandSpacing.lg) {
            Spacer()
            Image(systemName: "doc.text.below.ecg")
                .font(.system(size: 40))
                .foregroundStyle(BrandColor.textSecondary)
            Text(reason)
                .font(BrandFont.body)
                .foregroundStyle(BrandColor.text)
                .multilineTextAlignment(.center)
                .padding(.horizontal, BrandSpacing.xl)
            if retryable {
                BrandButton("Try again", style: .primary) {
                    Task { await model.load() }
                }
                .frame(maxWidth: 220)
            }
            Spacer()
        }
    }

    private func content(for card: ReportCard) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: BrandSpacing.xl) {
                gradeHero(card: card)

                scores(card: card)

                summarySection(card: card)

                if !card.strengths.isEmpty {
                    listSection(
                        title: "Strengths",
                        icon: "sparkles",
                        iconColor: BrandColor.success,
                        items: card.strengths
                    )
                }

                if !card.areasToRevisit.isEmpty {
                    listSection(
                        title: "Areas to revisit",
                        icon: "arrow.clockwise.circle",
                        iconColor: BrandColor.accent,
                        items: card.areasToRevisit
                    )
                }

                if !card.misconceptionsAddressed.isEmpty {
                    listSection(
                        title: "Misconceptions addressed",
                        icon: "lightbulb",
                        iconColor: BrandColor.accentLight,
                        items: card.misconceptionsAddressed
                    )
                }

                if !card.conceptsCovered.isEmpty {
                    conceptsSection(concepts: card.conceptsCovered)
                }

                nextSessionCallout(card: card)

                Color.clear.frame(height: BrandSpacing.lg)
            }
            .padding(.horizontal, BrandSpacing.lg)
            .padding(.top, BrandSpacing.md)
        }
    }

    // MARK: - Pieces

    private func gradeHero(card: ReportCard) -> some View {
        HStack(alignment: .center, spacing: BrandSpacing.lg) {
            Text(card.overallGrade)
                .font(.system(size: 54, weight: .bold, design: .default))
                .foregroundStyle(.white)
                .frame(width: 96, height: 96)
                .background(
                    LinearGradient(
                        colors: [BrandColor.userBubbleTop, BrandColor.userBubbleBottom],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .clipShape(RoundedRectangle(cornerRadius: BrandRadius.lg))
                .accessibilityLabel("Overall grade \(card.overallGrade)")

            VStack(alignment: .leading, spacing: 4) {
                Text("Overall")
                    .font(BrandFont.caption)
                    .textCase(.uppercase)
                    .tracking(1.2)
                    .foregroundStyle(BrandColor.textSecondary)
                Text("Session Grade")
                    .font(BrandFont.title)
                    .foregroundStyle(BrandColor.text)
            }
            Spacer()
        }
    }

    private func scores(card: ReportCard) -> some View {
        VStack(spacing: BrandSpacing.md) {
            scoreBar(
                label: "Critical Thinking",
                value: card.criticalThinkingScore
            )
            scoreBar(
                label: "Curiosity",
                value: card.curiosityScore
            )
        }
    }

    private func scoreBar(label: String, value: Int) -> some View {
        let clamped = max(0, min(100, value))
        return VStack(alignment: .leading, spacing: BrandSpacing.xs) {
            HStack {
                Text(label)
                    .font(BrandFont.bodyEmphasized)
                    .foregroundStyle(BrandColor.text)
                Spacer()
                Text("\(clamped)")
                    .font(BrandFont.bodyEmphasized)
                    .foregroundStyle(BrandColor.accent)
                    .accessibilityLabel("\(label): \(clamped) out of 100")
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
                        .frame(width: proxy.size.width * CGFloat(clamped) / 100)
                }
            }
            .frame(height: 10)
        }
        .accessibilityElement(children: .combine)
    }

    private func summarySection(card: ReportCard) -> some View {
        VStack(alignment: .leading, spacing: BrandSpacing.sm) {
            Text("Summary")
                .font(BrandFont.caption)
                .textCase(.uppercase)
                .tracking(1.2)
                .foregroundStyle(BrandColor.textSecondary)
            Text(card.summary)
                .font(BrandFont.body)
                .foregroundStyle(BrandColor.text)
        }
    }

    private func listSection(
        title: String,
        icon: String,
        iconColor: Color,
        items: [String]
    ) -> some View {
        VStack(alignment: .leading, spacing: BrandSpacing.sm) {
            HStack(spacing: BrandSpacing.xs) {
                Image(systemName: icon)
                    .foregroundStyle(iconColor)
                    .accessibilityHidden(true)
                Text(title)
                    .font(BrandFont.caption)
                    .textCase(.uppercase)
                    .tracking(1.2)
                    .foregroundStyle(BrandColor.textSecondary)
            }
            VStack(alignment: .leading, spacing: BrandSpacing.xs) {
                ForEach(items, id: \.self) { item in
                    HStack(alignment: .firstTextBaseline, spacing: BrandSpacing.sm) {
                        Text("•")
                            .foregroundStyle(iconColor)
                        Text(item)
                            .font(BrandFont.body)
                            .foregroundStyle(BrandColor.text)
                    }
                }
            }
            .padding(BrandSpacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(BrandColor.surface)
            .clipShape(RoundedRectangle(cornerRadius: BrandRadius.md))
        }
    }

    private func conceptsSection(concepts: [String]) -> some View {
        VStack(alignment: .leading, spacing: BrandSpacing.sm) {
            Text("Concepts covered")
                .font(BrandFont.caption)
                .textCase(.uppercase)
                .tracking(1.2)
                .foregroundStyle(BrandColor.textSecondary)
            FlowLayout(spacing: BrandSpacing.xs) {
                ForEach(concepts, id: \.self) { concept in
                    Text(concept)
                        .font(BrandFont.caption)
                        .foregroundStyle(BrandColor.accent)
                        .padding(.vertical, 6)
                        .padding(.horizontal, BrandSpacing.md)
                        .background(BrandColor.accent.opacity(0.12))
                        .clipShape(Capsule())
                }
            }
        }
    }

    private func nextSessionCallout(card: ReportCard) -> some View {
        VStack(alignment: .leading, spacing: BrandSpacing.sm) {
            HStack(spacing: BrandSpacing.xs) {
                Image(systemName: "arrow.forward.circle.fill")
                    .foregroundStyle(BrandColor.accent)
                    .accessibilityHidden(true)
                Text("Next session")
                    .font(BrandFont.caption)
                    .textCase(.uppercase)
                    .tracking(1.2)
                    .foregroundStyle(BrandColor.textSecondary)
            }
            Text(card.nextSessionSuggestion)
                .font(BrandFont.body)
                .foregroundStyle(BrandColor.text)
        }
        .padding(BrandSpacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(BrandColor.surfaceElevated)
        .clipShape(RoundedRectangle(cornerRadius: BrandRadius.lg))
    }
}

// MARK: - FlowLayout for concept chips

/// Simple left-to-right, top-to-bottom wrapping layout. Used for the
/// concept chip bar. iOS 16+ built-in `Layout` protocol.
private struct FlowLayout: Layout {
    let spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        let (_, totalHeight) = layout(subviews: subviews, maxWidth: maxWidth)
        return CGSize(width: maxWidth, height: totalHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let positions = computePositions(subviews: subviews, maxWidth: bounds.width)
        for (sv, origin) in zip(subviews, positions) {
            sv.place(at: CGPoint(x: bounds.minX + origin.x, y: bounds.minY + origin.y), proposal: .unspecified)
        }
    }

    private func layout(subviews: Subviews, maxWidth: CGFloat) -> ([CGPoint], CGFloat) {
        var positions: [CGPoint] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        for sv in subviews {
            let size = sv.sizeThatFits(.unspecified)
            if x + size.width > maxWidth {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            positions.append(CGPoint(x: x, y: y))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return (positions, y + rowHeight)
    }

    private func computePositions(subviews: Subviews, maxWidth: CGFloat) -> [CGPoint] {
        layout(subviews: subviews, maxWidth: maxWidth).0
    }
}
