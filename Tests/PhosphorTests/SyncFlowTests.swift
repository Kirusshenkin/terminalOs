import CryptoKit
import Foundation
import HostsKit
import PhosphorCore
import SSHKit
import Testing

@testable import SyncKit

/// Хранилище — папка во временном каталоге, команды идут в локальный sh, как
/// пошли бы по ssh. Сети нет: проверяется сам сценарий и сами команды.
private struct Folder {
    let home: String
    /// Оболочка сервера: на Маке sh — это bash, на Debian и Ubuntu — dash.
    var shell = "/bin/sh"

    init() throws {
        home = NSTemporaryDirectory() + "phosphor-sync-\(UUID().uuidString)"
        try FileManager.default.createDirectory(atPath: home, withIntermediateDirectories: true)
    }

    var remote: SyncRemote {
        let home = home
        let shell = shell
        return SyncRemote { command, input in
            try await Subprocess.run(
                executable: shell, arguments: ["-c", "HOME=\(Shell.quote(home)); \(command)"],
                input: input)
        }
    }

    var path: String { home + "/.phosphor-sync" }
}

/// Машина: свой профиль и своё состояние синхронизации.
private struct Mac {
    var book = HostBook()
    var state: SyncState
    var requests: [SyncMachine] = []
    /// Машина, которая пустила эту и ждёт сверки кода.
    var signer: SyncMachine?
    /// Хранилища, не прошедшие последний круг.
    var failures: [UUID: any Error] = [:]

    init(_ name: String, storage: UUID) throws {
        try self.init(name, storages: [storage])
    }

    init(_ name: String, storages: [UUID]) throws {
        state = SyncState(
            identity: try SyncIdentity.create(name: name, useEnclave: false), storages: storages)
    }

    /// Ревизия первого хранилища — то, что видит машина с одним сервером.
    var revision: UInt64 { state.marks[state.storages[0]]?.revision ?? 0 }

    @discardableResult
    mutating func sync(
        _ remote: SyncRemote, _ changes: SyncEngine.Changes = .init(), at now: Int64 = 1_000
    ) async throws -> String? {
        try await sync(remotes: [state.storages[0]: remote], changes, at: now)
    }

    /// Один круг, как его делает приложение: записи из профиля, слияние,
    /// результат обратно в профиль. Возвращает код, если машину ещё не пустили.
    @discardableResult
    mutating func sync(
        remotes: [UUID: SyncRemote], _ changes: SyncEngine.Changes = .init(), at now: Int64 = 1_000
    ) async throws -> String? {
        switch try await SyncEngine.run(
            items: book.syncItems(), state: state, remotes: remotes, changes: changes, now: { now })
        {
        case .awaitingApproval(let next, let code):
            state = next
            return code
        case .confirmSigner(let next, let machine):
            state = next
            signer = machine
            return nil
        case .synced(let records, let next, let waiting, let failed):
            state = next
            failures = failed
            book.applySync(records)
            state.rebase(book.syncItems(), merged: records)
            requests = waiting
            return nil
        }
    }
}

/// A заводит хранилище, B просится, A пускает по совпавшему коду.
private struct SyncFlowPairing {
    let storage: UUID

    func pair(_ folder: Folder) async throws -> (Mac, Mac) {
        var a = try Mac("a", storage: storage)
        a.book.hosts = [ServerHost(name: "web", address: "10.0.0.1")]
        try await a.sync(folder.remote)
        var b = try Mac("b", storage: storage)
        let code = try await b.sync(folder.remote)
        #expect(code != nil)
        try await a.sync(folder.remote)
        #expect(a.requests.map(\.code) == [code])
        try await a.sync(folder.remote, .init(approve: a.requests.map(\.id)), at: 2_000)
        try await b.sync(folder.remote, at: 3_000)
        // Новая машина сверяет код той, что её пустила, и только потом льёт своё.
        let signer = try #require(b.signer)
        #expect(try signer.code == a.state.identity.machine().code)
        #expect(!b.state.isJoined)
        try await b.sync(folder.remote, .init(trust: signer), at: 3_000)
        #expect(b.state.isJoined)
        return (a, b)
    }
}

@Suite("Синхронизация: две машины через папку на сервере")
struct SyncFlowTests {
    let storage = UUID()

    private func pair(_ folder: Folder) async throws -> (Mac, Mac) {
        try await SyncFlowPairing(storage: storage).pair(folder)
    }

    @Test("новая машина ждёт подтверждения, а после него получает хосты")
    func joinFlow() async throws {
        let folder = try Folder()
        let (a, b) = try await pair(folder)
        #expect(b.book.hosts.map(\.name) == ["web"])
        #expect(b.state.machines.count == 2 && a.state.isJoined && b.state.isJoined)
        // Просьба использована и убрана из папки.
        let left = try FileManager.default.contentsOfDirectory(atPath: folder.path + "/requests")
        #expect(left.isEmpty)
    }

    @Test("правки разных хостов на двух машинах сохраняются обе, удаление доходит")
    func editsAndDeletion() async throws {
        let folder = try Folder()
        var (a, b) = try await pair(folder)
        a.book.hosts.append(ServerHost(name: "db", address: "10.0.0.2"))
        b.book.hosts[0].name = "web-prod"
        try await a.sync(folder.remote, at: 4_000)
        try await b.sync(folder.remote, at: 5_000)
        try await a.sync(folder.remote, at: 6_000)
        #expect(Set(a.book.hosts.map(\.name)) == ["web-prod", "db"])
        #expect(Set(b.book.hosts.map(\.name)) == ["web-prod", "db"])

        b.book.hosts.removeAll { $0.name == "db" }
        try await b.sync(folder.remote, at: 7_000)
        try await a.sync(folder.remote, at: 8_000)
        #expect(a.book.hosts.map(\.name) == ["web-prod"])
    }

    @Test("то, что машина видит сама (когда хост отвечал), не синхронизируется и не пишет снимок")
    func observationsStayLocal() async throws {
        let folder = try Folder()
        var (a, b) = try await pair(folder)
        let revision = a.revision
        a.book.remember(a.book.hosts[0].id, osName: "Ubuntu 24.04")
        try await a.sync(folder.remote, at: 4_000)
        #expect(a.revision == revision)
        try await b.sync(folder.remote, at: 5_000)
        #expect(b.book.hosts[0].osName == nil)
        #expect(a.book.hosts[0].osName == "Ubuntu 24.04")
    }

    @Test("отозванная машина больше не читает профиль, оставшаяся работает дальше")
    func revoke() async throws {
        let folder = try Folder()
        var (a, b) = try await pair(folder)
        try await a.sync(folder.remote, .init(revoke: [b.state.identity.id]), at: 4_000)
        #expect(a.state.machines.count == 1 && a.state.keyGeneration == 1)
        await #expect(throws: SyncError.notForThisMachine) { try await b.sync(folder.remote, at: 5_000) }
        a.book.hosts.append(ServerHost(name: "db", address: "10.0.0.2"))
        try await a.sync(folder.remote, at: 6_000)
        try await a.sync(folder.remote, at: 7_000)
        #expect(a.book.hosts.count == 2)
        // Ключом, который остался у отозванной машины, новое не открыть.
        let oldKey = SymmetricKey(data: try #require(b.state.profileKey))
        let stored = try JSONDecoder().decode(
            SignedSnapshot.self, from: Data(contentsOf: URL(fileURLWithPath: folder.path + "/snapshot.json")))
        let snapshot = try JSONDecoder().decode(SyncSnapshot.self, from: stored.body)
        #expect(throws: SyncError.self) {
            try SyncCrypto.open(snapshot.records, key: oldKey, generation: snapshot.keyGeneration)
        }
    }

    @Test("подсунутая старая версия отвергается")
    func rollback() async throws {
        let folder = try Folder()
        var (a, _) = try await pair(folder)
        let old = try Data(contentsOf: URL(fileURLWithPath: folder.path + "/snapshot.json"))
        a.book.hosts.append(ServerHost(name: "db", address: "10.0.0.2"))
        try await a.sync(folder.remote, at: 4_000)
        try old.write(to: URL(fileURLWithPath: folder.path + "/snapshot.json"))
        await #expect(throws: SyncError.rollback(seen: 3, got: 2)) {
            try await a.sync(folder.remote, at: 5_000)
        }
    }

    @Test("занятая блокировка — это «занято», а не порча")
    func busy() async throws {
        let folder = try Folder()
        var a = try Mac("a", storage: storage)
        try FileManager.default.createDirectory(
            atPath: folder.path + "/lock", withIntermediateDirectories: true)
        await #expect(throws: SyncError.busy) { try await a.sync(folder.remote) }
    }

    @Test("разбор ответа: шум профиля оболочки и чужие id пропускаются")
    func parse() throws {
        let stranger = #"{"id":"../../etc","name":"x","signingKey":"","agreementKey":""}"#
        let view = try SyncRemote.parse("Welcome!\nrev 7\nreq \(stranger)\n")
        #expect(view.revision == 7 && view.snapshot == nil && view.requests.isEmpty)
        #expect(throws: SyncError.self) { try SyncRemote.fileName("../x") }
    }

    @Test("код машины — восемь знаков без путаницы I/L/O/U, одинаков на обеих сторонах")
    func code() throws {
        let machine = try SyncIdentity.create(name: "a", useEnclave: false).machine()
        #expect(machine.code.count == 9 && machine.code.contains("-"))
        #expect(!machine.code.contains { "ILOU".contains($0) })
    }
}

/// Хранилище, которое ведёт себя плохо: обрывает передачу, подделывает снимок.
@Suite("Синхронизация: враждебное или ненадёжное хранилище")
struct SyncHostileStorageTests {
    let storage = UUID()

    @Test("оборванная передача не заменяет снимок")
    func truncatedUpload() async throws {
        let folder = try Folder()
        var a = try Mac("a", storage: storage)
        a.book.hosts = [ServerHost(name: "web", address: "10.0.0.1")]
        try await a.sync(folder.remote)
        let before = try Data(contentsOf: URL(fileURLWithPath: folder.path + "/snapshot.json"))
        let home = folder.home
        let cut = SyncRemote { command, input in
            try await Subprocess.run(
                executable: "/bin/sh", arguments: ["-c", "HOME=\(Shell.quote(home)); \(command)"],
                input: input.map { $0.prefix($0.count / 2) })
        }
        a.book.hosts.append(ServerHost(name: "db", address: "10.0.0.2"))
        await #expect(throws: SyncError.storage("upload cut short")) { try await a.sync(cut, at: 2_000) }
        let after = try Data(contentsOf: URL(fileURLWithPath: folder.path + "/snapshot.json"))
        #expect(after == before)
        try await a.sync(folder.remote, at: 3_000)
        #expect(a.book.hosts.count == 2)
    }

    @Test("снимок, собранный хранилищем вокруг ключей новой машины, выдаёт чужой код и ничего не получает")
    func forgedWelcome() async throws {
        let folder = try Folder()
        var a = try Mac("a", storage: storage)
        try await a.sync(folder.remote)
        var b = try Mac("b", storage: storage)
        b.book.hosts = [ServerHost(name: "secret", address: "10.0.0.9")]
        try await b.sync(folder.remote)

        // Хранилище видит публичные ключи B в просьбе и пишет свой снимок.
        let attacker = try SyncIdentity.create(name: "a", useEnclave: false)
        let key = SymmetricKey(size: .bits256)
        let me = try b.state.identity.machine(), evil = try attacker.machine()
        let forged = SyncSnapshot(
            revision: 9, machines: [evil, me],
            keys: [try SyncCrypto.wrap(key, for: evil), try SyncCrypto.wrap(key, for: me)])
        try JSONEncoder().encode(try attacker.sign(forged))
            .write(to: URL(fileURLWithPath: folder.path + "/snapshot.json"))
        try "9".write(toFile: folder.path + "/revision", atomically: true, encoding: .utf8)
        let planted = try Data(contentsOf: URL(fileURLWithPath: folder.path + "/snapshot.json"))

        try await b.sync(folder.remote, at: 2_000)
        let signer = try #require(b.signer)
        #expect(try signer.code != a.state.identity.machine().code)
        #expect(!b.state.isJoined)
        #expect(try Data(contentsOf: URL(fileURLWithPath: folder.path + "/snapshot.json")) == planted)
    }

    @Test("подтверждённую машину нельзя подменить под тем же id до следующего круга")
    func swappedAfterConfirmation() async throws {
        let folder = try Folder()
        var a = try Mac("a", storage: storage)
        try await a.sync(folder.remote)
        var b = try Mac("b", storage: storage)
        try await b.sync(folder.remote)
        try await a.sync(folder.remote, .init(approve: [b.state.identity.id]), at: 2_000)
        try await b.sync(folder.remote, at: 3_000)
        let genuine = try #require(b.signer)

        // Хранилище подменяет снимок: тот же id подписанта, свои ключи.
        var impostor = try SyncIdentity.create(name: genuine.name, useEnclave: false)
        impostor.id = genuine.id
        let key = SymmetricKey(size: .bits256)
        let me = try b.state.identity.machine(), fake = try impostor.machine()
        let forged = SyncSnapshot(
            revision: 9, machines: [fake, me],
            keys: [try SyncCrypto.wrap(key, for: fake), try SyncCrypto.wrap(key, for: me)])
        try JSONEncoder().encode(try impostor.sign(forged))
            .write(to: URL(fileURLWithPath: folder.path + "/snapshot.json"))

        try await b.sync(folder.remote, .init(trust: genuine), at: 4_000)
        #expect(!b.state.isJoined)
        #expect(b.signer == fake)
    }

    @Test("папку стёрли, отстающая машина её пересоздала — ушедшая вперёд не застревает на «откате»")
    func wipedAndRebuilt() async throws {
        let folder = try Folder()
        let pairing = SyncFlowPairing(storage: storage)
        var (a, b) = try await pairing.pair(folder)
        for step in 0..<3 {
            b.book.hosts.append(ServerHost(name: "b\(step)", address: "10.0.1.\(step)"))
            try await b.sync(folder.remote, at: 10_000 + Int64(step))
        }
        try FileManager.default.removeItem(atPath: folder.path)
        a.book.hosts.append(ServerHost(name: "a-only", address: "10.0.2.1"))
        try await a.sync(folder.remote, at: 20_000)
        try await b.sync(folder.remote, at: 21_000)
        try await a.sync(folder.remote, at: 22_000)
        #expect(Set(b.book.hosts.map(\.name)) == Set(a.book.hosts.map(\.name)))
        #expect(b.book.hosts.count == 5)
    }
}

@Suite("Синхронизация: команды под dash")
struct SyncDashTests {
    @Test(
        "тот же сценарий под dash — это /bin/sh на Debian и Ubuntu",
        .enabled(if: FileManager.default.isExecutableFile(atPath: "/bin/dash")))
    func dash() async throws {
        var folder = try Folder()
        folder.shell = "/bin/dash"
        var (a, b) = try await SyncFlowPairing(storage: UUID()).pair(folder)
        b.book.hosts.append(ServerHost(name: "db", address: "10.0.0.2"))
        try await b.sync(folder.remote, at: 4_000)
        try await a.sync(folder.remote, at: 5_000)
        #expect(a.book.hosts.count == 2)
    }
}

@Suite("Синхронизация: несколько хранилищ")
struct SyncManyStoragesTests {
    let first = UUID(), second = UUID()

    /// A и B на двух хранилищах, B пущена.
    private func pair(_ one: Folder, _ two: Folder) async throws -> (Mac, Mac) {
        let both = [first: one.remote, second: two.remote]
        var a = try Mac("a", storages: [first, second])
        a.book.hosts = [ServerHost(name: "web", address: "10.0.0.1")]
        try await a.sync(remotes: both)
        var b = try Mac("b", storages: [first, second])
        #expect(try await b.sync(remotes: both) != nil)
        // Просьба оставлена в обоих хранилищах.
        for folder in [one, two] {
            #expect(try FileManager.default.contentsOfDirectory(atPath: folder.path + "/requests").count == 1)
        }
        try await a.sync(remotes: both)
        try await a.sync(remotes: both, .init(approve: a.requests.map(\.id)), at: 2_000)
        try await b.sync(remotes: both, at: 3_000)
        try await b.sync(remotes: both, .init(trust: try #require(b.signer)), at: 3_000)
        #expect(b.state.isJoined && b.book.hosts.map(\.name) == ["web"])
        return (a, b)
    }

    @Test("сервер лежит — синхронизация идёт через другой, а он догоняет, когда вернётся")
    func oneDown() async throws {
        let one = try Folder(), two = try Folder()
        var (a, b) = try await pair(one, two)
        b.book.hosts.append(ServerHost(name: "db", address: "10.0.0.2"))
        try await b.sync(remotes: [second: two.remote], at: 4_000)
        #expect(b.failures[first] != nil)
        // A видит только второй сервер — и правка уже там.
        try await a.sync(remotes: [second: two.remote], at: 5_000)
        #expect(a.book.hosts.count == 2)
        // Первый вернулся: A дописывает туда то, что он пропустил.
        try await a.sync(remotes: [first: one.remote, second: two.remote], at: 6_000)
        var c = b
        c.book = HostBook()
        c.state.forgetHistory()
        try await c.sync(remotes: [first: one.remote], at: 7_000)
        #expect(c.book.hosts.count == 2)
    }

    @Test("хранилище, пропустившее отзыв, не возвращает отозванную машину")
    func revokeWhileDown() async throws {
        let one = try Folder(), two = try Folder()
        var (a, b) = try await pair(one, two)
        try await a.sync(remotes: [first: one.remote], .init(revoke: [b.state.identity.id]), at: 4_000)
        try await a.sync(remotes: [first: one.remote, second: two.remote], at: 5_000)
        #expect(a.state.machines.count == 1 && a.state.keyGeneration == 1)
        #expect(a.failures.isEmpty)
        await #expect(throws: SyncError.notForThisMachine) {
            try await b.sync(remotes: [first: one.remote, second: two.remote], at: 6_000)
        }
    }

    @Test("добавленное хранилище получает полную копию на следующем круге")
    func addStorage() async throws {
        let one = try Folder(), two = try Folder()
        var a = try Mac("a", storages: [first])
        a.book.hosts = [ServerHost(name: "web", address: "10.0.0.1")]
        try await a.sync(remotes: [first: one.remote])
        a.state.storages.append(second)
        try await a.sync(remotes: [first: one.remote, second: two.remote], at: 2_000)
        #expect(FileManager.default.fileExists(atPath: two.path + "/snapshot.json"))
        var b = try Mac("b", storages: [second])
        #expect(try await b.sync(remotes: [second: two.remote], at: 3_000) != nil)
    }

    @Test("профиль сборки 168 с одним хранилищем читается как список из одного")
    func legacyState() throws {
        var state = SyncState(
            identity: try SyncIdentity.create(name: "a", useEnclave: false), storages: [first])
        state.marks[first] = StorageMark(revision: 7, epoch: 2)
        let modern = try JSONSerialization.jsonObject(with: JSONEncoder().encode(state)) as? [String: Any]
        var legacy = try #require(modern)
        legacy["storages"] = nil
        legacy["marks"] = nil
        legacy["storage"] = first.uuidString
        legacy["lastRevision"] = 7
        legacy["epoch"] = 2
        let decoded = try JSONDecoder().decode(
            SyncState.self, from: JSONSerialization.data(withJSONObject: legacy))
        #expect(decoded.storages == [first])
        #expect(decoded.marks[first] == StorageMark(revision: 7, epoch: 2))
    }
}
