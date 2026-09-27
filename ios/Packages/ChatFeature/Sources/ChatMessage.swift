import Foundation
import CoreGraphics
import ImageIO
import NetworkingKit

/// In-memory chat message model used by the view layer. Distinct from
/// `ChatMessageDTO` (wire format) so the UI layer isn't coupled to
/// server JSON shape.
public struct ChatMessage: Identifiable, Equatable, Sendable {
    public enum Role: String, Sendable {
        case user
        case assistant
    }

    /// Per-message state for progressive disclosure during streaming.
    public enum Status: Equatable, Sendable {
        /// Normal, no streaming in progress.
        case idle
        /// Assistant message is receiving deltas.
        case streaming
        /// A request failed. Error message is shown under the bubble.
        case failed(reason: String)
    }

    public let id: UUID
    public let role: Role
    public var content: String
    public let createdAt: Date
    public var status: Status

    /// An attached photo, shown inline in the bubble. In-memory only (not
    /// persisted), and never part of the wire `dto` — the image reaches the
    /// server out-of-band via the upload pipeline + the chat request's
    /// `imageId`.
    public var image: ChatImage?

    public init(
        id: UUID = UUID(),
        role: Role,
        content: String,
        createdAt: Date = Date(),
        status: Status = .idle,
        image: ChatImage? = nil
    ) {
        self.id = id
        self.role = role
        self.content = content
        self.createdAt = createdAt
        self.status = status
        self.image = image
    }

    /// Map to the DTO sent to the server. Text only — the image travels via the
    /// chat request's `imageId`, not the message body.
    public var dto: ChatMessageDTO {
        ChatMessageDTO(role: role.rawValue, content: content)
    }
}

/// A photo attachment, prepared once off the main actor from the picked
/// original: a decoded, display-sized preview and the upload JPEG. The
/// original bytes are dropped once this exists, so no view body decodes them
/// and Retry never needs them. Immutable; compared by identity.
public final class ChatImage: @unchecked Sendable, Equatable {
    /// Longest edge of `preview`, in pixels: the sent-photo bubble is at most
    /// 280pt tall, 840px at 3x.
    static let previewMaxPixelSize = 840

    /// Nil when the bytes could be prepared for upload but not previewed.
    public let preview: CGImage?
    let upload: APIClient.ImageUploadInput

    init(preview: CGImage?, upload: APIClient.ImageUploadInput) {
        self.preview = preview
        self.upload = upload
    }

    public static func == (lhs: ChatImage, rhs: ChatImage) -> Bool { lhs === rhs }

    /// Downsample and prepare the upload. Slow for a large photo — call it
    /// off the main actor.
    static func prepare(_ data: Data, preparer: ImagePreparing) throws -> ChatImage {
        let upload = try preparer.prepare(imageData: data, fileName: nil)
        return ChatImage(preview: previewImage(from: data), upload: upload)
    }

    static func previewImage(from data: Data, maxPixelSize: Int = previewMaxPixelSize) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              CGImageSourceGetCount(source) > 0 else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            // Decode now, on this thread, not on the first draw.
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }
}
