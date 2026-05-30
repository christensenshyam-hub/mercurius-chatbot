import Foundation

extension APIClient {
    /// Upload a prepared image. The request body matches the backend's
    /// `ImageUploadRequest` (sessionId + contentType + base64 `data` + optional
    /// fileName). Returns the stable stored-image descriptor.
    ///
    /// Errors surface as `APIError` via the shared status-code mapping:
    /// `.invalidRequest` for a rejected payload (400), `.server` for a storage
    /// failure (500), `.offline`/`.timeout` for connectivity. The caller should
    /// validate type + size first (see `ImageUploadLimits`) so the common cases
    /// never need a round-trip.
    public func uploadImage(_ input: ImageUploadInput, sessionId: String) async throws -> ImageUploadResponse {
        struct Body: Encodable {
            let sessionId: String
            let contentType: String
            let data: String
            // Optional: synthesized `Encodable` omits it when nil (encodeIfPresent),
            // so the backend sees `undefined`, which its Zod schema allows.
            let fileName: String?
        }
        return try await send(
            method: "POST",
            path: "/api/images",
            body: Body(
                sessionId: sessionId,
                contentType: input.contentType,
                data: input.base64Data,
                fileName: input.fileName
            )
        )
    }

    /// Resolve an `ImageUploadResponse`'s server-relative `url` into an absolute
    /// URL against the configured environment base URL (e.g. for `AsyncImage`).
    public func imageURL(for response: ImageUploadResponse) -> URL? {
        URL(string: response.url, relativeTo: environmentBaseURL)?.absoluteURL
    }
}
