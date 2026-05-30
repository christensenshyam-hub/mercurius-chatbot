import Foundation

/// Narrow protocol for uploading images. The image-upload ViewModel depends on
/// this (not the concrete `APIClient`) so tests can inject a stub instead of
/// hitting the network — mirrors `ModeChanging` / `ChatStreaming`.
public protocol ImageUploading: Sendable {
    func uploadImage(
        _ input: APIClient.ImageUploadInput,
        sessionId: String
    ) async throws -> APIClient.ImageUploadResponse
}

extension APIClient: ImageUploading {}
