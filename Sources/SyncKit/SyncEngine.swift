import CryptoKit
public import Foundation

/// One round of sync: read storage, merge, write back if anything changed.
public enum SyncEngine {
    public enum Outcome: Sendable, Equatable {
        /// Merged records to apply to the profile, and machines waiting at the door.
        case synced(records: [SyncRecord], state: SyncState, requests: [SyncMachine])
        /// Storage already holds a profile, and this machine is not let in yet.
        /// The request is left there; another machine shows the same code.
        case awaitingApproval(state: SyncState, code: String)
    }

    /// What the person asked for on this round, besides syncing.
    public struct Changes: Sendable, Equatable {
        public var approve: [String] = []
        public var revoke: [String] = []

        public init(approve: [String] = [], revoke: [String] = []) {
            self.approve = approve
            self.revoke = revoke
        }
    }

    /// How many times a write that lost a race is retried from a fresh read.
    static let attempts = 3

    public static func run(
        items: [SyncItem], state: SyncState, remote: SyncRemote, changes: Changes = Changes(),
        now: @Sendable () -> Int64 = { Int64(Date().timeIntervalSince1970 * 1_000) }
    ) async throws -> Outcome {
        for _ in 0..<attempts {
            do {
                return try await round(
                    items: items, state: state, remote: remote, changes: changes, now: now())
            } catch SyncError.busy {
                continue
            }
        }
        throw SyncError.busy
    }

    /// What a round works on: the snapshot to write next and its key.
    private struct Base {
        var snapshot: SyncSnapshot
        var key: SymmetricKey
        var records: [SyncRecord] = []
        var mustWrite = false
    }

    private static func round(
        items: [SyncItem], state initial: SyncState, remote: SyncRemote, changes: Changes, now: Int64
    ) async throws -> Outcome {
        var state = initial
        let me = try state.identity.machine()
        let view = try await remote.read()
        guard var base = try open(view, state: state, me: me) else {
            if !view.requests.contains(where: { $0.id == me.id }) { try await remote.request(me) }
            return .awaitingApproval(state: state, code: me.code)
        }

        // Свои правки штампуются до того, как часы увидят чужие: так штамп
        // ближе ко времени правки, а не ко времени синхронизации.
        let local = state.stamp(items, now: now)
        var clock = state.clock
        for record in base.records { clock.observe(record.stamp, now: now) }
        state.lastStamp = clock.last
        let merged = SyncMerge.merge(base.records, local, now: now)
        if merged != base.records.sorted(by: { $0.key < $1.key }) { base.mustWrite = true }

        let approved = try admit(view.requests, to: &base, changes: changes, me: me)
        if base.mustWrite {
            base.snapshot.revision = max(base.snapshot.revision, view.revision, state.lastRevision) + 1
            base.snapshot.records = try SyncCrypto.seal(
                merged, key: base.key, generation: base.snapshot.keyGeneration)
            try await remote.write(
                try state.identity.sign(base.snapshot), revision: base.snapshot.revision,
                expecting: view.revision, consuming: approved)
        }

        state.lastRevision = base.snapshot.revision
        state.machines = base.snapshot.machines
        state.keyGeneration = base.snapshot.keyGeneration
        state.profileKey = base.key.withUnsafeBytes { Data($0) }
        state.lastSync = Date(timeIntervalSince1970: Double(now) / 1_000)
        let members = Set(base.snapshot.machines.map(\.id))
        let waiting = view.requests.filter { !members.contains($0.id) }
        return .synced(records: merged, state: state, requests: waiting)
    }

    /// Checks and opens what storage holds. nil: this machine is not let in yet.
    private static func open(_ view: SyncRemote.View, state: SyncState, me: SyncMachine) throws -> Base? {
        if let signed = view.snapshot {
            let snapshot: SyncSnapshot
            if state.machines.isEmpty {
                guard let first = try SyncCrypto.acceptFirst(signed, me: me) else { return nil }
                snapshot = first
            } else {
                snapshot = try SyncCrypto.accept(
                    signed, trusted: state.machines, lastRevision: state.lastRevision)
            }
            guard snapshot.machines.contains(where: { $0.id == me.id }) else {
                throw SyncError.notForThisMachine
            }
            let key = try state.identity.unwrap(snapshot)
            let records = try SyncCrypto.open(snapshot.records, key: key, generation: snapshot.keyGeneration)
            return Base(snapshot: snapshot, key: key, records: records)
        }
        if state.isJoined, let stored = state.profileKey {
            // Папку стёрли или сервер переустановили: профиль у нас на руках,
            // складываем его заново под прежним ключом и для прежних машин.
            let key = SymmetricKey(data: stored)
            var snapshot = SyncSnapshot(
                revision: max(state.lastRevision, view.revision), keyGeneration: state.keyGeneration,
                machines: state.machines.isEmpty ? [me] : state.machines)
            snapshot.keys = try snapshot.machines.map { machine throws(SyncError) in
                try SyncCrypto.wrap(key, for: machine)
            }
            return Base(snapshot: snapshot, key: key, mustWrite: true)
        }
        // Хранилище пустое: эта машина его и заводит.
        let key = SymmetricKey(size: .bits256)
        let snapshot = SyncSnapshot(
            revision: view.revision, machines: [me], keys: [try SyncCrypto.wrap(key, for: me)])
        return Base(snapshot: snapshot, key: key, mustWrite: true)
    }

    /// Lets approved machines in and removes revoked ones. Returns the ids of
    /// requests used up, so storage can drop them.
    private static func admit(
        _ requests: [SyncMachine], to base: inout Base, changes: Changes, me: SyncMachine
    ) throws(SyncError) -> [String] {
        let approved = requests.filter { request in
            changes.approve.contains(request.id) && !base.snapshot.machines.contains { $0.id == request.id }
        }
        for machine in approved {
            base.snapshot.machines.append(machine)
            base.snapshot.keys.append(try SyncCrypto.wrap(base.key, for: machine))
            base.mustWrite = true
        }
        let revoked = changes.revoke.filter { id in
            id != me.id && base.snapshot.machines.contains { $0.id == id }
        }
        if !revoked.isEmpty {
            // Отзыв меняет ключ: записи всё равно запечатываются заново.
            base.snapshot.machines.removeAll { revoked.contains($0.id) }
            base.key = SymmetricKey(size: .bits256)
            base.snapshot.keyGeneration += 1
            base.snapshot.keys = try base.snapshot.machines.map { machine throws(SyncError) in
                try SyncCrypto.wrap(base.key, for: machine)
            }
            base.mustWrite = true
        }
        return approved.map(\.id)
    }
}

extension SyncCrypto {
    /// The first snapshot a new machine sees, when it trusts nobody yet.
    ///
    /// It is believed if it lists this very machine with its own keys —
    /// meaning a machine that was let in approved it after comparing the code —
    /// and is signed by a machine on that same list. nil: not let in yet.
    static func acceptFirst(_ signed: SignedSnapshot, me: SyncMachine) throws(SyncError) -> SyncSnapshot? {
        let unverified: SyncSnapshot
        do {
            unverified = try JSONDecoder().decode(SyncSnapshot.self, from: signed.body)
        } catch {
            throw .malformed("snapshot")
        }
        guard unverified.machines.contains(me) else { return nil }
        return try accept(signed, trusted: unverified.machines, lastRevision: 0)
    }
}
