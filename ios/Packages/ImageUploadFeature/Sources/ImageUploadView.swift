import SwiftUI
import PhotosUI
import DesignSystem
import NetworkingKit

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// The image-upload screen: pick a photo, preview it, upload it, and see clear
/// loading / success / failure states with retry. Owns its `@Observable`
/// ViewModel via `@State`, matching the `ChatView` pattern. The upload pipeline
/// (validation, compression, networking, state) lives in `ImageUploadViewModel`
/// — this view is presentation only.
public struct ImageUploadView: View {
    @State private var viewModel: ImageUploadViewModel
    @State private var pickerItem: PhotosPickerItem?
    @State private var isLoadingSelection = false

    /// Construct the screen and its ViewModel from the shared clients.
    public init(apiClient: APIClient, sessionIdentity: SessionIdentity) {
        _viewModel = State(initialValue: ImageUploadViewModel(apiClient: apiClient, sessionIdentity: sessionIdentity))
    }

    /// Inject an existing ViewModel (composition root / previews / tests).
    public init(model: ImageUploadViewModel) {
        _viewModel = State(initialValue: model)
    }

    public var body: some View {
        ScrollView {
            VStack(spacing: BrandSpacing.xl) {
                preview
                picker
                if viewModel.selectedImageData != nil {
                    uploadControls
                }
                status
            }
            .padding(BrandSpacing.lg)
            .frame(maxWidth: .infinity)
        }
        .background(BrandColor.background.ignoresSafeArea())
        .navigationTitle("Upload Image")
        .onChange(of: pickerItem) { _, newItem in
            handlePickerChange(newItem)
        }
    }

    // MARK: - Preview

    @ViewBuilder
    private var preview: some View {
        ZStack {
            RoundedRectangle(cornerRadius: BrandRadius.lg, style: .continuous)
                .fill(BrandColor.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: BrandRadius.lg, style: .continuous)
                        .strokeBorder(BrandColor.border, style: StrokeStyle(lineWidth: 1, dash: [6]))
                )

            if let data = viewModel.selectedImageData, let image = Self.decodedImage(from: data) {
                image
                    .resizable()
                    .scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: BrandRadius.lg, style: .continuous))
                    .accessibilityLabel("Selected image preview")
            } else if isLoadingSelection {
                ProgressView()
            } else {
                VStack(spacing: BrandSpacing.sm) {
                    Image(systemName: "photo.on.rectangle.angled")
                        .font(.system(size: 40, weight: .light))
                        .foregroundStyle(BrandColor.textSecondary)
                    Text("No image selected")
                        .font(BrandFont.caption)
                        .foregroundStyle(BrandColor.textSecondary)
                }
                .accessibilityElement(children: .combine)
            }

            // Dim + spinner overlay while uploading so the preview reads as busy.
            if viewModel.isUploading {
                RoundedRectangle(cornerRadius: BrandRadius.lg, style: .continuous)
                    .fill(.black.opacity(0.25))
                ProgressView()
                    .tint(.white)
            }
        }
        .frame(height: 280)
        .frame(maxWidth: .infinity)
    }

    // MARK: - Picker

    private var picker: some View {
        // Resolve the title here (main-actor context) and capture the String so
        // the PhotosPicker label closure doesn't read main-actor state itself.
        let title = viewModel.selectedImageData == nil ? "Choose Photo" : "Choose a Different Photo"
        return PhotosPicker(selection: $pickerItem, matching: .images) {
            Label(title, systemImage: "photo")
                .font(BrandFont.bodyEmphasized)
                .frame(maxWidth: .infinity, minHeight: 44)
                .padding(.horizontal, BrandSpacing.lg)
                .foregroundStyle(BrandColor.accent)
                .background(BrandColor.accent.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: BrandRadius.lg, style: .continuous))
        }
        .disabled(viewModel.isUploading)
    }

    // MARK: - Upload controls

    @ViewBuilder
    private var uploadControls: some View {
        if viewModel.isUploading {
            BrandButton("Cancel", style: .secondary) {
                viewModel.cancel()
            }
        } else {
            BrandButton("Upload", style: .primary, isEnabled: viewModel.canUpload) {
                viewModel.upload()
            }
        }
    }

    // MARK: - Status

    @ViewBuilder
    private var status: some View {
        switch viewModel.phase {
        case .uploading:
            Label("Uploading…", systemImage: "arrow.up.circle")
                .font(BrandFont.caption)
                .foregroundStyle(BrandColor.textSecondary)

        case let .uploaded(response):
            VStack(spacing: BrandSpacing.xs) {
                Label("Uploaded", systemImage: "checkmark.circle.fill")
                    .font(BrandFont.bodyEmphasized)
                    .foregroundStyle(BrandColor.success)
                Text("\(formattedSize(response.size)) · \(response.contentType)")
                    .font(BrandFont.caption)
                    .foregroundStyle(BrandColor.textSecondary)
            }
            .accessibilityElement(children: .combine)

        case let .failed(reason, isRetryable):
            VStack(spacing: BrandSpacing.sm) {
                Label(reason, systemImage: "exclamationmark.triangle.fill")
                    .font(BrandFont.caption)
                    .foregroundStyle(BrandColor.error)
                    .multilineTextAlignment(.center)
                if isRetryable {
                    BrandButton("Retry", style: .secondary) {
                        viewModel.retry()
                    }
                }
            }

        case .idle:
            EmptyView()
        }
    }

    // MARK: - Helpers

    private func handlePickerChange(_ newItem: PhotosPickerItem?) {
        guard let newItem else { return }
        isLoadingSelection = true
        Task {
            let data = try? await newItem.loadTransferable(type: Data.self)
            await MainActor.run {
                isLoadingSelection = false
                if let data {
                    // PhotosPickerItem doesn't expose a file name; nil is fine.
                    viewModel.select(data: data, fileName: nil)
                }
            }
        }
    }

    private func formattedSize(_ bytes: Int) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }

    /// Decode raw image bytes into a SwiftUI `Image` for preview, using the
    /// platform's image type. Returns nil if the bytes aren't a displayable
    /// image.
    private static func decodedImage(from data: Data) -> Image? {
        #if canImport(UIKit)
        return UIImage(data: data).map { Image(uiImage: $0) }
        #elseif canImport(AppKit)
        return NSImage(data: data).map { Image(nsImage: $0) }
        #else
        return nil
        #endif
    }
}
