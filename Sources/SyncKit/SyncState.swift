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

/// Everything this machine keeps about sync, inside its encrypted profile.
public struct SyncState: Codable, Sendable, Equatable {
    public var identity: SyncIdentity
    /// The host whose folder holds the shared snapshot.
    public var storage: UUID
    /// The highest revision seen: storage handing back anything lower is refused.
    public var lastRevision: UInt64 = 0
    /// Machines this one trusts to sign snapshots. Empty until it is let in.
    public var machines: [SyncMachine] = []
    /// The profile key, unwrapped. A secret, but it sits next to the hosts it
    /// protects: the local profile is encrypted under the Keychain key anyway.
    var profileKey: Data?
    public var keyGeneration: UInt32 = 0
    /// The storage epoch last seen; see `SyncSnapshot.epoch`.
    public var epoch: UInt32 = 0
    var lastStamp: Stamp?
    var baseline: [String: SyncBaseline] = [:]
    public var lastSync: Date?

    public init(identity: SyncIdentity, storage: UUID) {
        self.identity = identity
        self.storage = storage
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
