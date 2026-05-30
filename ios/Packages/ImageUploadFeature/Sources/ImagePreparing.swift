import Foundation
import NetworkingKit

/// Turns raw picked image bytes into an upload-ready `ImageUploadInput`
/// (compressed + normalized + base64). Abstracted behind a protocol so the
/// ViewModel stays platform-agnostic and unit-testable: tests inject a stub,
/// production injects the UIKit-backed `JPEGImagePreparer`.
///
/// `Sendable` so the ViewModel can run preparation off the main actor.
public protocol ImagePreparing: Sendable {
    /// Decode, normalize (orientation), downscale if oversized, and JPEG-encode
    /// `imageData`, returning an upload-ready input. Throws
    /// `ImagePreparationError` if the bytes aren't a readable image or can't be
    /// brought under the size limit.
    func prepare(imageData: Data, fileName: String?) throws -> APIClient.ImageUploadInput
}

/// Why image preparation failed, with a user-facing message. Both cases are
/// non-retryable — re-running won't help an unreadable or too-big image.
public enum ImagePreparationError: Error, Equatable {
    case unreadableImage
    case tooLargeAfterCompression

    public var userMessage: String {
        switch self {
        case .unreadableImage:
            return "That file doesn't look like an image we can read. Try another."
        case .tooLargeAfterCompression:
            return "That image is too large to upload, even after compression. Try a smaller one."
        }
    }
}
