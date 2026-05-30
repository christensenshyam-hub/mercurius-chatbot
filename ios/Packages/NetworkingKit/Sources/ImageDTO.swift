import Foundation

extension APIClient {
    /// A prepared image, ready to upload. The feature layer (which owns UIKit)
    /// compresses/normalizes a picked photo into base64 + a declared content
    /// type before handing it here. Keeping this UI-free lets `NetworkingKit`
    /// stay free of UIKit and unit-testable with stub data.
    public struct ImageUploadInput: Sendable, Equatable {
        public let contentType: String
        public let base64Data: String
        public let fileName: String?

        public init(contentType: String, base64Data: String, fileName: String? = nil) {
            self.contentType = contentType
            self.base64Data = base64Data
            self.fileName = fileName
        }
    }

    /// Stable descriptor for a stored image, returned by `POST /api/images`.
    /// `url` is server-relative (e.g. `/api/images/<id>`); resolve it to an
    /// absolute URL with `APIClient.imageURL(for:)`. Future v3 features key off
    /// `id`.
    ///
    /// Field names match the backend JSON exactly — the client decodes with a
    /// default `JSONDecoder` (no key conversion), so `contentType`, `fileName`,
    /// and `createdAt` must stay camelCase. `createdAt` is an ISO-8601 string.
    public struct ImageUploadResponse: Decodable, Sendable, Equatable, Identifiable {
        public let id: String
        public let url: String
        public let contentType: String
        public let fileName: String?
        public let size: Int
        public let createdAt: String

        public init(
            id: String,
            url: String,
            contentType: String,
            fileName: String?,
            size: Int,
            createdAt: String
        ) {
            self.id = id
            self.url = url
            self.contentType = contentType
            self.fileName = fileName
            self.size = size
            self.createdAt = createdAt
        }
    }
}

/// Client-side upload limits — a single source of truth mirrored from the
/// backend (`lib/schemas.js`). The feature layer validates against these
/// before calling the client so users get instant feedback instead of a
/// round-trip rejection.
public enum ImageUploadLimits {
    /// Content types the backend accepts. The client normalizes captures to
    /// JPEG, so real uploads are almost always `image/jpeg`.
    public static let allowedContentTypes: Set<String> = [
        "image/jpeg", "image/png", "image/webp", "image/gif",
    ]

    /// Max decoded image size the backend accepts (8 MB). The client compresses
    /// to comfortably under this before uploading.
    public static let maxBytes: Int = 8 * 1024 * 1024

    public static func isAllowed(contentType: String) -> Bool {
        allowedContentTypes.contains(contentType.lowercased())
    }
}
