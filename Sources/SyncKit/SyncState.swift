import CryptoKit
public import Foundation

/// One item of the profile as sync sees it, before it gets a stamp.
public struct SyncItem: Sendable, Equatable {
    public var kind: SyncRecord.Kind
    public var id: String
    public var payload: Data

    public init(kind: SyncRecord.Kind, id: String, payload: Data) {
        self.kind = kind
        self.id = id
        self.payload = payload
    }

    var key: String { "\(kind.rawValue)/\(id)" }
}

/// What this machine last agreed on with storage, for one item.
public struct SyncBaseline: Codable, Sendable, Equatable {
    public var stamp: Stamp
    /// SHA-256 of the item as this machine encodes it; empty for a deletion mark.
    public var digest: Data
    /// False when a record came in that this version of the app could not
    /// read (a newer format): its absence here is not a deletion.
    public var applied: Bool
}

/// What one storage last showed this machine.
public struct StorageMark: Codable, Sendable, Equatable {
    public var revision: UInt64 = 0
    /// See `SyncSnapshot.epoch`.
    public var epoch: UInt32 = 0
}

/// Everything this machine keeps about sync, inside its encrypted profile.
public struct SyncState: Codable, Sendable, Equatable {
    public var identity: SyncIdentity
    /// Hosts whose folders hold the shared snapshot, each a full copy: one
    /// down does not stop sync, it catches up when it is back.
    public var storages: [UUID]
    /// Per storage: the highest revision and epoch seen there. Storage
    /// handing back anything older is refused.
    public var marks: [UUID: StorageMark] = [:]
    /// Machines this one trusts to sign snapshots. Empty until it is let in.
    public var machines: [SyncMachine] = []
    /// The profile key, unwrapped. A secret, but it sits next to the hosts it
    /// protects: the local profile is encrypted under the Keychain key anyway.
    var profileKey: Data?
    public var keyGeneration: UInt32 = 0
    /// Machines ever revoked, as storage last showed them; see `SyncSnapshot.revoked`.
    public var revoked: [String] = []
    var lastStamp: Stamp?
    var baseline: [String: SyncBaseline] = [:]
    public var lastSync: Date?

    public init(identity: SyncIdentity, storages: [UUID]) {
        self.identity = identity
        self.storages = storages
    }

    /// Whether another machine (or this one, creating the storage) has let it in.
    public var isJoined: Bool { profileKey != nil }

    var clock: HybridClock { HybridClock(machine: identity.id, last: lastStamp) }

    /// The local profile as records.
    ///
    /// The profile itself has no clocks: edits are noticed here, by comparing
    /// each item with what was last synced. Unchanged items keep their stamp;
    /// changed and new ones get a fresh one; items that disappeared become
    /// deletion marks. Sync runs shortly after every save, so a fresh stamp is
    /// close to when the edit was made.
    public mutating func stamp(_ items: [SyncItem], now: Int64) -> [SyncRecord] {
        var clock = clock
        var records: [SyncRecord] = []
        var seen = Set<String>()
        for item in items where seen.insert(item.key).inserted {
            let digest = Self.digest(item.payload)
            let stamp: Stamp
            if let base = baseline[item.key], base.digest == digest, !digest.isEmpty {
                stamp = base.stamp
            } else {
                stamp = clock.tick(now: now)
            }
            records.append(SyncRecord(kind: item.kind, id: item.id, stamp: stamp, payload: item.payload))
        }
        for (key, base) in baseline.sorted(by: { $0.key < $1.key }) where !seen.contains(key) {
            guard base.applied, let kind = SyncRecord.Kind(rawValue: String(key.prefix { $0 != "/" })) else {
                continue
            }
            let id = String(key.drop { $0 != "/" }.dropFirst())
            let stamp = base.digest.isEmpty ? base.stamp : clock.tick(now: now)
            records.append(SyncRecord(kind: kind, id: id, stamp: stamp, payload: nil))
        }
        lastStamp = clock.last
        return records
    }

    /// Remembers what the profile holds after merged records were applied.
    ///
    /// The digest is taken from this machine's own encoding of the item, not
    /// from the payload that came in: otherwise a field this version does not
    /// know would look like a local edit forever.
    public mutating func rebase(_ items: [SyncItem], merged: [SyncRecord]) {
        let local = Dictionary(items.map { ($0.key, $0.payload) }, uniquingKeysWith: { first, _ in first })
        baseline = [:]
        for record in merged {
            if record.isDeleted {
                baseline[record.key] = SyncBaseline(stamp: record.stamp, digest: Data(), applied: true)
            } else if let payload = local[record.key] {
                baseline[record.key] = SyncBaseline(
                    stamp: record.stamp, digest: Self.digest(payload), applied: true)
            } else {
                baseline[record.key] = SyncBaseline(stamp: record.stamp, digest: Data([0]), applied: false)
            }
        }
    }

    /// Forgets what was last agreed on: every local item then counts as an
    /// edit, and nothing counts as deleted. For a profile replaced wholesale
    /// by an import, which must not delete on every machine what it lacks.
    public mutating func forgetHistory() { baseline = [:] }

    static func digest(_ payload: Data) -> Data { Data(SHA256.hash(data: payload)) }
}

extension SyncState {
    private enum CodingKeys: String, CodingKey {
        case identity, storages, marks, machines, revoked, profileKey, keyGeneration, lastStamp, baseline,
            lastSync
        // Сборка 168 знала одно хранилище: читаем его как список из одного.
        case storage, lastRevision, epoch
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        identity = try container.decode(SyncIdentity.self, forKey: .identity)
        if let list = try container.decodeIfPresent([UUID].self, forKey: .storages) {
            storages = list
            marks = try container.decodeIfPresent([UUID: StorageMark].self, forKey: .marks) ?? [:]
        } else {
            let single = try container.decode(UUID.self, forKey: .storage)
            storages = [single]
            marks = [
                single: StorageMark(
                    revision: try container.decodeIfPresent(UInt64.self, forKey: .lastRevision) ?? 0,
                    epoch: try container.decodeIfPresent(UInt32.self, forKey: .epoch) ?? 0)
            ]
        }
        machines = try container.decodeIfPresent([SyncMachine].self, forKey: .machines) ?? []
        revoked = try container.decodeIfPresent([String].self, forKey: .revoked) ?? []
        profileKey = try container.decodeIfPresent(Data.self, forKey: .profileKey)
        keyGeneration = try container.decodeIfPresent(UInt32.self, forKey: .keyGeneration) ?? 0
        lastStamp = try container.decodeIfPresent(Stamp.self, forKey: .lastStamp)
        baseline = try container.decodeIfPresent([String: SyncBaseline].self, forKey: .baseline) ?? [:]
        lastSync = try container.decodeIfPresent(Date.self, forKey: .lastSync)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(identity, forKey: .identity)
        try container.encode(storages, forKey: .storages)
        try container.encode(marks, forKey: .marks)
        try container.encode(machines, forKey: .machines)
        try container.encode(revoked, forKey: .revoked)
        try container.encodeIfPresent(profileKey, forKey: .profileKey)
        try container.encode(keyGeneration, forKey: .keyGeneration)
        try container.encodeIfPresent(lastStamp, forKey: .lastStamp)
        try container.encode(baseline, forKey: .baseline)
        try container.encodeIfPresent(lastSync, forKey: .lastSync)
    }
}
