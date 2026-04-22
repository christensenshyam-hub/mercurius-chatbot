import Testing
@testable import NetworkingKit

@Suite("SessionIdentity")
struct SessionIdentityTests {

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
