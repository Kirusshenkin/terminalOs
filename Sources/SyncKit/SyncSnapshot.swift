public import CryptoKit
public import Foundation

/// A machine allowed to read and write the synced profile.
public struct SyncMachine: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var name: String
    /// P-256 signing key, x9.63: checks that a snapshot came from this machine.
    public var signingKey: Data
    /// P-256 key-agreement key, x9.63: the profile key is wrapped to it.
    public var agreementKey: Data

    public init(id: String, name: String, signingKey: Data, agreementKey: Data) {
        self.id = id
        self.name = name
        self.signingKey = signingKey
        self.agreementKey = agreementKey
    }
}

/// The profile key, wrapped for one machine with HPKE.
public struct WrappedKey: Codable, Sendable, Equatable {
    public var machine: String
    public var encapsulated: Data
    public var sealed: Data
}

/// A record as the storage sees it: which item and when, but not what.
public struct SealedRecord: Codable, Sendable, Equatable {
    public var kind: SyncRecord.Kind
    public var id: String
    public var stamp: Stamp
    /// AES-GCM box of the payload; nil for a deletion mark.
    public var box: Data?
}

/// Everything one storage holds: who may read, the wrapped key, the records.
public struct SyncSnapshot: Codable, Sendable, Equatable {
    /// Grows with every write. A machine refuses anything lower than what it
    /// has already seen, so storage cannot hand back an old version.
    public var revision: UInt64
    /// Grows when the profile key is replaced, e.g. after a machine is removed.
    public var keyGeneration: UInt32
    public var machines: [SyncMachine]
    public var keys: [WrappedKey]
    public var records: [SealedRecord]

    public init(
        revision: UInt64 = 0, keyGeneration: UInt32 = 0, machines: [SyncMachine] = [],
        keys: [WrappedKey] = [], records: [SealedRecord] = []
    ) {
        self.revision = revision
        self.keyGeneration = keyGeneration
        self.machines = machines
        self.keys = keys
        self.records = records
    }
}

/// A snapshot with the signature of the machine that wrote it.
public struct SignedSnapshot: Codable, Sendable, Equatable {
    /// The snapshot's JSON exactly as signed: it is decoded from these bytes,
    /// so what is checked is what is used.
    public var body: Data
    public var signer: String
    public var signature: Data
}

/// Why a snapshot or record was refused. Every case is something the storage
/// or a network could do to us, not a bug: they are reported, never trapped.
public enum SyncError: Error, Sendable, Equatable {
    /// Signed by a machine that is not on the list this machine trusts.
    case unknownSigner(String)
    case badSignature
    /// Storage returned a revision older than one already seen here.
    case rollback(seen: UInt64, got: UInt64)
    /// This machine is not among the readers: it was removed, or not added yet.
    case notForThisMachine
    /// A record or wrapped key does not open: damaged or tampered with.
    case unreadable(String)
    case malformed(String)
    /// This machine's own keys do not work: the profile was moved here from
    /// another Mac, or the Secure Enclave was reset.
    case keys
    /// Another machine kept writing at the same moment, three times running.
    case busy
    /// The folder on the server could not be read or written; the text is
    /// what the server said.
    case storage(String)
}

/// The cryptography of sync, with no storage and no network.
///
/// - Records are sealed one by one with AES-GCM under the profile key; the
///   item's kind, id, stamp and key generation are bound in as associated
///   data, so storage cannot move a payload to another item or time.
/// - The profile key is wrapped for each machine with HPKE (P-256), whose
///   private half can live in the Secure Enclave.
/// - The whole snapshot is signed by the machine that wrote it.
public enum SyncCrypto {
    static let suite = HPKE.Ciphersuite.P256_SHA256_AES_GCM_256
    static let info = Data("phosphor.sync.profile-key.v1".utf8)

    // MARK: Ключ профиля для каждой машины

    public static func wrap(_ key: SymmetricKey, for machine: SyncMachine) throws(SyncError) -> WrappedKey {
        do {
            let recipient = try P256.KeyAgreement.PublicKey(x963Representation: machine.agreementKey)
            var sender = try HPKE.Sender(recipientKey: recipient, ciphersuite: suite, info: info)
            let sealed = try key.withUnsafeBytes { try sender.seal(Data($0)) }
            return WrappedKey(machine: machine.id, encapsulated: sender.encapsulatedKey, sealed: sealed)
        } catch {
            throw .malformed("agreement key of \(machine.id)")
        }
    }

    /// Opens this machine's wrapped key. Generic over the private key so the
    /// same code takes a Secure Enclave key in the app and a software key in
    /// tests.
    public static func unwrap<PrivateKey: HPKEDiffieHellmanPrivateKey>(
        _ snapshot: SyncSnapshot, machine: String, with privateKey: PrivateKey
    ) throws(SyncError) -> SymmetricKey {
        guard let wrapped = snapshot.keys.first(where: { $0.machine == machine }) else {
            throw .notForThisMachine
        }
        do {
            var recipient = try HPKE.Recipient(
                privateKey: privateKey, ciphersuite: suite, info: info, encapsulatedKey: wrapped.encapsulated)
            return SymmetricKey(data: try recipient.open(wrapped.sealed))
        } catch {
            throw .unreadable("profile key")
        }
    }

    // MARK: Записи

    public static func seal(
        _ records: [SyncRecord], key: SymmetricKey, generation: UInt32
    ) throws(SyncError) -> [SealedRecord] {
        var sealed: [SealedRecord] = []
        for record in records {
            var box: Data?
            if let payload = record.payload {
                do {
                    box = try AES.GCM.seal(
                        payload, using: key,
                        authenticating: binding(record.kind, record.id, record.stamp, generation)
                    ).combined
                } catch {
                    throw .malformed("record \(record.key)")
                }
            }
            sealed.append(SealedRecord(kind: record.kind, id: record.id, stamp: record.stamp, box: box))
        }
        return sealed
    }

    public static func open(
        _ sealed: [SealedRecord], key: SymmetricKey, generation: UInt32
    ) throws(SyncError) -> [SyncRecord] {
        var records: [SyncRecord] = []
        for item in sealed {
            var payload: Data?
            if let box = item.box {
                do {
                    payload = try AES.GCM.open(
                        AES.GCM.SealedBox(combined: box), using: key,
                        authenticating: binding(item.kind, item.id, item.stamp, generation))
                } catch {
                    throw .unreadable("\(item.kind.rawValue)/\(item.id)")
                }
            }
            records.append(SyncRecord(kind: item.kind, id: item.id, stamp: item.stamp, payload: payload))
        }
        return records
    }

    /// Что привязано к шифртексту: перенести полезную нагрузку на другую
    /// запись, время или поколение ключа нельзя — она перестанет открываться.
    static func binding(_ kind: SyncRecord.Kind, _ id: String, _ stamp: Stamp, _ generation: UInt32) -> Data {
        Data(
            "\(kind.rawValue)\u{0}\(id)\u{0}\(stamp.millis)\u{0}\(stamp.counter)\u{0}\(stamp.machine)\u{0}\(generation)"
                .utf8)
    }

    // MARK: Подпись снимка

    /// Signs a snapshot. `sign` is the machine's signing key — a Secure
    /// Enclave key in the app, which CryptoKit gives no common type with a
    /// software key, hence a function.
    public static func sign(
        _ snapshot: SyncSnapshot, signer: String,
        sign: (Data) throws -> P256.Signing.ECDSASignature
    ) throws(SyncError) -> SignedSnapshot {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        do {
            let body = try encoder.encode(snapshot)
            return SignedSnapshot(body: body, signer: signer, signature: try sign(body).derRepresentation)
        } catch {
            throw .malformed("snapshot")
        }
    }

    /// Checks a snapshot from storage before anything in it is believed: a
    /// machine this one trusts signed it, and it is not older than what was
    /// already seen. The machine list inside becomes the next trusted list.
    public static func accept(
        _ signed: SignedSnapshot, trusted: [SyncMachine], lastRevision: UInt64
    ) throws(SyncError) -> SyncSnapshot {
        guard let machine = trusted.first(where: { $0.id == signed.signer }) else {
            throw .unknownSigner(signed.signer)
        }
        do {
            let key = try P256.Signing.PublicKey(x963Representation: machine.signingKey)
            let signature = try P256.Signing.ECDSASignature(derRepresentation: signed.signature)
            guard key.isValidSignature(signature, for: signed.body) else { throw SyncError.badSignature }
        } catch {
            throw .badSignature
        }
        let snapshot: SyncSnapshot
        do {
            snapshot = try JSONDecoder().decode(SyncSnapshot.self, from: signed.body)
        } catch {
            throw .malformed("snapshot")
        }
        guard snapshot.revision >= lastRevision else {
            throw .rollback(seen: lastRevision, got: snapshot.revision)
        }
        return snapshot
    }

    // MARK: Отзыв машины

    /// Removes a machine and replaces the profile key, so it cannot read
    /// anything written from now on. What it already downloaded stays with it
    /// — no system can take that back.
    public static func revoke(
        _ machineID: String, from snapshot: SyncSnapshot, key: SymmetricKey
    ) throws(SyncError) -> (snapshot: SyncSnapshot, key: SymmetricKey) {
        let records = try open(snapshot.records, key: key, generation: snapshot.keyGeneration)
        let fresh = SymmetricKey(size: .bits256)
        var next = snapshot
        next.keyGeneration += 1
        next.machines.removeAll { $0.id == machineID }
        next.keys = []
        for machine in next.machines {
            next.keys.append(try wrap(fresh, for: machine))
        }
        next.records = try seal(records, key: fresh, generation: next.keyGeneration)
        return (next, fresh)
    }
}
