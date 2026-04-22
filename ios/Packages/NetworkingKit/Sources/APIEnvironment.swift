import Foundation

/// Identifies which Mercurius backend the client talks to.
///
/// Keeps staging and production cleanly separable. The production URL is
/// hard-coded because it is a public, non-secret value. Staging is
/// configurable so contributors can run against a local server.
public struct APIEnvironment: Sendable {
    public let baseURL: URL
    public let requestTimeout: TimeInterval
    public let streamingTimeout: TimeInterval

    public init(baseURL: URL, requestTimeout: TimeInterval = 30, streamingTimeout: TimeInterval = 60) {
        self.baseURL = baseURL
        self.requestTimeout = requestTimeout
        self.streamingTimeout = streamingTimeout
    }

    /// Production deployment on Railway.
    public static let production = APIEnvironment(
        baseURL: URL(string: "https://mercurius-chatbot-production.up.railway.app")!
    )

    /// Local dev server.
    public static let local = APIEnvironment(
        baseURL: URL(string: "http://localhost:3000")!
    )
}
