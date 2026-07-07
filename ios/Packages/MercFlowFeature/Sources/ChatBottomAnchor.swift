import SwiftUI
import DesignSystem

/// Placement 2 — live chat: the message list, the "Got it — quiz me →" CTA, and
/// Merc peeking up from BEHIND the composer (clipped at his torso). Merc is
/// `.thinking` while a reply streams, `.idle` otherwise. From Part B §4b.
struct ChatBottomAnchor: View {
    @ObservedObject var vm: LessonViewModel

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(vm.messages) { MessageBubble(message: $0) }

                        // Revealed once the reply has finished (Merc back to idle).
                        if vm.merc != .thinking && !vm.messages.isEmpty {
                            Button { vm.goExercise() } label: {
                                Text("Got it — quiz me →")
                                    .font(.nunito(13.5, .black))
                                    .foregroundStyle(.white)
                                    .padding(.vertical, 13).padding(.horizontal, 24)
                                    .background(Brand.gradient, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
                            }
                            .padding(.top, 4)
                            .frame(maxWidth: .infinity)
                        }
                    }
                    .padding(.horizontal, 18).padding(.top, 14).padding(.bottom, 8)
                }
                .onChange(of: vm.messages.count) { _, _ in
                    withAnimation { proxy.scrollTo(vm.messages.last?.id, anchor: .bottom) }
                }
                .onChange(of: vm.messages.last?.text) { _, _ in
                    proxy.scrollTo(vm.messages.last?.id, anchor: .bottom)
                }
            }

            // Merc peeks from BEHIND one side of the composer (not over the
            // input) — Part C Bug 2. Drawn first = behind; offset off-centre to
            // the leading side so only his head shows past the bar's edge.
            ZStack(alignment: .bottom) {
                MercMascot(vm.merc, size: 116, placement: .free)
                    .frame(height: 64, alignment: .top).clipped()   // show only his top
                    .offset(x: -96, y: -26)                          // tucked behind the leading side
                    .onTapGesture { vm.wake() }
                Composer(text: $vm.input, onSend: vm.send)
            }
        }
    }
}

/// A chat bubble — Merc on the left (white card, soft shadow, notched top-left
/// `8/24/24/24`), user on the right (brand gradient, notched bottom-right).
struct MessageBubble: View {
    let message: ChatMessage
    private var isMerc: Bool { message.role == .merc }

    var body: some View {
        HStack(spacing: 0) {
            if !isMerc { Spacer(minLength: 44) }
            Text(message.text)
                .font(.nunito(13, .bold))
                .foregroundStyle(isMerc ? Brand.text : .white)
                .lineSpacing(4)
                .padding(.vertical, 12).padding(.horizontal, 15)
                .background {
                    if isMerc {
                        mercShape.fill(Brand.card)
                            .shadow(color: Color(hex: 0x3C3278).opacity(0.16), radius: 12, y: 6)
                    } else {
                        userShape.fill(Brand.gradient)
                    }
                }
            if isMerc { Spacer(minLength: 44) }
        }
    }

    private var mercShape: UnevenRoundedRectangle {
        UnevenRoundedRectangle(topLeadingRadius: 8, bottomLeadingRadius: 24,
                               bottomTrailingRadius: 24, topTrailingRadius: 24, style: .continuous)
    }
    private var userShape: UnevenRoundedRectangle {
        UnevenRoundedRectangle(topLeadingRadius: 24, bottomLeadingRadius: 24,
                               bottomTrailingRadius: 8, topTrailingRadius: 24, style: .continuous)
    }
}

/// The composer pill + photo icon + gradient send button. The background fades
/// to transparent at the top so the anchored Merc dissolves up into it.
struct Composer: View {
    @Binding var text: String
    var onSend: () -> Void

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: "photo")
                .font(.system(size: 22, weight: .regular))
                .foregroundStyle(Brand.accent)
                .frame(width: 36, height: 36)

            TextField("Ask Mercurius…", text: $text)
                .font(.nunito(13.5, .bold))
                .tint(Brand.accent)
                .padding(.horizontal, 17)
                .frame(height: 42)
                .background(Brand.card, in: Capsule())
                .overlay(Capsule().strokeBorder(Brand.accent.opacity(0.18), lineWidth: 1.5))

            Button(action: onSend) {
                Circle().fill(Brand.gradient).frame(width: 42, height: 42)
                    .overlay(Image(systemName: "arrow.up").font(.system(size: 16, weight: .heavy)).foregroundStyle(.white))
                    .shadow(color: Brand.accent.opacity(0.5), radius: 9, y: 6)
            }
        }
        .padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 14)
        .background(
            LinearGradient(colors: [Brand.bg, Brand.bg, Brand.bg.opacity(0)],
                           startPoint: .bottom, endPoint: .top)
        )
    }
}
