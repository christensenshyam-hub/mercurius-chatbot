import SwiftUI
import DesignSystem

/// Brief explainer presented as a sheet from `HomeView`. Explains the
/// three pedagogical principles the tutor is built around so a student
/// (or parent, or teacher) knows what to expect before they start.
///
/// Kept deliberately short — anyone who wants more detail will find it
/// in the full pedagogical-philosophy section of the README. The home
/// sheet's job is to give users the confidence to tap **Start Chat**
/// without reading a wall of text.
struct HowItWorksView: View {
    let dismiss: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: BrandSpacing.xl) {
                    header

                    principle(
                        number: "01",
                        title: "Critical thinking over answers",
                        body: "Mercurius uses the Socratic method by default — it asks questions back before answering. The goal is for you to learn about AI, not just from it."
                    )
                    principle(
                        number: "02",
                        title: "Honest about its limits",
                        body: "Every response carries a confidence signal. When Mercurius isn't sure, it says so — and tells you why."
                    )
                    principle(
                        number: "03",
                        title: "Not a homework machine",
                        body: "Ask Mercurius to write your essay and it will redirect you to the thinking behind the task. The tutor's job is to identify what's hard and work on that with you."
                    )

                    note
                }
                .padding(.horizontal, BrandSpacing.xl)
                .padding(.vertical, BrandSpacing.xl)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(BrandColor.background)
            .scrollBounceBehavior(.basedOnSize)
#if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
#endif
            .navigationTitle("How it works")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", action: dismiss)
                        .fontWeight(.semibold)
                        .foregroundStyle(BrandColor.accent)
                }
            }
        }
        .tint(BrandColor.accent)
    }

    // MARK: - Pieces

    private var header: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.sm) {
            Text("A tutor, not a shortcut")
                .font(BrandFont.title)
                .foregroundStyle(BrandColor.text)
                .fixedSize(horizontal: false, vertical: true)

            Text("Three principles shape every response you'll see.")
                .font(BrandFont.body)
                .foregroundStyle(BrandColor.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    private func principle(number: String, title: String, body: String) -> some View {
        HStack(alignment: .top, spacing: BrandSpacing.lg) {
            Text(number)
                .font(BrandFont.bodyEmphasized)
                .foregroundStyle(BrandColor.accent)
                .frame(width: 32, alignment: .leading)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: BrandSpacing.xs) {
                Text(title)
                    .font(BrandFont.bodyEmphasized)
                    .foregroundStyle(BrandColor.text)
                    .fixedSize(horizontal: false, vertical: true)

                Text(body)
                    .font(BrandFont.body)
                    .foregroundStyle(BrandColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title). \(body)")
    }

    private var note: some View {
        Text("Learn AI effectively, ethically, and intelligently.")
            .font(BrandFont.caption)
            .foregroundStyle(BrandColor.textSecondary)
            .padding(.top, BrandSpacing.lg)
    }
}

#Preview("Light") {
    HowItWorksView(dismiss: { print("dismiss") })
        .preferredColorScheme(.light)
}

#Preview("Dark") {
    HowItWorksView(dismiss: { print("dismiss") })
        .preferredColorScheme(.dark)
}
