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

    var body: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.sm) {
            if let data = attachedImageData, let image = Self.thumbnail(from: data) {
                attachmentPreview(image)
            }

            if attachLoadFailed {
                Text("Couldn't load that photo. Try again.")
                    .font(BrandFont.caption)
                    .foregroundStyle(BrandColor.error)
                    .padding(.leading, 44)  // align past the photo button
                    .task {
                        // Transient: auto-clear after a few seconds (a new
                        // picker interaction also clears it immediately).
                        try? await Task.sleep(for: .seconds(3))
                        attachLoadFailed = false
                    }
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
        return (hasText || attachedImageData != nil) && !isSending
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
