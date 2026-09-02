import CryptoKit
public import Foundation
public import VaultKit

/// Everything the app remembers between launches.
///
/// One `Codable` blob so the encrypted container has exactly one shape and a
/// migration touches one place.
public struct Profile: Codable, Sendable {
    /// Schema this profile was written with. Read from the clear header, not
    /// from here — this copy exists so a migration can tell what it is holding
    /// after decryption.
    public var version: UInt16
    public var payload: Data

    public init(version: UInt16 = Vault.currentVersion, payload: Data) {
        self.version = version
        self.payload = payload
    }
}

public enum ProfileStoreError: Error, Equatable {
    /// No profile has been written yet: a first run, not a failure.
    case empty
    /// The master key is gone, so the profile can never be read again.
    ///
    /// This is the price of `ThisDeviceOnly`, and it is also a feature: deleting
    /// the key destroys the profile in a second, with no disk wiping.
    case keyLost
}

/// Reads and writes the encrypted profile.
///
/// The master key lives in the Keychain behind biometry and never touches disk;
/// this type only turns bytes into a document and back.
public actor ProfileStore {
    public static let masterKeyAccount = "phosphor.master-key"

    private let store: any SecretStore
    private let url: URL
    private var cachedKey: SymmetricKey?

    public init(store: any SecretStore, url: URL? = nil) {
        self.store = store
        self.url = url ?? Self.defaultURL()
    }

    public static func defaultURL() -> URL {
        let base =
            FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first ?? URL(fileURLWithPath: NSHomeDirectory())
        return base.appendingPathComponent("Phosphor/profile.phosphor")
    }

    /// Whether a profile exists on disk. Cheap, and asks for nothing.
    public func hasProfile() -> Bool {
        FileManager.default.fileExists(atPath: url.path)
    }

    /// Fetches the master key, creating one on first run.
    private func masterKey(reason: String) async throws -> SymmetricKey {
        if let cachedKey { return cachedKey }
        if await store.exists(Self.masterKeyAccount) {
            let raw = try await store.read(Self.masterKeyAccount, reason: reason)
            let key = SymmetricKey(data: raw)
            cachedKey = key
            return key
        }
        // Refuse to silently mint a second key over an existing profile: that
        // would make the old one permanently unreadable without saying so.
        guard !hasProfile() else { throw ProfileStoreError.keyLost }
        let key = Vault.generateKey()
        try await store.write(key.withUnsafeBytes { Data($0) }, account: Self.masterKeyAccount)
        cachedKey = key
        return key
    }

    /// Decrypts and decodes the profile.
    public func load<T: Decodable>(_ type: T.Type, reason: String) async throws -> T {
        guard hasProfile() else { throw ProfileStoreError.empty }
        let key = try await masterKey(reason: reason)
        let sealed = try Data(contentsOf: url)
        let plain = try Vault(key: key).open(sealed)
        return try JSONDecoder().decode(T.self, from: plain)
    }

    /// Encodes, encrypts and writes atomically.
    public func save(_ value: some Encodable, reason: String) async throws {
        let key = try await masterKey(reason: reason)
        let plain = try JSONEncoder().encode(value)
        let sealed = try Vault(key: key).seal(plain)
        try AtomicFile.write(sealed, to: url)
    }

    /// Re-encrypts the profile under a passphrase, for moving to another Mac.
    ///
    /// The only way out of `ThisDeviceOnly`, and the only insurance against
    /// losing the key — which is why it is a normal feature rather than a
    /// recovery tool nobody finds in time.
    public func export(passphrase: String, reason: String) async throws -> Data {
        let key = try await masterKey(reason: reason)
        let plain = try Vault(key: key).open(Data(contentsOf: url))
        // PBKDF2 со случайной солью, а не быстрый HKDF: файл экспорта — это то,
        // что можно потерять или переслать, и его нельзя перебирать офлайн.
        return try PassphraseBox.seal(plain, passphrase: passphrase)
    }

    /// Installs an exported profile, replacing whatever is here.
    public func importProfile(_ data: Data, passphrase: String, reason: String) async throws {
        let plain = try PassphraseBox.open(data, passphrase: passphrase)
        let key = try await masterKey(reason: reason)
        try AtomicFile.write(try Vault(key: key).seal(plain), to: url)
    }

    /// Destroys the profile by forgetting how to read it.
    public func destroy() async throws {
        try? FileManager.default.removeItem(at: url)
        try await store.delete(Self.masterKeyAccount)
        cachedKey = nil
    }

}
