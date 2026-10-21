#if os(macOS)
import SwiftUI
import DesignSystem

/// The first-time mode explainer on the Mac, in Night Studio (SPEC.md
/// §5.4): a sheet on a lit surface, the mode's name as its title, then what
/// it's for, when to use it, and an example to try, set as the thing a
/// student would say (the "keep" face). One prominent "Got it" (Return);
/// Close (Escape) leaves without switching. The copy is the iPhone's
/// (`ModeDescription`), with the tutor named Merc (`NightModeCopy`).
struct NightModeExplainer: View {
    let description: ModeDescription
    let acknowledge: () -> Void
    let close: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: Night.Space.section) {
                    VStack(alignment: .leading, spacing: 6) {
                        NightEyebrow("Chat mode", systemImage: "bubble.left.and.text.bubble.right")
                        Text(description.title)
                            .nightFont(.display)
                            .foregroundStyle(Night.ink)
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(description.title) Mode")
                    .accessibilityAddTraits(.isHeader)

                    section("What it's for", text: NightModeCopy.purpose(description.mode))
                    section("When to use it", text: description.whenToUse)

                    VStack(alignment: .leading, spacing: 10) {
                        NightEyebrow("Try", color: Night.ink3)
                        Text("“\(description.example)”")
                            .nightFont(.keep)
                            .foregroundStyle(Night.ink)
                            .fixedSize(horizontal: false, vertical: true)
                            .textSelection(.enabled)
                    }
                    .padding(Night.Space.card)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .nightWash()
                    .nightLit(radius: Night.Radius.card)
                    .accessibilityElement(children: .combine)

                    if let footnote = description.footnote {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Image(systemName: "lock.fill")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(Night.ink3)
                                .accessibilityHidden(true)
                            Text(footnote)
                                .nightFont(.caption)
                                .foregroundStyle(Night.ink3)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .padding(.horizontal, 28)
                .padding(.top, 28)
                .padding(.bottom, 16)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollBounceBehavior(.basedOnSize)

            HStack(spacing: 12) {
                Spacer(minLength: 0)
                NightTextButton("Close", color: Night.ink2, action: close)
                    .keyboardShortcut(.cancelAction)
                    .help("Close without switching modes (Esc)")
                    .accessibilityHint("Closes this explanation without continuing")
                NightPrimaryButton("Got it", action: acknowledge)
                    .keyboardShortcut(.defaultAction)
                    .help("Switch to \(description.title) (Return)")
                    .accessibilityHint("Marks this explanation seen and continues into \(description.title) Mode")
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 18)
        }
        .background(NightCanvas(pools: .indigo, stars: false))
        .frame(minWidth: 460, idealWidth: 520, minHeight: 420, idealHeight: 500)
    }

    private func section(_ label: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            NightEyebrow(label, color: Night.ink3)
            Text(text)
                .nightFont(.body)
                .foregroundStyle(Night.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }
}
#endif
