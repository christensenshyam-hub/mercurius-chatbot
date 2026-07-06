import SwiftUI
import DesignSystem

/// Placement 1 — the lesson intro: Merc grounded bottom-left, a tailed white
/// bubble above-right, a CONTINUE CTA. From `MERC_HANDOFF.md` Part B §4a.
struct IntroSpeechBubble: View {
    @ObservedObject var vm: LessonViewModel
    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            SpeechBubble {
                VStack(alignment: .leading, spacing: 7) {
                    Text("LESSON 2 · PRE-TRAINING")
                        .font(.nunito(11, .black)).foregroundStyle(Brand.accent).kerning(0.5)
                    Text("Hey — ready to find out how a model actually learns? I'll explain, then quiz you.")
                        .font(.nunito(15, .heavy)).foregroundStyle(Brand.text)
                }
            }
            .padding(.horizontal, 24).padding(.bottom, 4)

            HStack(alignment: .bottom) {
                MercMascot(vm.merc, size: 176)           // grounded bottom-left
                    .onTapGesture { vm.wake() }
                Spacer()
                Button { vm.startChat() } label: {
                    Text("CONTINUE").font(.nunito(14, .black)).kerning(0.4)
                        .foregroundStyle(.white)
                        .padding(.vertical, 15).padding(.horizontal, 26)
                        .background(Brand.gradient, in: RoundedRectangle(cornerRadius: 16))
                }
                .padding(.trailing, 22).padding(.bottom, 30)
            }
        }
    }
}

/// Tailed bubble (tail bottom-left, pointing at Merc). From Part B §4a.
struct SpeechBubble<C: View>: View {
    @ViewBuilder var content: C
    var body: some View {
        content.padding(18)
            .background(.white, in: RoundedRectangle(cornerRadius: 22))
            .overlay(RoundedRectangle(cornerRadius: 22).stroke(Brand.accent.opacity(0.16), lineWidth: 2))
            .overlay(alignment: .bottomLeading) {
                Rectangle().fill(.white).frame(width: 16, height: 16)
                    .rotationEffect(.degrees(45)).offset(x: 48, y: 8)
                    .overlay(Rectangle().stroke(Brand.accent.opacity(0.16), lineWidth: 2)
                        .rotationEffect(.degrees(45)).offset(x: 48, y: 8))
            }
            .shadow(color: Color(hex: 0x3C3278).opacity(0.25), radius: 16, y: 10)
    }
}
