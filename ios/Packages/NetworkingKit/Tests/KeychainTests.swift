import Testing
import Foundation
@testable import NetworkingKit

/// Tests against the real macOS/iOS Keychain. Each test uses a unique
/// `service` string so parallel runs (swift test --parallel) don't
/// stomp on each other's state — the Keychain is a process-wide
/// resource with no sandbox between unit tests.
///
/// Skipped when `CI=true`. GitHub-hosted macOS runners ship without a
/// writable keychain for the agent user — `SecItemAdd` returns
/// `errSecMissingEntitlement` or `errSecNotAvailable` depending on the
/// image. The same code path is exercised on a real device + the iOS
/// simulator test host via `xcodebuild test`, which provides an app
/// with the default-keychain entitlement.
private let isRunningUnderCI: Bool = ProcessInfo.processInfo.environment["CI"] == "true"

@Suite(
    "Keychain",
    .disabled(if: isRunningUnderCI, "macOS runner keychain is not writable under `swift test`; covered by the simulator test host instead.")
)
struct KeychainTests {

    /// Returns a Keychain instance bound to a service scoped by the
    /// test name, and registers a teardown that deletes anything we
    /// wrote — keeps the macOS Keychain clean between runs.
    private func isolatedKeychain(_ label: String = #function) -> Keychain {
        let service = "com.mayoailiteracy.mercurius.tests.\(label)"
        let kc = Keychain(service: service)
        // Best-effort pre-cleanup in case a prior run died mid-test.
        try? kc.delete("k")
        try? kc.delete("k2")
        return kc
    }

    @Test("set then get returns the same string")
    func roundTrip() throws {
        let kc = isolatedKeychain()
        try kc.set("hello", for: "k")
        #expect(try kc.get("k") == "hello")
        try kc.delete("k")
    }

    @Test("set overwrites a previous value (SecItemUpdate path)")
    func overwrite() throws {
        let kc = isolatedKeychain()
        try kc.set("one", for: "k")
        try kc.set("two", for: "k")
        #expect(try kc.get("k") == "two")
        try kc.delete("k")
    }

    @Test("get on a missing key throws .itemNotFound")
    func missingKeyThrows() throws {
        let kc = isolatedKeychain()
        try kc.delete("k")  // ensure empty
        do {
            _ = try kc.get("k")
            Issue.record("Expected itemNotFound")
        } catch Keychain.KeychainError.itemNotFound {
            // expected
        } catch {
            Issue.record("Expected .itemNotFound, got \(error)")
        }
    }

    @Test("delete on a missing key is a no-op, not an error")
    func deleteMissingIsIdempotent() throws {
        let kc = isolatedKeychain()
        // Ensure empty, then delete again — should not throw.
        try kc.delete("k")
        try kc.delete("k")
    }

    @Test("Two different services are independent — no cross-bleed")
    func serviceScoping() throws {
        let a = Keychain(service: "com.mayoailiteracy.mercurius.tests.scopeA")
        let b = Keychain(service: "com.mayoailiteracy.mercurius.tests.scopeB")
        try? a.delete("k"); try? b.delete("k")

        try a.set("alpha", for: "k")
        try b.set("beta", for: "k")

        #expect(try a.get("k") == "alpha")
        #expect(try b.get("k") == "beta")

        try a.delete("k")
        try b.delete("k")
    }

    @Test("Multiple keys within one service don't interfere")
    func multipleKeys() throws {
        let kc = isolatedKeychain()
        try kc.set("v1", for: "k")
        try kc.set("v2", for: "k2")
        #expect(try kc.get("k") == "v1")
        #expect(try kc.get("k2") == "v2")
        try kc.delete("k")
        try kc.delete("k2")
    }
}
