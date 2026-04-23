import Foundation
import Security

/// Narrow protocol so callers can substitute a fake at test time
/// without depending on the real iOS Keychain. Production code uses
/// the concrete `Keychain` via the default parameter; tests that
/// exercise keychain-dependent state machines (`SessionIdentityTests`)
/// pass an in-memory conforming type.
public protocol KeychainStore: Sendable {
    func set(_ value: String, for key: String) throws
    func get(_ key: String) throws -> String
    func delete(_ key: String) throws
}

/// A minimal, explicit wrapper around the iOS Keychain for storing short
/// string secrets (e.g. session identifiers).
///
/// Design notes:
/// - Returns typed errors rather than optional Bool — callers can decide
///   whether to fall through or surface.
/// - Scoped to the app via `kSecAttrService`; no cross-app sharing.
/// - Uses `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly` so secrets
///   survive restarts but do not sync to iCloud or leave the device.
public struct Keychain: Sendable, KeychainStore {
    public enum KeychainError: Error, Equatable {
        case itemNotFound
        case unexpectedData
        case unhandled(status: OSStatus)
    }

    private let service: String

    public init(service: String = "com.mayoailiteracy.mercurius") {
        self.service = service
    }

    public func set(_ value: String, for key: String) throws {
        guard let data = value.data(using: .utf8) else {
            throw KeychainError.unexpectedData
        }

        // Try update first (atomic); fall back to add if not present.
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]

        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]

        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)

        switch updateStatus {
        case errSecSuccess:
            return
        case errSecItemNotFound:
            var addQuery = query
            addQuery.merge(attributes) { _, new in new }
            let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
            guard addStatus == errSecSuccess else {
                throw KeychainError.unhandled(status: addStatus)
            }
        default:
            throw KeychainError.unhandled(status: updateStatus)
        }
    }

    public func get(_ key: String) throws -> String {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecReturnData as String: true,
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)

        switch status {
        case errSecSuccess:
            guard let data = item as? Data, let string = String(data: data, encoding: .utf8) else {
                throw KeychainError.unexpectedData
            }
            return string
        case errSecItemNotFound:
            throw KeychainError.itemNotFound
        default:
            throw KeychainError.unhandled(status: status)
        }
    }

    public func delete(_ key: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.unhandled(status: status)
        }
    }
}
