public import Foundation
import LocalAuthentication
import Security

public enum SecretError: Error, Equatable {
    case notFound
    case denied
    case keychain(OSStatus)
}

/// Somewhere small secrets live.
///
/// Deliberately narrow: passwords, passphrases, TOTP seeds and the profile's
/// master key. Anything larger belongs in the encrypted profile — the Keychain
/// is a key store, not a database.
public protocol SecretStore: Sendable {
    func read(_ account: String, reason: String) async throws -> Data
    func write(_ data: Data, account: String) async throws
    func delete(_ account: String) async throws
    func exists(_ account: String) async -> Bool
}

/// Keychain-backed store where every item is gated by the system.
///
/// The important part is not the dialog but the access control: the item is
/// created so that macOS itself refuses to hand the bytes over without a fresh
/// check. Showing a prompt and then reading a plaintext file would be theatre.
public struct KeychainSecretStore: SecretStore {
    private let service: String

    public init(service: String = "dev.phosphor.terminal") {
        self.service = service
    }

    /// `biometryCurrentSet` invalidates the item when the enrolled fingerprints
    /// change — which is the point, and also why re-enrolment has to be handled
    /// gracefully rather than surfacing as `errSecAuthFailed`.
    private func accessControl() throws -> SecAccessControl {
        var error: Unmanaged<CFError>?
        guard
            let control = SecAccessControlCreateWithFlags(
                nil,
                kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
                .biometryCurrentSet,
                &error
            )
        else {
            throw SecretError.keychain(errSecParam)
        }
        return control
    }

    public func read(_ account: String, reason: String) async throws -> Data {
        let context = LAContext()
        context.localizedReason = reason
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecUseAuthenticationContext as String: context,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        switch status {
        case errSecSuccess:
            guard let data = item as? Data else { throw SecretError.notFound }
            return data
        case errSecItemNotFound:
            throw SecretError.notFound
        case errSecUserCanceled, errSecAuthFailed:
            throw SecretError.denied
        default:
            throw SecretError.keychain(status)
        }
    }

    public func write(_ data: Data, account: String) throws {
        try? delete(account)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrAccessControl as String: try accessControl(),
        ]
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else { throw SecretError.keychain(status) }
    }

    public func delete(_ account: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw SecretError.keychain(status)
        }
    }

    public func exists(_ account: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            // Ask only whether the item is there: no data, so no prompt.
            kSecUseAuthenticationUI as String: kSecUseAuthenticationUIFail,
        ]
        let status = SecItemCopyMatching(query as CFDictionary, nil)
        return status == errSecSuccess || status == errSecInteractionNotAllowed
    }
}

/// In-memory store for tests: same contract, no Keychain, no prompts.
public actor MemorySecretStore: SecretStore {
    private var items: [String: Data] = [:]

    public init() {}

    public func read(_ account: String, reason: String) async throws -> Data {
        guard let data = items[account] else { throw SecretError.notFound }
        return data
    }

    public func write(_ data: Data, account: String) throws {
        items[account] = data
    }

    public func delete(_ account: String) throws {
        items[account] = nil
    }

    public func exists(_ account: String) -> Bool {
        items[account] != nil
    }
}
