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

    init() throws {
        home = NSTemporaryDirectory() + "phosphor-sync-\(UUID().uuidString)"
        try FileManager.default.createDirectory(atPath: home, withIntermediateDirectories: true)
    }

    var remote: SyncRemote {
        let home = home
        return SyncRemote { command, input in
            try await Subprocess.run(
                executable: "/bin/sh", arguments: ["-c", "HOME=\(Shell.quote(home)); \(command)"],
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

    init(_ name: String, storage: UUID) throws {
        state = SyncState(identity: try SyncIdentity.create(name: name, useEnclave: false), storage: storage)
    }

    /// Один круг, как его делает приложение: записи из профиля, слияние,
    /// результат обратно в профиль. Возвращает код, если машину ещё не пустили.
    @discardableResult
    mutating func sync(
        _ remote: SyncRemote, _ changes: SyncEngine.Changes = .init(), at now: Int64 = 1_000
    )
        async throws -> String?
    {
        switch try await SyncEngine.run(
            items: book.syncItems(), state: state, remote: remote, changes: changes, now: { now })
        {
        case .awaitingApproval(let next, let code):
            state = next
            return code
        case .synced(let records, let next, let waiting):
            state = next
            book.applySync(records)
            state.rebase(book.syncItems(), merged: records)
            requests = waiting
            return nil
        }
    }
}

@Suite("Синхронизация: две машины через папку на сервере")
struct SyncFlowTests {
    let storage = UUID()

    /// A заводит хранилище, B просится, A пускает по совпавшему коду.
    private func pair(_ folder: Folder) async throws -> (Mac, Mac) {
        var a = try Mac("a", storage: storage)
        a.book.hosts = [ServerHost(name: "web", address: "10.0.0.1")]
        try await a.sync(folder.remote)
        var b = try Mac("b", storage: storage)
        let code = try await b.sync(folder.remote)
        #expect(code != nil)
        try await a.sync(folder.remote)
        #expect(a.requests.map(\.code) == [code])
        try await a.sync(folder.remote, .init(approve: a.requests.map(\.id)), at: 2_000)
        #expect(try await b.sync(folder.remote, at: 3_000) == nil)
        return (a, b)
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
        let revision = a.state.lastRevision
        a.book.remember(a.book.hosts[0].id, osName: "Ubuntu 24.04")
        try await a.sync(folder.remote, at: 4_000)
        #expect(a.state.lastRevision == revision)
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
