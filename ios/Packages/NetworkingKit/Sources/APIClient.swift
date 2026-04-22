import Foundation

/// The single entry point for every request to the Mercurius backend.
///
/// Responsibilities:
/// - Construct requests with correct headers (tracing, JSON, session).
/// - Enforce timeouts.
/// - Translate `URLSession`/HTTP responses into `APIError` cases.
/// - Decode and validate response bodies.
///
/// Features hold a single `APIClient` instance (typically injected at the
/// app root). The client is an `actor` so shared mutable state (e.g.
/// `URLSession`, trace IDs) is isolated correctly under Swift's strict
/// concurrency checking.
public actor APIClient {
    private let environment: APIEnvironment
    private let session: URLSession
    private let sessionIdentity: SessionIdentity
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder

    public init(
        environment: APIEnvironment = .production,
        sessionIdentity: SessionIdentity = SessionIdentity(),
        sessionConfiguration: URLSessionConfiguration = .default
    ) {
        self.environment = environment
        self.sessionIdentity = sessionIdentity

        let config = sessionConfiguration
        config.timeoutIntervalForRequest = environment.requestTimeout
        config.timeoutIntervalForResource = environment.requestTimeout * 2
        config.waitsForConnectivity = false  // fail fast on offline
        self.session = URLSession(configuration: config)

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        self.decoder = decoder

        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        self.encoder = encoder
    }

    // MARK: - Health

    /// Pings the backend's health endpoint. Returns `true` only if the
    /// backend reports `status: "ok"`.
    public func checkHealth() async -> Bool {
        do {
            let response: HealthResponse = try await send(
                method: "GET",
                path: "/api/health",
                body: Optional<Empty>.none
            )
            return response.status == "ok"
        } catch {
            return false
        }
    }

    // MARK: - Generic request

    /// Send a JSON request and decode the JSON response.
    ///
    /// `Body: Encodable` — pass `Optional<Empty>.none` for GET.
    /// `Response: Decodable` — the expected body shape.
    func send<Body: Encodable, Response: Decodable>(
        method: String,
        path: String,
        body: Body?
    ) async throws -> Response {
        var request = try buildRequest(method: method, path: path)

        if let body {
            do {
                request.httpBody = try encoder.encode(body)
            } catch {
                throw APIError.invalidRequest(reason: "Failed to encode body")
            }
        }

        return try await perform(request: request)
    }

    // MARK: - Request construction

    private func buildRequest(method: String, path: String) throws -> URLRequest {
        guard let url = URL(string: path, relativeTo: environment.baseURL)?.absoluteURL else {
            throw APIError.invalidRequest(reason: "Invalid URL: \(path)")
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = environment.requestTimeout
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        // Trace ID helps correlate iOS issues with server logs.
        request.setValue(UUID().uuidString, forHTTPHeaderField: "x-trace-id")

        return request
    }

    // MARK: - Perform

    private func perform<Response: Decodable>(request: URLRequest) async throws -> Response {
        let data: Data
        let response: URLResponse

        do {
            (data, response) = try await session.data(for: request)
        } catch let urlError as URLError {
            throw Self.mapURLError(urlError)
        } catch is CancellationError {
            throw APIError.cancelled
        } catch {
            throw APIError.unknown(underlying: String(describing: error))
        }

        guard let http = response as? HTTPURLResponse else {
            throw APIError.unknown(underlying: "Non-HTTP response")
        }

        try Self.validate(statusCode: http.statusCode, data: data)

        do {
            return try decoder.decode(Response.self, from: data)
        } catch {
            throw APIError.decoding(underlying: String(describing: error))
        }
    }

    // MARK: - Response validation

    static func validate(statusCode: Int, data: Data) throws {
        switch statusCode {
        case 200...299:
            return
        case 400:
            let reason = (try? JSONDecoder().decode(ErrorBody.self, from: data))?.message
            throw APIError.invalidRequest(reason: reason)
        case 401, 403:
            throw APIError.unauthorized
        case 429:
            throw APIError.rateLimited
        case 500...599:
            throw APIError.server(status: statusCode)
        default:
            throw APIError.unknown(underlying: "HTTP \(statusCode)")
        }
    }

    static func mapURLError(_ error: URLError) -> APIError {
        switch error.code {
        case .notConnectedToInternet, .dataNotAllowed:
            return .offline
        case .timedOut:
            return .timeout
        case .cancelled:
            return .cancelled
        default:
            return .unknown(underlying: error.localizedDescription)
        }
    }
}

// MARK: - Supporting types

struct Empty: Codable {}

struct ErrorBody: Decodable {
    let error: String?
    let message: String?
    let reply: String?
}

/// Shape of the /api/health response.
struct HealthResponse: Decodable {
    let status: String
    let timestamp: String?
}
