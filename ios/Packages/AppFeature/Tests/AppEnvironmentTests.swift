import Testing
@testable import AppFeature

@Suite("AppEnvironment")
@MainActor
struct AppEnvironmentTests {

    @Test("Creates without throwing and exposes required collaborators")
    func construction() {
        let env = AppEnvironment(environment: .local)
        _ = env.apiClient
        _ = env.sessionIdentity
    }
}
