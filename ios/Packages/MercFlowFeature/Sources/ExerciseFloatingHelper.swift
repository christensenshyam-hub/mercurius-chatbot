import SwiftUI
import DesignSystem

/// Placement 3 — the exercise: a single MCQ check with a gradient CHECK button,
/// plus a floating 64px circular Merc "Need a hint?" FAB (tap toggles a hint
/// bubble). Correct → celebration; wrong → inline retry copy. From Part B §4c.
struct ExerciseFloatingHelper: View {
    @ObservedObject var vm: LessonViewModel
    @State private var picked: Int? = nil

    private let options = [
        ("It stores all the text it saw", false),
        ("It learns patterns to predict the next token", true),
        ("It copies sites into a database", false),
    ]

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            VStack(alignment: .leading, spacing: 11) {
                Text("CHECK · PICK ONE")
                    .font(.nunito(11, .heavy)).foregroundStyle(Brand.accent).kerning(0.4)
                Text("What best describes pre-training?")
                    .font(.nunito(21, .black)).foregroundStyle(Brand.text)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.bottom, 2)

                ForEach(options.indices, id: \.self) { i in
                    OptionRow(label: options[i].0, selected: picked == i) { picked = i }
                }

                if vm.showWrong {
                    Text("Not quite — it isn't storing the text. Try again, or tap Merc for a hint.")
                        .font(.nunito(12.5, .heavy)).foregroundStyle(Color(hex: 0xC23B3F))
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)

                Button { vm.answer(correct: options[picked ?? 0].1) } label: {
                    Text("CHECK").font(.nunito(14, .black)).foregroundStyle(.white)
                        .frame(maxWidth: .infinity).padding(.vertical, 15)
                        .background(Brand.gradient, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .disabled(picked == nil).opacity(picked == nil ? 0.5 : 1)
            }
            .padding(22)

            // Floating Merc helper.
            VStack(alignment: .trailing, spacing: 10) {
                if vm.hintOpen {
                    Text("Focus on what it's trained to *predict* each step — not what it keeps.")
                        .font(.nunito(12.5, .heavy)).foregroundStyle(Color(hex: 0x4A3FB0))
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(12)
                        .background(.white, in: UnevenRoundedRectangle(topLeadingRadius: 16, bottomLeadingRadius: 16,
                                                                        bottomTrailingRadius: 4, topTrailingRadius: 16,
                                                                        style: .continuous))
                        .frame(maxWidth: 210)
                        .shadow(color: Color(hex: 0x281A50).opacity(0.30), radius: 12, y: 6)
                } else {
                    Text("Need a hint?")
                        .font(.nunito(10.5, .black)).foregroundStyle(Brand.accent)
                        .padding(.vertical, 5).padding(.horizontal, 10)
                        .background(.white, in: Capsule())
                        .shadow(color: Color(hex: 0x281A50).opacity(0.24), radius: 8, y: 4)
                }

                Button { vm.toggleHint() } label: {
                    Circle().fill(.white)
                        .frame(width: 64, height: 64)
                        .overlay(MercMascot(vm.merc, size: 92).offset(y: 20))
                        .clipShape(Circle())
                        .shadow(color: Brand.accent.opacity(0.5), radius: 13, y: 10)
                }
                .buttonStyle(.plain)
            }
            .padding(.trailing, 18).padding(.bottom, 96)
        }
    }
}

/// One MCQ option card — white, soft shadow; selected gets an accent ring + tint.
struct OptionRow: View {
    let label: String
    let selected: Bool
    var onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 0) {
                Text(label)
                    .font(.nunito(13, .heavy)).foregroundStyle(Brand.text)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 0)
            }
            .padding(.vertical, 15).padding(.horizontal, 16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(selected ? Brand.accent.opacity(0.07) : Brand.card,
                        in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(selected ? Brand.accent : .clear, lineWidth: 2)
            )
            .shadow(color: Color(hex: 0x3C3278).opacity(0.10), radius: 9, y: 6)
        }
        .buttonStyle(.plain)
    }
}
