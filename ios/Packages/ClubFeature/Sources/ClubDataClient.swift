import Foundation
import NetworkingKit

/// The narrow protocol `ClubViewModel` depends on. Tests inject a stub.
public protocol ClubDataProviding: Sendable {
    func fetchEvents() async throws -> ClubEvents
    func fetchBlogPosts() async throws -> [BlogPost]
}

/// Fetches the club's public JSON documents directly from
/// `mayoailiteracy.com`. Intentionally bypasses the Mercurius server —
/// these are static assets the website already serves publicly, and
/// going through the server would add a useless hop.
///
/// Errors are mapped to `APIError` so the shared `userFacingMessage` and
/// `isRetryable` logic in NetworkingKit applies, just like chat and
/// tools errors.
public final class ClubDataClient: ClubDataProviding, Sendable {

    public static let defaultBaseURL = URL(string: "https://mayoailiteracy.com")!

    private let baseURL: URL
    private let session: URLSession

    public init(baseURL: URL = defaultBaseURL, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.session = session
    }

    public func fetchEvents() async throws -> ClubEvents {
        try await fetchJSON(path: "events-data.json")
    }

    public func fetchBlogPosts() async throws -> [BlogPost] {
        try await fetchJSON(path: "blog-content.json")
    }

    // MARK: - Private

    private func fetchJSON<T: Decodable>(path: String) async throws -> T {
        let url = baseURL.appendingPathComponent(path)
        var request = URLRequest(url: url)
        // The JSON files are cached CDN-side; let URLSession reuse its
        // own cache too so rapid tab switches don't refetch.
        request.cachePolicy = .useProtocolCachePolicy
        request.timeoutInterval = 15

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch let urlError as URLError {
            throw APIClient.mapURLError(urlError)
        } catch is CancellationError {
            throw APIError.cancelled
        } catch {
            throw APIError.unknown(underlying: String(describing: error))
        }

        guard let http = response as? HTTPURLResponse else {
            throw APIError.unknown(underlying: "Non-HTTP response")
        }
        try APIClient.validate(statusCode: http.statusCode, data: data)

        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw APIError.decoding(underlying: String(describing: error))
        }
    }
}
