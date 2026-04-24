import SwiftUI
import DesignSystem
import NetworkingKit

/// First-time contextual explainer for a single chat mode. Presented
/// via `.sheet(item:)` from `ModeSelectorView` the first time a user
/// taps each mode; suppressed on subsequent taps by
/// `ModeDescriptionStore`.
///
/// Three beats, top to bottom: **purpose / when / example**. That's
/// the maximum a student should need to decide whether to try a
/// mode. Anything longer belongs in a help article.
///
/// The sheet confirms with a single primary CTA ("Got it") — no
/// "Don't show again" toggle. Tapping Got it IS the "don't show
/// again" (we mark-seen and never present again). An explicit
/// toggle would imply the alternative exists and isn't necessary
/// for a component this small.
struct ModeDescriptionSheet: View {
    let description: ModeDescription
    let onContinue: () -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: BrandSpacing.xl) {
                    header
                    body(label: "What it's for", text: description.purpose)
                    body(label: "When to use it", text: description.whenToUse)
                    exampleCard

                    if let footnote = description.footnote {
                        footnoteView(footnote)
                    }
                }
                .padding(.horizontal, BrandSpacing.xl)
                .padding(.top, BrandSpacing.lg)
                .padding(.bottom, BrandSpacing.xl)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(BrandColor.background)
            .scrollBounceBehavior(.basedOnSize)
            .safeAreaInset(edge: .bottom) {
                BrandButton("Got it", style: .primary, action: acknowledge)
                    .padding(.horizontal, BrandSpacing.xl)
                    .padding(.vertical, BrandSpacing.md)
                    .background(BrandColor.background)
                    .accessibilityHint(
                        "Marks this explanation seen and continues into \(description.title) Mode"
                    )
            }
#if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
#endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close", action: dismiss.callAsFunction)
                        .accessibilityLabel("Close")
                        .accessibilityHint("Closes this explanation without continuing")
                }
            }
        }
        .tint(BrandColor.accent)
        // `.medium` detent keeps this lightweight — the user can
        // pull to `.large` if they want more breathing room at
        // accessibility Dynamic Type sizes.
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    // MARK: - Pieces

    private var header: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.xs) {
            Text(description.title)
                .font(BrandFont.largeTitle)
                .foregroundStyle(BrandColor.text)
                .fixedSize(horizontal: false, vertical: true)

            Text("Mode")
                .font(BrandFont.caption)
                .tracking(1.5)
                .foregroundStyle(BrandColor.textSecondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
        .accessibilityLabel("\(description.title) Mode")
    }

    private func body(label: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: BrandSpacing.xs) {
            Text(label.uppercased())
                .font(BrandFont.caption)
                .tracking(1.2)
                .foregroundStyle(BrandColor.textSecondary)

            Text(text)
                .font(BrandFont.body)
                .foregroundStyle(BrandColor.text)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var exampleCard: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.xs) {
            Text("TRY")
                .font(BrandFont.caption)
                .tracking(1.2)
                .foregroundStyle(BrandColor.textSecondary)

            HStack(alignment: .top, spacing: BrandSpacing.sm) {
                Rectangle()
                    .fill(BrandColor.accent)
                    .frame(width: 3)
                    .accessibilityHidden(true)

                Text("“\(description.example)”")
                    .font(BrandFont.body)
                    .italic()
                    .foregroundStyle(BrandColor.text)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.vertical, BrandSpacing.md)
                    .padding(.trailing, BrandSpacing.md)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(BrandColor.surface)
            .clipShape(RoundedRectangle(cornerRadius: BrandRadius.md, style: .continuous))
        }
    }

    private func footnoteView(_ text: String) -> some View {
        HStack(alignment: .top, spacing: BrandSpacing.sm) {
            Image(systemName: "lock.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(BrandColor.textSecondary)
                .accessibilityHidden(true)

            Text(text)
                .font(BrandFont.caption)
                .foregroundStyle(BrandColor.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(BrandSpacing.md)
        .background(BrandColor.surface)
        .clipShape(RoundedRectangle(cornerRadius: BrandRadius.md, style: .continuous))
    }

    // MARK: - Actions

    private func acknowledge() {
        ModeDescriptionStore.markSeen(description.mode)
        dismiss()
        onContinue()
    }
}

// MARK: - Previews

#Preview("Socratic") {
    Color.clear.sheet(isPresented: .constant(true)) {
        ModeDescriptionSheet(
            description: ModeDescription.description(for: .socratic),
            onContinue: { }
        )
    }
}

#Preview("Direct (locked)") {
    Color.clear.sheet(isPresented: .constant(true)) {
        ModeDescriptionSheet(
            description: ModeDescription.description(for: .direct),
            onContinue: { }
        )
    }
}

#Preview("Debate") {
    Color.clear.sheet(isPresented: .constant(true)) {
        ModeDescriptionSheet(
            description: ModeDescription.description(for: .debate),
            onContinue: { }
        )
    }
}
