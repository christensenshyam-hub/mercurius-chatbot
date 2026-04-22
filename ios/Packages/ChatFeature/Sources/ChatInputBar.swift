import SwiftUI
import DesignSystem

/// Message composer. Grows with content up to 5 lines, then scrolls.
/// Disables the send button while a request is in flight.
struct ChatInputBar: View {
    @Binding var text: String
    let isSending: Bool
    let onSend: () -> Void
    let onCancel: () -> Void

    @FocusState private var focused: Bool

    var body: some View {
        HStack(alignment: .bottom, spacing: BrandSpacing.sm) {
            TextField("Ask Mercurius…", text: $text, axis: .vertical)
                .lineLimit(1...5)
                .font(BrandFont.body)
                .foregroundStyle(BrandColor.text)
                .tint(BrandColor.accent)
                .padding(.vertical, 10)
                .padding(.horizontal, BrandSpacing.md)
                .background(BrandColor.surfaceElevated)
                .clipShape(RoundedRectangle(cornerRadius: BrandRadius.xl))
                .overlay(
                    RoundedRectangle(cornerRadius: BrandRadius.xl)
                        .stroke(focused ? BrandColor.accent : BrandColor.border, lineWidth: 1)
                )
                .focused($focused)
                .submitLabel(.send)
                .onSubmit(triggerSend)
                .accessibilityLabel("Message")

            actionButton
        }
        .padding(.horizontal, BrandSpacing.lg)
        .padding(.vertical, BrandSpacing.sm)
        .background(BrandColor.background)
    }

    private var actionButton: some View {
        Group {
            if isSending {
                Button(action: onCancel) {
                    Image(systemName: "stop.circle.fill")
                        .resizable()
                        .frame(width: 36, height: 36)
                        .foregroundStyle(BrandColor.textSecondary)
                }
                .accessibilityLabel("Stop replying")
            } else {
                Button(action: triggerSend) {
                    Image(systemName: "arrow.up.circle.fill")
                        .resizable()
                        .frame(width: 36, height: 36)
                        .foregroundStyle(canSend ? BrandColor.accent : BrandColor.textSecondary.opacity(0.5))
                }
                .disabled(!canSend)
                .accessibilityLabel("Send")
            }
        }
        .frame(minWidth: 44, minHeight: 44)
    }

    private var canSend: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isSending
    }

    private func triggerSend() {
        guard canSend else { return }
        onSend()
    }
}
