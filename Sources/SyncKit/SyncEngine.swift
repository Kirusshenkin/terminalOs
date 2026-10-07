import CryptoKit
public import Foundation

/// One round of sync: read storage, merge, write back if anything changed.
public enum SyncEngine {
    public enum Outcome: Sendable {
        /// Merged records to apply to the profile, machines waiting at the door,
        /// and the storages that failed this round — the others went through.
        case synced(
            records: [SyncRecord], state: SyncState, requests: [SyncMachine], failures: [UUID: any Error])
        /// Storage already holds a profile, and this machine is not let in yet.
        /// The request is left there; another machine shows the same code.
        case awaitingApproval(state: SyncState, code: String)
        /// This machine was let in, but it trusts nobody yet. Before anything of
        /// its own goes into storage, the person compares the code of the
        /// machine that let it in with what that machine shows for itself:
        /// otherwise storage could build a snapshot of its own around this
        /// machine's public keys and collect its hosts.
        case confirmSigner(state: SyncState, signer: SyncMachine)
    }

    /// What the person asked for on this round, besides syncing.
    public struct Changes: Sendable, Equatable {
        public var approve: [String] = []
        public var revoke: [String] = []
        /// The machine whose code the person confirmed on first joining — the
        /// whole entry with its keys, not just the id: storage could otherwise
        /// swap in a machine of its own under the same id between the check and
        /// the next round.
        public var trust: SyncMachine?

        public init(approve: [String] = [], revoke: [String] = [], trust: SyncMachine? = nil) {
            self.approve = approve
            self.revoke = revoke
            self.trust = trust
        }
    }

    /// How many times a round is repeated when a write lost a race.
    static let attempts = 3

    /// - Parameter remotes: every storage of `state.storages` that can be
    ///   reached now; a missing one counts as down for this round.
    public static func run(
        items: [SyncItem], state: SyncState, remotes: [UUID: SyncRemote], changes: Changes = Changes(),
        now: @Sendable () -> Int64 = { Int64(Date().timeIntervalSince1970 * 1_000) }
    ) async throws -> Outcome {
        for attempt in 1...attempts {
            var round = Round(items: items, state: state, remotes: remotes, changes: changes, now: now())
            do {
                return try await round.run()
            } catch SyncError.busy where attempt < attempts {
                continue
            }
        }
        throw SyncError.busy
    }
}

/// One round over every storage: read all, check, merge, write all.
///
/// Each storage holds a full copy. Machines and the profile key are shared:
/// the snapshot with the newest key generation decides them, so a storage
/// that missed a revocation cannot bring the revoked machine back. Revision
/// and epoch are per storage, and so is every failure: one server down or
/// tampered with is reported, the others carry on.
private struct Round {
    let items: [SyncItem]
    var state: SyncState
    let remotes: [UUID: SyncRemote]
    let changes: SyncEngine.Changes
    let now: Int64

    /// What one storage showed this round.
    private struct Copy {
        var view: SyncRemote.View
        var snapshot: SyncSnapshot?
        var records: [SyncRecord]?
    }

    private var copies: [UUID: Copy] = [:]
    private var failures: [UUID: any Error] = [:]

    init(
        items: [SyncItem], state: SyncState, remotes: [UUID: SyncRemote], changes: SyncEngine.Changes,
        now: Int64
    ) {
        self.items = items
        self.state = state
        self.remotes = remotes
        self.changes = changes
        self.now = now
    }

    mutating func run() async throws -> SyncEngine.Outcome {
        let me = try state.identity.machine()
        for id in state.storages {
            guard let remote = remotes[id] else {
                failures[id] = SyncError.storage("")
                continue
            }
            do {
                copies[id] = Copy(view: try await remote.read())
            } catch {
                failures[id] = error
            }
        }
        guard !copies.isEmpty else { throw failures.values.first ?? SyncError.storage("") }

        if state.machines.isEmpty, copies.values.contains(where: { $0.view.snapshot != nil }) {
            if let early = try await firstContact(me) { return early }
        }
        acceptAll()
        let requests = uniqueRequests()
        var shared = try sharedBase(me)
        let local = state.stamp(items, now: now)
        var clock = state.clock
        for record in shared.records { clock.observe(record.stamp, now: now) }
        state.lastStamp = clock.last
        let merged = SyncMerge.merge(shared.records, local, now: now)

        let approved = try admit(requests, to: &shared, me: me)
        var busy = false
        for (id, copy) in copies.sorted(by: { $0.key.uuidString < $1.key.uuidString }) {
            guard failures[id] == nil, let remote = remotes[id] else { continue }
            do {
                try await write(merged, shared: shared, copy: copy, to: remote, id: id, approved: approved)
            } catch SyncError.busy {
                busy = true
            } catch {
                failures[id] = error
            }
        }
        if busy { throw SyncError.busy }
        guard failures.count < state.storages.count else {
            throw failures.values.first ?? SyncError.storage("")
        }

        state.machines = shared.machines
        state.keyGeneration = shared.generation
        state.profileKey = shared.key.withUnsafeBytes { Data($0) }
        state.lastSync = Date(timeIntervalSince1970: Double(now) / 1_000)
        let members = Set(shared.machines.map(\.id))
        return .synced(
            records: merged, state: state, requests: requests.filter { !members.contains($0.id) },
            failures: failures)
    }

    /// A machine that trusts nobody yet. nil: it was let in and the person
    /// confirmed who did it — carry on with a normal round.
    private mutating func firstContact(_ me: SyncMachine) async throws -> SyncEngine.Outcome? {
        for (id, copy) in copies.sorted(by: { $0.key.uuidString < $1.key.uuidString }) {
            guard let signed = copy.view.snapshot else { continue }
            let first: SyncSnapshot?
            do {
                first = try SyncCrypto.acceptFirst(signed, me: me)
            } catch {
                // Битый снимок на одном сервере не мешает войти через другой.
                failures[id] = error
                continue
            }
            guard let first, let signer = first.machines.first(where: { $0.id == signed.signer }) else {
                continue
            }
            guard signer == changes.trust else { return .confirmSigner(state: state, signer: signer) }
            state.machines = first.machines
            return nil
        }
        for (id, copy) in copies where !copy.view.requests.contains(where: { $0.id == me.id }) {
            guard let remote = remotes[id] else { continue }
            do { try await remote.request(me) } catch { failures[id] = error }
        }
        return .awaitingApproval(state: state, code: me.code)
    }

    /// Checks every snapshot against the trusted machines and that storage's mark.
    private mutating func acceptAll() {
        for (id, copy) in copies {
            guard let signed = copy.view.snapshot else { continue }
            let mark = state.marks[id] ?? StorageMark()
            do {
                let snapshot = try SyncCrypto.accept(
                    signed, trusted: state.machines, lastRevision: mark.revision, lastEpoch: mark.epoch)
                copies[id]?.snapshot = snapshot
                // Снимок старшего поколения без этой машины ещё не значит отзыв:
                // решает только общий список ниже. Открывается то, что открывается.
                if let key = try? state.identity.unwrap(snapshot) {
                    copies[id]?.records = try SyncCrypto.open(
                        snapshot.records, key: key, generation: snapshot.keyGeneration)
                }
            } catch {
                failures[id] = error
            }
        }
    }

    private func uniqueRequests() -> [SyncMachine] {
        var seen = Set<String>()
        return copies.sorted { $0.key.uuidString < $1.key.uuidString }
            .flatMap(\.value.view.requests)
            .filter { seen.insert($0.id).inserted }
    }

    /// Machines, key and records every storage gets this round.
    private struct Shared {
        var machines: [SyncMachine]
        var generation: UInt32
        var key: SymmetricKey
        var records: [SyncRecord]
    }

    private func sharedBase(_ me: SyncMachine) throws -> Shared {
        let accepted = copies.filter { failures[$0.key] == nil }.compactMap(\.value.snapshot)
        guard let top = accepted.map(\.keyGeneration).max() else {
            // Ни одного снимка: хранилища пустые или их стёрли. Профиль у нас
            // на руках — складываем заново под прежним ключом; нет — заводим.
            if let stored = state.profileKey {
                return Shared(
                    machines: state.machines.isEmpty ? [me] : state.machines, generation: state.keyGeneration,
                    key: SymmetricKey(data: stored), records: [])
            }
            return Shared(machines: [me], generation: 0, key: SymmetricKey(size: .bits256), records: [])
        }
        var machines: [SyncMachine] = []
        for snapshot in accepted where snapshot.keyGeneration == top {
            for machine in snapshot.machines where !machines.contains(where: { $0.id == machine.id }) {
                machines.append(machine)
            }
        }
        guard machines.contains(where: { $0.id == me.id }),
            let newest = accepted.first(where: { $0.keyGeneration == top && $0.machines.contains(me) })
        else { throw SyncError.notForThisMachine }
        let records = copies.values.compactMap(\.records).reduce([SyncRecord]()) {
            SyncMerge.merge($0, $1, now: now)
        }
        return Shared(
            machines: machines, generation: top, key: try state.identity.unwrap(newest), records: records)
    }

    /// Lets approved machines in and removes revoked ones. Returns the ids of
    /// requests used up, so storage can drop them.
    private func admit(_ requests: [SyncMachine], to shared: inout Shared, me: SyncMachine) throws -> [String]
    {
        let approved = requests.filter { request in
            changes.approve.contains(request.id) && !shared.machines.contains { $0.id == request.id }
        }
        shared.machines += approved
        let revoked = changes.revoke.filter { id in id != me.id && shared.machines.contains { $0.id == id } }
        if !revoked.isEmpty {
            // Отзыв меняет ключ: записи всё равно запечатываются заново.
            shared.machines.removeAll { revoked.contains($0.id) }
            shared.key = SymmetricKey(size: .bits256)
            shared.generation += 1
        }
        return approved.map(\.id)
    }

    /// Writes one storage if what it holds differs from what it should.
    private mutating func write(
        _ merged: [SyncRecord], shared: Shared, copy: Copy, to remote: SyncRemote, id: UUID,
        approved: [String]
    ) async throws {
        let mark = state.marks[id] ?? StorageMark()
        let held = copy.snapshot
        let current =
            held.map { snapshot in
                snapshot.keyGeneration == shared.generation
                    && Set(snapshot.machines.map(\.id)) == Set(shared.machines.map(\.id))
                    && copy.records.map { $0.sorted { $0.key < $1.key } } == merged
            } ?? false
        let consumes = copy.view.requests.contains { approved.contains($0.id) }
        guard !current || consumes else {
            if let held { state.marks[id] = StorageMark(revision: held.revision, epoch: held.epoch) }
            return
        }
        var next = SyncSnapshot(
            revision: max(held?.revision ?? 0, copy.view.revision, mark.revision) + 1,
            keyGeneration: shared.generation, machines: shared.machines)
        // Пустое хранилище, где эта машина уже бывала, — папку стёрли:
        // новая эпоха, чтобы ушедшие вперёд машины не приняли её за откат.
        next.epoch = held?.epoch ?? (mark == StorageMark() ? 0 : mark.epoch + 1)
        next.keys = try shared.machines.map { machine throws(SyncError) in
            try SyncCrypto.wrap(shared.key, for: machine)
        }
        next.records = try SyncCrypto.seal(merged, key: shared.key, generation: shared.generation)
        try await remote.write(
            try state.identity.sign(next), revision: next.revision, expecting: copy.view.revision,
            consuming: approved)
        state.marks[id] = StorageMark(revision: next.revision, epoch: next.epoch)
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
