import Foundation
import Observation
import OSLog
import NetworkingKit

/// Diagnostics logger. Logs upload lifecycle metadata only — never the image
/// bytes and never the session id/token.
private let uploadLog = Logger(subsystem: "com.mayoailiteracy.mercurius", category: "ImageUpload")

/// View model for the image-upload screen.
///
/// Lifecycle:
/// - `select(data:fileName:)` — the picker handed us bytes; hold them for
///   preview and move to `.idle` (ready to upload).
/// - `upload()` — prepare (compress/normalize off the main actor) then POST.
/// - `retry()` — re-run the last upload after a failure.
/// - `clearSelection()` — drop the picked image and reset.
///
/// State machine:
/// ```
/// idle ──upload()──▶ uploading ──▶ uploaded(response)
///                        └────────▶ failed(reason, isRetryable)
/// failed ──retry()──▶ uploading ...
/// ```
///
/// Duplicate uploads are guarded two ways: `upload()` is a no-op while a
/// request is in flight, and the View disables its button via `canUpload`.
///
/// Isolated to the main actor — all state reads/writes happen on main; only
/// the CPU-bound preparation and the network call hop off it.
@MainActor
@Observable
public final class ImageUploadViewModel {
    // MARK: - Observable state

    public private(set) var phase: Phase = .idle

    /// Raw bytes of the currently-selected image, kept for preview. Nil until
    /// the user picks something. Not the *uploaded* bytes — those are
    /// re-encoded during `upload()`.
    public private(set) var selectedImageData: Data?

    /// Original file name from the picker, if any. Surfaced in the UI and sent
    /// as metadata.
    public private(set) var selectedFileName: String?

    public enum Phase: Equatable, Sendable {
        /// Nothing in flight. May or may not have a selection.
        case idle
        /// Preparing + uploading.
        case uploading
        /// Upload succeeded. Carries the stable server descriptor that future
        /// v3 features reuse.
        case uploaded(APIClient.ImageUploadResponse)
        /// The last upload failed. `reason` is safe to show; `isRetryable`
        /// drives the Retry button.
        case failed(reason: String, isRetryable: Bool)
    }

    // MARK: - Dependencies

    private let uploader: ImageUploading
    private let preparer: ImagePreparing
    private let sessionIdProvider: @Sendable () throws -> String

    // MARK: - Private

    private var uploadTask: Task<Void, Never>?

    // MARK: - Init

    /// Designated initializer — inject stubs in tests, a fixed session id, and
    /// a fake preparer.
    public init(
        uploader: ImageUploading,
        preparer: ImagePreparing,
        sessionIdProvider: @escaping @Sendable () throws -> String
    ) {
        self.uploader = uploader
        self.preparer = preparer
        self.sessionIdProvider = sessionIdProvider
    }

    /// Production initializer — wires the real `APIClient`, the ImageIO-backed
    /// JPEG preparer, and the Keychain session identity.
    public convenience init(apiClient: APIClient, sessionIdentity: SessionIdentity) {
        self.init(
            uploader: apiClient,
            preparer: JPEGImagePreparer(),
            sessionIdProvider: { try sessionIdentity.current() }
        )
    }

    // MARK: - Derived state (for the View)

    public var isUploading: Bool {
        if case .uploading = phase { return true }
        return false
    }

    /// True when there's a selection and nothing is in flight.
    public var canUpload: Bool {
        selectedImageData != nil && !isUploading
    }

    public var uploadedResponse: APIClient.ImageUploadResponse? {
        if case let .uploaded(response) = phase { return response }
        return nil
    }

    public var failureReason: String? {
        if case let .failed(reason, _) = phase { return reason }
        return nil
    }

    public var canRetry: Bool {
        if case let .failed(_, isRetryable) = phase { return isRetryable }
        return false
    }

    // MARK: - Actions

    /// The picker delivered bytes. Hold them for preview and reset to a ready
    /// state, dropping any prior upload result/error.
    public func select(data: Data, fileName: String?) {
        uploadTask?.cancel()
        uploadTask = nil
        selectedImageData = data
        selectedFileName = fileName
        phase = .idle
    }

    /// Drop the selection and any result. Returns to a clean slate.
    public func clearSelection() {
        uploadTask?.cancel()
        uploadTask = nil
        selectedImageData = nil
        selectedFileName = nil
        phase = .idle
    }

    /// The picker handed us an item but its data couldn't be loaded (e.g. an
    /// iCloud asset that failed to download, or an unsupported item). Surface a
    /// clear, non-retryable error instead of silently doing nothing.
    public func handleSelectionFailure() {
        uploadLog.error("photo selection failed to load")
        selectedImageData = nil
        selectedFileName = nil
        phase = .failed(reason: "Couldn't load that photo. Pick a different one.", isRetryable: false)
    }

    /// Prepare + upload the selected image. No-op without a selection or while
    /// an upload is already in flight (the duplicate-upload guard).
    public func upload() {
        guard let data = selectedImageData else { return }
        if case .uploading = phase { return }

        phase = .uploading
        let fileName = selectedFileName
        let preparer = self.preparer
        let uploader = self.uploader

        uploadTask = Task { [weak self] in
            await self?.runUpload(data: data, fileName: fileName, preparer: preparer, uploader: uploader)
        }
    }

    /// Retry after a failure. No-op unless currently failed (and retryable).
    public func retry() {
        guard case let .failed(_, isRetryable) = phase, isRetryable else { return }
        upload()
    }

    /// Cancel an in-flight upload and return to a ready state. The selection is
    /// kept so the user can try again.
    public func cancel() {
        guard isUploading else { return }
        uploadTask?.cancel()
        uploadTask = nil
        phase = .idle
    }

    // MARK: - Upload pipeline

    private func runUpload(
        data: Data,
        fileName: String?,
        preparer: ImagePreparing,
        uploader: ImageUploading
    ) async {
        // Resolve the session ("auth") first — cheap, and a clear failure if
        // the Keychain is unavailable.
        let sessionId: String
        do {
            sessionId = try sessionIdProvider()
        } catch {
            setFailed(reason: "Could not resolve your session. Please restart the app.", isRetryable: false)
            return
        }

        // Compress / normalize off the main actor so the UI stays responsive.
        let input: APIClient.ImageUploadInput
        do {
            input = try await Task.detached(priority: .userInitiated) {
                try preparer.prepare(imageData: data, fileName: fileName)
            }.value
        } catch let error as ImagePreparationError {
            setFailed(reason: error.userMessage, isRetryable: false)
            return
        } catch {
            setFailed(reason: "Couldn't process that image. Try another.", isRetryable: false)
            return
        }

        if Task.isCancelled { return }

        // Metadata only — never the image bytes, never the session id/token.
        let approxKB = (input.base64Data.count * 3 / 4) / 1024
        uploadLog.info("uploading image: type=\(input.contentType, privacy: .public), ~\(approxKB)KB")

        do {
            let response = try await uploader.uploadImage(input, sessionId: sessionId)
            if Task.isCancelled { return }
            uploadLog.info("image upload succeeded: id=\(response.id, privacy: .public), size=\(response.size)")
            phase = .uploaded(response)
        } catch let error as APIError {
            setFailed(reason: error.userFacingMessage, isRetryable: error.isRetryable)
        } catch is CancellationError {
            // User cancelled — `cancel()` already reset the phase.
        } catch {
            setFailed(reason: "Something went wrong. Try again.", isRetryable: true)
        }
    }

    private func setFailed(reason: String, isRetryable: Bool) {
        // `reason` is an app-generated user message (no bytes, no token).
        uploadLog.error("image upload failed (retryable=\(isRetryable, privacy: .public)): \(reason, privacy: .public)")
        phase = .failed(reason: reason, isRetryable: isRetryable)
    }
}
