public import CryptoKit
public import Foundation

/// This machine's own keys for sync: one to sign what it writes, one the
/// profile key is wrapped to.
///
/// In the Secure Enclave where there is one: the private halves never leave
/// it, and what is stored is an opaque blob only this Mac's enclave can use.
/// Without an enclave (old Intel Macs) the keys are ordinary software keys,
/// kept inside the encrypted profile and nowhere else.
public struct SyncIdentity: Codable, Sendable, Equatable {
    public enum Custody: String, Codable, Sendable {
        case secureEnclave, software
    }

    public var id: String
    public var name: String
    public var custody: Custody
    var signingKey: Data
    var agreementKey: Data

    /// Makes new keys for this machine.
    public static func create(
        name: String, useEnclave: Bool = SecureEnclave.isAvailable
    ) throws(SyncError)
        -> SyncIdentity
    {
        do {
            if useEnclave {
                return SyncIdentity(
                    id: UUID().uuidString, name: name, custody: .secureEnclave,
                    signingKey: try SecureEnclave.P256.Signing.PrivateKey().dataRepresentation,
                    agreementKey: try SecureEnclave.P256.KeyAgreement.PrivateKey().dataRepresentation)
            }
            return SyncIdentity(
                id: UUID().uuidString, name: name, custody: .software,
                signingKey: P256.Signing.PrivateKey().rawRepresentation,
                agreementKey: P256.KeyAgreement.PrivateKey().rawRepresentation)
        } catch {
            throw .keys
        }
    }

    /// What other machines need to know about this one: public keys only.
    public func machine() throws(SyncError) -> SyncMachine {
        do {
            switch custody {
            case .secureEnclave:
                return SyncMachine(
                    id: id, name: name,
                    signingKey: try SecureEnclave.P256.Signing.PrivateKey(dataRepresentation: signingKey)
                        .publicKey.x963Representation,
                    agreementKey: try SecureEnclave.P256.KeyAgreement.PrivateKey(
                        dataRepresentation: agreementKey
                    )
                    .publicKey.x963Representation)
            case .software:
                return SyncMachine(
                    id: id, name: name,
                    signingKey: try P256.Signing.PrivateKey(rawRepresentation: signingKey)
                        .publicKey.x963Representation,
                    agreementKey: try P256.KeyAgreement.PrivateKey(rawRepresentation: agreementKey)
                        .publicKey.x963Representation)
            }
        } catch {
            throw .keys
        }
    }

    func sign(_ snapshot: SyncSnapshot) throws(SyncError) -> SignedSnapshot {
        let custody = custody, key = signingKey
        return try SyncCrypto.sign(snapshot, signer: id) { body in
            switch custody {
            case .secureEnclave:
                try SecureEnclave.P256.Signing.PrivateKey(dataRepresentation: key).signature(for: body)
            case .software:
                try P256.Signing.PrivateKey(rawRepresentation: key).signature(for: body)
            }
        }
    }

    /// Ключ не открывается — значит, это не тот Мак, где он родился (профиль
    /// перенесли экспортом), или анклав сброшен.
    func unwrap(_ snapshot: SyncSnapshot) throws(SyncError) -> SymmetricKey {
        switch custody {
        case .secureEnclave:
            let key: SecureEnclave.P256.KeyAgreement.PrivateKey
            do { key = try .init(dataRepresentation: agreementKey) } catch { throw .keys }
            return try SyncCrypto.unwrap(snapshot, machine: id, with: key)
        case .software:
            let key: P256.KeyAgreement.PrivateKey
            do { key = try .init(rawRepresentation: agreementKey) } catch { throw .keys }
            return try SyncCrypto.unwrap(snapshot, machine: id, with: key)
        }
    }
}

extension SyncMachine {
    /// A short code to compare by eye when one machine lets another in:
    /// the same eight characters on both screens mean the request was not
    /// swapped on the way. 40 bits of the keys' hash, in Crockford base32 —
    /// no I, L, O or U to misread.
    public var code: String {
        let digest = Array(SHA256.hash(data: signingKey + agreementKey).prefix(5))
        let alphabet = Array("0123456789ABCDEFGHJKMNPQRSTVWXYZ")
        var bits = digest.reduce(UInt64(0)) { $0 << 8 | UInt64($1) }
        var characters: [Character] = []
        for _ in 0..<8 {
            characters.append(alphabet[Int(bits & 31)])
            bits >>= 5
        }
        let text = String(characters.reversed())
        return "\(text.prefix(4))-\(text.suffix(4))"
    }
}
