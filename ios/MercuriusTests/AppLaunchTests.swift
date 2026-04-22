import Testing

/// Smoke test — ensures the test target is wired up. Feature-specific
/// tests live in the package test targets (DesignSystem / NetworkingKit /
/// AppFeature).
@Suite("App launch smoke test")
struct AppLaunchTests {
    @Test("Test target builds and executes")
    func smokeTest() {
        #expect(1 + 1 == 2)
    }
}
