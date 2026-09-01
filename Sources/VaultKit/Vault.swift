public import CryptoKit
public import Foundation
public import PhosphorCore

/// Errors the encrypted profile can raise.
public enum VaultError: Error, Equatable {
    /// The file is shorter than its own header claims.
    case truncated
    /// The header magic does not match; this is not a profile.
    case notAProfile
    /// The schema version is newer than this build understands.
    case unsupportedVersion(UInt16)
    /// Decryption or authentication failed: wrong key, or the file was altered.
    case cannotDecrypt
}

/// An encrypted, authenticated, versioned container for the profile.
///
/// FileVault protects a Mac that is switched off. While you are logged in every
/// process running as you can read `~/Library`, so the profile carries its own
/// encryption. The key lives in the Keychain behind biometry and never touches
/// disk; this type only knows how to turn a key plus bytes into a document.
///
/// Layout: `PHOS` magic, big-endian `UInt16` schema version, then the sealed
/// box. The header stays in the clear so a future migration can read the
/// version instead of failing with "cannot decrypt".
public struct Vault: Sendable {
    public static let magic: [UInt8] = Array("PHOS".utf8)
    public static let currentVersion: UInt16 = 1
    private static let headerSize = 6

    private let key: SymmetricKey

    public init(key: SymmetricKey) {
        self.key = key
    }

    /// Generates a fresh 256-bit master key.
    public static func generateKey() -> SymmetricKey {
        SymmetricKey(size: .bits256)
    }

    /// Encrypts `plaintext` into a versioned container.
    public func seal(_ plaintext: Data, version: UInt16 = Vault.currentVersion) throws -> Data {
        let box = try ChaChaPoly.seal(plaintext, using: key)
        var out = Data(Self.magic)
        out.append(UInt8(truncatingIfNeeded: version >> 8))
        out.append(UInt8(truncatingIfNeeded: version))
        out.append(box.combined)
        return out
    }

    /// Reads the schema version without needing the key.
    public static func version(of data: Data) throws -> UInt16 {
        guard data.count >= headerSize else { throw VaultError.truncated }
        guard Array(data.prefix(4)) == magic else { throw VaultError.notAProfile }
        let bytes = [UInt8](data)
        return UInt16(bytes[4]) << 8 | UInt16(bytes[5])
    }

    /// Decrypts a container, verifying its authentication tag.
    public func open(_ data: Data) throws -> Data {
        let version = try Self.version(of: data)
        guard version <= Self.currentVersion else { throw VaultError.unsupportedVersion(version) }
        let body = data.dropFirst(Self.headerSize)
        guard !body.isEmpty else { throw VaultError.truncated }
        do {
            let box = try ChaChaPoly.SealedBox(combined: body)
            return try ChaChaPoly.open(box, using: key)
        } catch {
            throw VaultError.cannotDecrypt
        }
    }
}

/// Writes files so that a crash mid-write cannot destroy the previous version.
///
/// A truncated ciphertext is not a damaged record, it is a lost profile — so
/// the new content lands in a temporary file, is flushed to disk, and only then
/// replaces the original.
public enum AtomicFile {
    public static func write(_ data: Data, to url: URL, permissions: Int16 = 0o600) throws {
        let directory = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let temporary = directory.appendingPathComponent(".\(url.lastPathComponent).tmp-\(UUID().uuidString)")

        FileManager.default.createFile(
            atPath: temporary.path,
            contents: nil,
            attributes: [.posixPermissions: NSNumber(value: permissions)]
        )
        let handle = try FileHandle(forWritingTo: temporary)
        do {
            try handle.write(contentsOf: data)
            try handle.synchronize()
            try handle.close()
        } catch {
            try? handle.close()
            try? FileManager.default.removeItem(at: temporary)
            throw error
        }
        _ = try FileManager.default.replaceItemAt(url, withItemAt: temporary)
    }
}
