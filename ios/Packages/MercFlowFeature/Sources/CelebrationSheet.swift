import SwiftUI
import DesignSystem

/// Placement 4 — celebration takeover: a dimmed screen + a bottom sheet sliding
/// up, with Merc (`celebrate`, confetti) overflowing its top edge. Layout-driven
/// per Part C §4 — Merc is a non-clipped `overlay(alignment: .top)` so he bursts
/// out, with a `Spacer` reserving head room (no magic clipping).
struct CelebrationSheet: View {
    @ObservedObject var vm: LessonViewModel

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.black.opacity(0.35).ignoresSafeArea()

            sheet
                .overlay(alignment: .top) {
                    MercMascot(.celebrate, size: 168)
                        .offset(y: -96)               // half above the sheet
                        .allowsHitTesting(false)
                }
                .transition(.move(edge: .bottom))
        }
        .animation(.spring(response: 0.45, dampingFraction: 0.8), value: vm.stage)
    }

    private var sheet: some View {
        VStack(spacing: 6) {
            Spacer().frame(height: 64)                 // reserve room for the overflowing head
            Text("Nailed it!")
                .font(.nunito(26, .black)).foregroundStyle(Color(hex: 0x22A05B))
            Text("Pre-training learns patterns to predict the next token — nothing is copied.")
                .font(.nunito(13.5, .heavy)).foregroundStyle(Brand.subtext)
                .multilineTextAlignment(.center).padding(.horizontal, 20)
                .fixedSize(horizontal: false, vertical: true)
            Button { vm.finish() } label: {
                Text("CONTINUE").font(.nunito(15, .black)).foregroundStyle(.white)
                    .frame(maxWidth: .infinity).padding(.vertical, 16)
                    .background(Brand.gradient, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .padding(.top, 14)
        }
        .padding(24)
        .padding(.bottom, 8)
        .frame(maxWidth: .infinity)
        .background(
            UnevenRoundedRectangle(topLeadingRadius: 32, topTrailingRadius: 32, style: .continuous)
                .fill(.white)
                .ignoresSafeArea(edges: .bottom)
        )
    }
}

/// The flow's closing screen — a happy Merc, the lesson-complete summary, the
/// XP + streak chips, and a Replay control (mirrors the prototype's done screen).
struct DoneView: View {
    @ObservedObject var vm: LessonViewModel

    var body: some View {
        VStack(spacing: 20) {
            Spacer()
            MercMascot(.happy, size: 168)
            VStack(spacing: 6) {
                Text("Lesson complete!")
                    .font(.nunito(24, .black)).foregroundStyle(Brand.text)
                Text("6 of 8 through Unit 01")
                    .font(.nunito(13.5, .heavy)).foregroundStyle(Brand.subtext)
            }
            HStack(spacing: 12) {
                statChip(systemImage: "sparkles", text: "+15 XP", tint: Color(hex: 0xE09600))
                statChip(systemImage: "flame.fill", text: "5-day streak", tint: Color(hex: 0xF5731E))
            }
            Spacer()
            Button { vm.restart() } label: {
                Text("Replay flow ↺").font(.nunito(14, .black)).foregroundStyle(Brand.accent)
                    .padding(.vertical, 14).padding(.horizontal, 28)
                    .background(Brand.accent.opacity(0.10), in: Capsule())
            }
            .padding(.bottom, 36)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func statChip(systemImage: String, text: String, tint: Color) -> some View {
        HStack(spacing: 6) {
            Image(systemName: systemImage).font(.system(size: 13, weight: .bold)).foregroundStyle(tint)
            Text(text).font(.nunito(13, .heavy)).foregroundStyle(Brand.text)
        }
        .padding(.vertical, 8).padding(.horizontal, 14)
        .background(Brand.card, in: Capsule())
        .shadow(color: Color(hex: 0x3C3278).opacity(0.10), radius: 8, y: 4)
    }
}
