import SwiftUI
import PhotosUI
import DesignSystem

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// Message composer. Grows with content up to 5 lines, then scrolls. Supports
/// attaching one photo (shown as a thumbnail above the field). Disables the
/// send button while a request is in flight.
struct ChatInputBar: View {
    @Binding var text: String
    let isSending: Bool
    let attachedImageData: Data?
    let onSend: () -> Void
    let onCancel: () -> Void
    let onAttachImage: (Data) -> Void
    let onRemoveAttachment: () -> Void

    @FocusState private var focused: Bool
    @State private var pickerItem: PhotosPickerItem?

    var body: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.sm) {
            if let data = attachedImageData, let image = Self.thumbnail(from: data) {
                attachmentPreview(image)
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

                actionButton
            }
        }
        .padding(.horizontal, BrandSpacing.lg)
        .padding(.vertical, BrandSpacing.sm)
        .background(BrandColor.background)
        .onChange(of: pickerItem) { _, newItem in
            loadPickedImage(newItem)
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

    private func attachmentPreview(_ image: Image) -> some View {
        ZStack(alignment: .topTrailing) {
            image
                .resizable()
                .scaledToFill()
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
        return (hasText || attachedImageData != nil) && !isSending
    }

    private func triggerSend() {
        guard canSend else { return }
        onSend()
    }

    private func loadPickedImage(_ item: PhotosPickerItem?) {
        guard let item else { return }
        Task {
            let data = try? await item.loadTransferable(type: Data.self)
            await MainActor.run {
                // Reset so the same photo can be picked again after removal.
                pickerItem = nil
                if let data {
                    onAttachImage(data)
                }
            }
        }
    }

    /// Decode raw image bytes into a SwiftUI `Image` for the thumbnail.
    private static func thumbnail(from data: Data) -> Image? {
        #if canImport(UIKit)
        return UIImage(data: data).map { Image(uiImage: $0) }
        #elseif canImport(AppKit)
        return NSImage(data: data).map { Image(nsImage: $0) }
        #else
        return nil
        #endif
    }
}
