import CryptoKit
import Foundation
import Testing

@testable import SyncKit

/// Машина с программными ключами — в приложении они будут в Secure Enclave.
private struct TestMachine {
    let signing = P256.Signing.PrivateKey()
    let agreement = P256.KeyAgreement.PrivateKey()
    let entry: SyncMachine

    init(_ id: String) {
        entry = SyncMachine(
            id: id, name: id, signingKey: signing.publicKey.x963Representation,
            agreementKey: agreement.publicKey.x963Representation)
    }

    func sign(_ snapshot: SyncSnapshot) throws -> SignedSnapshot {
        try SyncCrypto.sign(snapshot, signer: entry.id) { try signing.signature(for: $0) }
    }
}

private func record(_ id: String, _ text: String?, at millis: Int64, by machine: String = "a") -> SyncRecord {
    SyncRecord(
        kind: .host, id: id, stamp: Stamp(millis: millis, counter: 0, machine: machine),
        payload: text.map { Data($0.utf8) })
}

@Suite("Синхронизация: часы и слияние")
struct SyncMergeTests {
    @Test("часы не идут назад, даже если системные отстали")
    func clockMonotonic() {
        var clock = HybridClock(machine: "a")
        let first = clock.tick(now: 1_000)
        let second = clock.tick(now: 900)
        #expect(second > first)
        clock.observe(Stamp(millis: 5_000, counter: 3, machine: "b"), now: 1_000)
        let third = clock.tick(now: 1_000)
        #expect(third > Stamp(millis: 5_000, counter: 3, machine: "b"))
    }

    @Test("штамп из будущего дальше суток не тащит часы за собой, а машина с ним видна (#28)")
    func clockFromTheFuture() {
        let day = HybridClock.maxSkew
        var clock = HybridClock(machine: "a")
        clock.observe(Stamp(millis: 1_000 + 400 * day, counter: 0, machine: "broken"), now: 1_000)
        #expect(clock.tick(now: 2_000).millis == 2_000)
        clock.observe(Stamp(millis: 1_000 + day / 2, counter: 0, machine: "b"), now: 1_000)
        #expect(clock.tick(now: 2_000).millis == 1_000 + day / 2)
        let records = [record("web", "x", at: 1_000 + 400 * day, by: "broken"), record("db", "y", at: 900)]
        #expect(SyncMerge.ahead(records, now: 1_000) == ["broken": 400 * day])
    }

    @Test("свои часы ушли вперёд и вернулись — следующая правка штампуется около настоящего времени")
    func ownClockBack() {
        let year = 365 * HybridClock.maxSkew
        var clock = HybridClock(machine: "a")
        _ = clock.tick(now: 1_000 + year)
        #expect(clock.tick(now: 2_000).millis == 2_000)
    }

    @Test("правки разных записей с двух машин сохраняются обе")
    func differentItemsBothKept() {
        let merged = SyncMerge.merge(
            [record("web", "a-edit", at: 10)], [record("db", "b-edit", at: 11, by: "b")], now: 20)
        #expect(merged.map(\.id) == ["db", "web"])
    }

    @Test("в одной записи побеждает поздняя правка, в любом порядке слияния")
    func laterWins() {
        let old = record("web", "old", at: 10)
        let new = record("web", "new", at: 11, by: "b")
        #expect(SyncMerge.merge([old], [new], now: 20).first?.payload == Data("new".utf8))
        #expect(SyncMerge.merge([new], [old], now: 20).first?.payload == Data("new".utf8))
    }

    @Test("удаление позже правки побеждает и доходит до других; старая метка забывается")
    func tombstones() {
        let edit = record("web", "x", at: 10)
        let deletion = record("web", nil, at: 11, by: "b")
        let merged = SyncMerge.merge([edit], [deletion], now: 20)
        #expect(merged.count == 1 && merged[0].isDeleted)
        let later = 11 + SyncMerge.tombstoneLifetime
        #expect(SyncMerge.merge(merged, [], now: later).isEmpty)
    }
}

@Suite("Синхронизация: шифрование и подписи")
struct SyncCryptoTests {
    private let key = SymmetricKey(size: .bits256)

    @Test("запись открывается тем же ключом, а хранилище видит только тип, id и время")
    func sealOpen() throws {
        let records = [record("web", "secret host", at: 10), record("old", nil, at: 11)]
        let sealed = try SyncCrypto.seal(records, key: key, generation: 0)
        #expect(sealed[0].box.map { !String(decoding: $0, as: UTF8.self).contains("secret") } == true)
        #expect(sealed[1].box == nil)
        #expect(try SyncCrypto.open(sealed, key: key, generation: 0) == records)
    }

    @Test("содержимое нельзя переложить в другую запись или поколение ключа")
    func bindingHolds() throws {
        var sealed = try SyncCrypto.seal([record("web", "x", at: 10)], key: key, generation: 0)
        #expect(throws: SyncError.unreadable("host/web")) {
            try SyncCrypto.open(sealed, key: key, generation: 1)
        }
        sealed[0].id = "db"
        #expect(throws: SyncError.unreadable("host/db")) {
            try SyncCrypto.open(sealed, key: key, generation: 0)
        }
    }

    @Test("ключ профиля открывают только машины из списка")
    func wrapping() throws {
        let laptop = TestMachine("laptop")
        let mini = TestMachine("mini")
        let stranger = TestMachine("stranger")
        let snapshot = SyncSnapshot(
            machines: [laptop.entry, mini.entry],
            keys: [try SyncCrypto.wrap(key, for: laptop.entry), try SyncCrypto.wrap(key, for: mini.entry)])
        let opened = try SyncCrypto.unwrap(snapshot, machine: "mini", with: mini.agreement)
        #expect(opened == key)
        #expect(throws: SyncError.notForThisMachine) {
            try SyncCrypto.unwrap(snapshot, machine: "stranger", with: stranger.agreement)
        }
        #expect(throws: SyncError.unreadable("profile key")) {
            try SyncCrypto.unwrap(snapshot, machine: "mini", with: stranger.agreement)
        }
    }

    @Test("ключ в Secure Enclave открывает обёрнутый ключ профиля", .enabled(if: SecureEnclave.isAvailable))
    func secureEnclave() throws {
        let enclave = try SecureEnclave.P256.KeyAgreement.PrivateKey()
        let machine = SyncMachine(
            id: "mac", name: "mac", signingKey: Data(), agreementKey: enclave.publicKey.x963Representation)
        let snapshot = SyncSnapshot(machines: [machine], keys: [try SyncCrypto.wrap(key, for: machine)])
        #expect(try SyncCrypto.unwrap(snapshot, machine: "mac", with: enclave) == key)
    }

    @Test("снимок принимается только с подписью доверенной машины и не старше виденного")
    func acceptance() throws {
        let laptop = TestMachine("laptop")
        let stranger = TestMachine("stranger")
        let signed = try laptop.sign(SyncSnapshot(revision: 7, machines: [laptop.entry]))

        #expect(try SyncCrypto.accept(signed, trusted: [laptop.entry], lastRevision: 7).revision == 7)
        #expect(throws: SyncError.rollback(seen: 8, got: 7)) {
            try SyncCrypto.accept(signed, trusted: [laptop.entry], lastRevision: 8)
        }
        #expect(throws: SyncError.unknownSigner("laptop")) {
            try SyncCrypto.accept(signed, trusted: [stranger.entry], lastRevision: 0)
        }

        // Хранилище подменило ревизию в теле — подпись больше не сходится.
        var forged = signed
        forged.body = Data(
            String(decoding: signed.body, as: UTF8.self)
                .replacingOccurrences(of: "\"revision\":7", with: "\"revision\":9").utf8)
        #expect(forged.body != signed.body)
        #expect(throws: SyncError.badSignature) {
            try SyncCrypto.accept(forged, trusted: [laptop.entry], lastRevision: 0)
        }

        // Чужой ключ, выдающий себя за ноутбук.
        let impostor = try SyncCrypto.sign(SyncSnapshot(revision: 99), signer: "laptop") {
            try stranger.signing.signature(for: $0)
        }
        #expect(throws: SyncError.badSignature) {
            try SyncCrypto.accept(impostor, trusted: [laptop.entry], lastRevision: 0)
        }
    }
}
