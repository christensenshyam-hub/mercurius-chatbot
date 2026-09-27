import SwiftUI
import PhotosUI
import DesignSystem

/// Message composer. Grows with content up to 5 lines, then scrolls. Supports
/// attaching one photo (shown as a thumbnail above the field). Disables the
/// send button while a request is in flight or a photo is still preparing.
/// Holds at most `characterLimit` characters — what the server reads — and
/// says so when a paste is cut.
struct ChatInputBar: View {
    @Binding var text: String
    let isSending: Bool
    let attachment: ChatImage?
    let isPreparingAttachment: Bool
    /// Why the last picked photo couldn't be attached.
    let attachmentError: String?
    let characterLimit: Int
    let onSend: () -> Void
    let onCancel: () -> Void
    let onAttachImage: (Data) -> Void
    let onRemoveAttachment: () -> Void
    /// When true, the send button becomes the "Playful" 42pt circle filled with
    /// the brand gradient (lesson screen). Defaults off so free chat is unchanged.
    var useBrandSend: Bool = false
    /// When true, the bar's background fades to transparent at the top so a
    /// mascot anchored behind it dissolves in (lesson screen). Defaults off.
    var backgroundFade: Bool = false
    /// Increment to programmatically focus the text field (e.g. tapping the
    /// lesson check-question callout). A counter rather than a Bool so every
    /// tap re-focuses even if the field was focused-then-dismissed.
    var focusTrigger: Int = 0

    @FocusState private var focused: Bool
    @State private var pickerItem: PhotosPickerItem?
    /// A picked photo failed to load (e.g. an iCloud-optimized original while
    /// offline, or a corrupt asset). Without this the picker dismisses and
    /// nothing appears — which reads as "the attach button is broken."
    @State private var attachLoadFailed = false
    /// The last edit (a paste) went over `characterLimit` and was cut.
    @State private var wasCut = false

    var body: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.sm) {
            if isPreparingAttachment {
                preparingPreview
            } else if let attachment {
                attachmentPreview(attachment)
            }

            if attachLoadFailed {
                attachmentFailure("Couldn't load that photo. Try again.") { attachLoadFailed = false }
            } else if let attachmentError {
                attachmentFailure(attachmentError, clear: onRemoveAttachment)
            }

            if let note = ComposerLimit.note(count: text.utf16.count, limit: characterLimit, wasCut: wasCut) {
                Text(note)
                    .font(BrandFont.caption)
                    .foregroundStyle(wasCut ? BrandColor.error : BrandColor.textSecondary)
                    .monospacedDigit()
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .accessibilityIdentifier("composer.limit")
            }

            HStack(alignment: .bottom, spacing: BrandSpacing.sm) {
                photoButton

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
                    .onChange(of: focusTrigger) { _, _ in focused = true }

                actionButton
            }
        }
        .padding(.horizontal, BrandSpacing.lg)
        .padding(.vertical, BrandSpacing.sm)
        .background { composerBackground }
        .onChange(of: pickerItem) { _, newItem in
            loadPickedImage(newItem)
        }
        .onChange(of: text) { _, newText in
            let kept = ChatViewModel.clamped(newText, toUTF16: characterLimit)
            if kept.utf16.count < newText.utf16.count {
                wasCut = true
                text = kept
            } else if newText.utf16.count < characterLimit {
                wasCut = false
            }
        }
    }

    /// Transient: clears itself after a few seconds (a new pick clears it
    /// at once).
    private func attachmentFailure(_ message: String, clear: @escaping () -> Void) -> some View {
        Text(message)
            .font(BrandFont.caption)
            .foregroundStyle(BrandColor.error)
            .padding(.leading, 44)  // align past the photo button
            .task(id: message) {
                try? await Task.sleep(for: .seconds(3))
                guard !Task.isCancelled else { return }
                clear()
            }
    }

    @ViewBuilder private var composerBackground: some View {
        if backgroundFade {
            // Solid at the bottom, fading to transparent at the top so an
            // anchored Merc behind the bar dissolves up into it.
            LinearGradient(
                colors: [BrandColor.background, BrandColor.background, BrandColor.background.opacity(0)],
                startPoint: .bottom, endPoint: .top
            )
        } else {
            BrandColor.background
        }
    }

    private var photoButton: some View {
        PhotosPicker(selection: $pickerItem, matching: .images) {
            Image(systemName: "photo")
                .font(.system(size: 22, weight: .regular))
                .foregroundStyle(isSending ? BrandColor.textSecondary.opacity(0.5) : BrandColor.accent)
                .frame(width: 36, height: 36)
        }
        .frame(minWidth: 44, minHeight: 44)
        .disabled(isSending)
        .accessibilityLabel("Attach photo")
    }

    private var preparingPreview: some View {
        RoundedRectangle(cornerRadius: BrandRadius.md)
            .fill(BrandColor.surfaceElevated)
            .frame(width: 64, height: 64)
            .overlay(ProgressView())
            .overlay(
                RoundedRectangle(cornerRadius: BrandRadius.md)
                    .stroke(BrandColor.border, lineWidth: 1)
            )
            .padding(.leading, 44)  // align past the photo button
            .accessibilityElement()
            .accessibilityLabel("Attaching photo")
    }

    private func attachmentPreview(_ attachment: ChatImage) -> some View {
        ZStack(alignment: .topTrailing) {
            Group {
                if let preview = attachment.preview {
                    Image(preview, scale: 1, label: Text("Attached photo"))
                        .resizable()
                        .scaledToFill()
                } else {
                    Image(systemName: "photo")
                        .font(.system(size: 24))
                        .foregroundStyle(BrandColor.textSecondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(BrandColor.surfaceElevated)
                        .accessibilityLabel("Attached photo")
                }
            }
            .frame(width: 64, height: 64)
            .clipShape(RoundedRectangle(cornerRadius: BrandRadius.md))
            .overlay(
                RoundedRectangle(cornerRadius: BrandRadius.md)
                    .stroke(BrandColor.border, lineWidth: 1)
            )

            Button(action: onRemoveAttachment) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 20))
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, .black.opacity(0.5))
            }
            .padding(4)
            .accessibilityLabel("Remove photo")
        }
        .padding(.leading, 44)  // align past the photo button
        .accessibilityElement(children: .contain)
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
            } else if useBrandSend {
                Button(action: triggerSend) {
                    Circle()
                        .fill(BrandGradient.merc)
                        .frame(width: 42, height: 42)
                        .overlay(
                            Image(systemName: "arrow.up")
                                .font(.system(size: 16, weight: .heavy))
                                .foregroundStyle(.white)
                        )
                        .shadow(color: BrandColor.accent.opacity(0.5), radius: 9, y: 6)
                        .opacity(canSend ? 1 : 0.45)
                }
                .disabled(!canSend)
                .accessibilityLabel("Send")
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
        let hasText = !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return (hasText || attachment != nil) && !isSending && !isPreparingAttachment
    }

    private func triggerSend() {
        guard canSend else { return }
        onSend()
    }

    private func loadPickedImage(_ item: PhotosPickerItem?) {
        guard let item else { return }
        attachLoadFailed = false  // a fresh pick supersedes any prior failure note
        Task {
            let data = try? await item.loadTransferable(type: Data.self)
            await MainActor.run {
                // Reset so the same photo can be picked again after removal.
                pickerItem = nil
                if let data {
                    onAttachImage(data)
                } else {
                    // `loadTransferable` throws / returns nil for iCloud-
                    // optimized originals while offline and for corrupt
                    // assets — surface it instead of silently doing nothing.
                    attachLoadFailed = true
                }
            }
        }
    }
}

/// The composer's length note (pure; covered by ComposerLimitTests).
enum ComposerLimit {
    /// How close to the limit the counter appears.
    static let counterLead = 200

    /// Nil while the draft is comfortably short.
    static func note(count: Int, limit: Int, wasCut: Bool) -> String? {
        if wasCut {
            return "Only the first \(limit.formatted()) characters will be sent."
        }
        guard count >= limit - counterLead else { return nil }
        return "\(count.formatted()) / \(limit.formatted())"
    }
}
