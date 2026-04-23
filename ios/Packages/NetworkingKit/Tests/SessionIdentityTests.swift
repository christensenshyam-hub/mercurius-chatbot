import Testing
import Foundation
@testable import NetworkingKit

// MARK: - In-memory KeychainStore fake

/// Hermetic `KeychainStore` for tests — no Security framework calls,
/// runs identically on local dev, `swift test`, and CI.
/// Can also be primed with an error to drive the unhappy paths.
final class InMemoryKeychain: KeychainStore, @unchecked Sendable {
    private let lock = NSLock()
    private var store: [String: String] = [:]

    /// If non-nil, the next call to any method throws this and clears
    /// the slot. Lets a single test drive one specific failure mode.
    var nextError: Error?
    var recordedSets: [(value: String, key: String)] = []
    var recordedDeletes: [String] = []

    func set(_ value: String, for key: String) throws {
        lock.lock(); defer { lock.unlock() }
        if let err = consumeError() { throw err }
        recordedSets.append((value, key))
        store[key] = value
    }

    func get(_ key: String) throws -> String {
        lock.lock(); defer { lock.unlock() }
        if let err = consumeError() { throw err }
        guard let v = store[key] else {
            throw Keychain.KeychainError.itemNotFound
        }
        return v
    }

    func delete(_ key: String) throws {
        lock.lock(); defer { lock.unlock() }
        if let err = consumeError() { throw err }
        recordedDeletes.append(key)
        store.removeValue(forKey: key)
    }

    /// Non-throwing primer — used by tests to prepopulate.
    func seed(_ value: String, for key: String) {
        lock.lock(); defer { lock.unlock() }
        store[key] = value
    }

    private func consumeError() -> Error? {
        defer { nextError = nil }
        return nextError
    }
}

// MARK: - Static generation / validation

@Suite("SessionIdentity static helpers")
struct SessionIdentityStaticTests {

    @Test("Generates an ID that satisfies server validation rules")
    func generatesValidId() {
        let id = SessionIdentity.generate()
        #expect(id.count <= 64)
        #expect(!id.isEmpty)
        #expect(SessionIdentity.isValid(id))
    }

    @Test("Generated IDs are not identical across calls")
    func generatedIdsAreUnique() {
        let a = SessionIdentity.generate()
        let b = SessionIdentity.generate()
        #expect(a != b)
    }

    @Test("Rejects SQL injection and special characters")
    func rejectsInvalidIds() {
        #expect(!SessionIdentity.isValid(""))
        #expect(!SessionIdentity.isValid("'; DROP TABLE sessions;--"))
        #expect(!SessionIdentity.isValid("has spaces"))
        #expect(!SessionIdentity.isValid("has/slash"))
        #expect(!SessionIdentity.isValid("has+plus"))
        #expect(!SessionIdentity.isValid(String(repeating: "a", count: 65)))
    }

    @Test("Accepts alphanumerics, underscores, and hyphens up to 64 chars")
    func acceptsValidIds() {
        #expect(SessionIdentity.isValid("abc123"))
        #expect(SessionIdentity.isValid("ABC_DEF"))
        #expect(SessionIdentity.isValid("a-b-c"))
        #expect(SessionIdentity.isValid(String(repeating: "a", count: 64)))
    }
}

// MARK: - current() + reset() state machine

@Suite("SessionIdentity.current() + reset()")
struct SessionIdentityInstanceTests {

    @Test("current() on empty keychain generates a valid id and persists it")
    func firstLaunchGenerates() throws {
        let kc = InMemoryKeychain()
        let identity = SessionIdentity(keychain: kc)

        let id = try identity.current()

        #expect(SessionIdentity.isValid(id))
        #expect(kc.recordedSets.count == 1, "New id should be written exactly once")
        #expect(kc.recordedSets.first?.key == "session_id")
        #expect(kc.recordedSets.first?.value == id)
    }

    @Test("current() returns the same id on repeated calls (cached in memory)")
    func repeatedCallsAreCached() throws {
        let kc = InMemoryKeychain()
        let identity = SessionIdentity(keychain: kc)

        let a = try identity.current()
        let b = try identity.current()
        let c = try identity.current()

        #expect(a == b && b == c)
        #expect(kc.recordedSets.count == 1, "Should not re-write on every call — in-memory cache holds the id")
    }

    @Test("current() reads a pre-existing valid id from the keychain and does not regenerate")
    func rereadsExistingId() throws {
        let kc = InMemoryKeychain()
        kc.seed("abc_1234_DEF-5678", for: "session_id")
        let identity = SessionIdentity(keychain: kc)

        let id = try identity.current()

        #expect(id == "abc_1234_DEF-5678")
        #expect(kc.recordedSets.isEmpty, "Pre-existing valid id must not be overwritten")
    }

    @Test("current() regenerates when the stored id is invalid (corrupted keychain)")
    func invalidStoredIdRegenerates() throws {
        let kc = InMemoryKeychain()
        kc.seed("has spaces — not valid", for: "session_id")
        let identity = SessionIdentity(keychain: kc)

        let id = try identity.current()

        #expect(id != "has spaces — not valid")
        #expect(SessionIdentity.isValid(id))
        #expect(kc.recordedSets.count == 1, "Regenerated id should be persisted")
    }

    @Test("current() propagates non-itemNotFound keychain errors")
    func propagatesKeychainErrors() {
        let kc = InMemoryKeychain()
        kc.nextError = Keychain.KeychainError.unhandled(status: -50)
        let identity = SessionIdentity(keychain: kc)

        do {
            _ = try identity.current()
            Issue.record("Expected the unhandled keychain error to propagate")
        } catch Keychain.KeychainError.unhandled(let status) {
            #expect(status == -50)
        } catch {
            Issue.record("Expected .unhandled, got \(error)")
        }
    }

    @Test("reset() clears the keychain entry and the in-memory cache")
    func resetClearsEverything() throws {
        let kc = InMemoryKeychain()
        let identity = SessionIdentity(keychain: kc)

        let first = try identity.current()
        try identity.reset()
        #expect(kc.recordedDeletes.contains("session_id"))

        // After reset the next current() should generate a fresh id.
        let second = try identity.current()
        #expect(second != first, "Reset should force a regenerate on the next current()")
        #expect(kc.recordedSets.count == 2, "One write before reset, one after")
    }

    @Test("reset() propagates keychain delete errors")
    func resetPropagates() {
        let kc = InMemoryKeychain()
        kc.nextError = Keychain.KeychainError.unhandled(status: -26)
        let identity = SessionIdentity(keychain: kc)

        do {
            try identity.reset()
            Issue.record("Expected reset to propagate")
        } catch Keychain.KeychainError.unhandled(let status) {
            #expect(status == -26)
        } catch {
            Issue.record("Expected .unhandled, got \(error)")
        }
    }

    @Test("Concurrent current() calls all return the same id (thread-safe)")
    func concurrentAccess() async throws {
        let kc = InMemoryKeychain()
        let identity = SessionIdentity(keychain: kc)

        // Fan out 32 concurrent current() calls. The internal lock
        // serializes them; they should all observe the same id and
        // generate-and-persist should happen exactly once.
        let ids = await withTaskGroup(of: String?.self, returning: Set<String>.self) { group in
            for _ in 0..<32 {
                group.addTask {
                    try? identity.current()
                }
            }
            var set = Set<String>()
            for await id in group {
                if let id { set.insert(id) }
            }
            return set
        }

        #expect(ids.count == 1, "All 32 concurrent callers must agree on one id")
        #expect(kc.recordedSets.count == 1, "Generation must happen exactly once under concurrency")
    }
}
