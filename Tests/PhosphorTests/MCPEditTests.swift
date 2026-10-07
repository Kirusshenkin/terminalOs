import Foundation
import Testing

@testable import HostsKit
@testable import MCPBridge
@testable import PetKit
@testable import PhosphorCore
@testable import SSHKit
@testable import SessionKit

@Suite("Ключи через мост: дата добавления")
struct BridgeKeyDateTests {
    private static let keyA =
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAILC2LvfH8cqJFP0LYaIDtuTloX9a85tUuOVqmxjwYHPr fixture-a"
    private static let keyB =
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIKvDq8eXgg2JiQZ8Uy8vnzi8DdfxZP1fl6uMa/7PdCtF fixture-b"
    private static let fingerprintB = "SHA256:ONt2qkakMUEYwh4yGHOJmjJYTkw/3X4IiKYaEcc66tE"

    /// Сервер, на котором `authorized_keys` уже лежит, а запись всегда удаётся.
    private actor KeysTransport: SSHTransport {
        nonisolated let host: ServerHost
        let file: String
        init(host: ServerHost, file: String) {
            self.host = host
            self.file = file
        }
        func run(_ command: String, timeout: Duration) async throws -> CommandResult {
            CommandResult(
                status: 0, stdout: command.hasPrefix("cat ~/.ssh/authorized_keys") ? file : "", stderr: "")
        }
        func stream(_ command: String, onLine: @escaping @Sendable (String) -> Void) async throws {}
        func close() async {}
    }

    private actor Edits {
        var all: [HostEdit] = []
        func remember(_ edit: HostEdit) { all.append(edit) }
    }

    private func call(
        _ arguments: [String: String], file: String
    ) async -> (ToolResult, [HostEdit], ServerHost.ID) {
        let host = ServerHost(name: "prod-01", address: "192.0.2.20")
        let policy = AccessPolicy()
        await policy.setMode(.full, for: host.id)
        let session = HostSession(host: host, transport: KeysTransport(host: host, file: file))
        let edits = Edits()
        let runner = ToolRunner(
            policy: policy,
            audit: AuditLog(
                url: FileManager.default.temporaryDirectory
                    .appendingPathComponent("phosphor-test-\(UUID().uuidString).jsonl")),
            book: { HostBook(hosts: [host]) },
            sessions: { _ in session },
            edit: { await edits.remember($0) },
            confirm: { _, _ in true })
        var all = arguments
        all["host"] = host.id.uuidString
        let result = await runner.call("manage_authorized_key", arguments: all)
        return (result, await edits.all, host.id)
    }

    @Test("ключ, добавленный агентом, получает дату в профиле")
    func addRecordsDate() async {
        let (result, edits, host) = await call(["action": "add", "key": Self.keyB], file: Self.keyA)
        #expect(!result.isError, "\(result.text)")
        guard case .keyAdded(let fingerprint, let id)? = edits.first, edits.count == 1 else {
            Issue.record("дата не дошла до приложения: \(edits)")
            return
        }
        #expect(fingerprint == Self.fingerprintB)
        #expect(id == host)
    }

    @Test("удалённый агентом ключ забывает дату")
    func removeForgetsDate() async {
        let (result, edits, host) = await call(
            ["action": "remove", "fingerprint": Self.fingerprintB], file: Self.keyA + "\n" + Self.keyB)
        #expect(!result.isError, "\(result.text)")
        guard case .keyRemoved(let fingerprint, let id)? = edits.first, edits.count == 1 else {
            Issue.record("удаление не дошло до приложения: \(edits)")
            return
        }
        #expect(fingerprint == Self.fingerprintB)
        #expect(id == host)
    }

    @Test("уже существующий ключ не переписывает дату")
    func existingKeyKeepsDate() async {
        let (_, edits, _) = await call(["action": "add", "key": Self.keyA], file: Self.keyA)
        #expect(edits.isEmpty)
    }
}

@Suite("Питомцы через мост")
struct BridgePetTests {
    private actor Edits {
        var all: [HostEdit] = []
        func remember(_ edit: HostEdit) { all.append(edit) }
    }

    private func runner(
        pets: [PetDefinition] = [], confirmed: Bool = true, edits: Edits
    ) -> ToolRunner {
        ToolRunner(
            policy: AccessPolicy(),
            audit: AuditLog(
                url: FileManager.default.temporaryDirectory
                    .appendingPathComponent("phosphor-test-\(UUID().uuidString).jsonl")),
            book: { HostBook() },
            sessions: { _ in nil },
            edit: { await edits.remember($0) },
            pets: { pets },
            confirm: { _, _ in confirmed })
    }

    private static let pet =
        #"{"format":1,"id":"blob","name":"Blob","states":{"idle":{"frames":[["rb"]]},"#
        + #""walk":{"frames":[["rb"]]},"sleep":{"frames":[["r"]]}}}"#

    @Test("нарисованный агентом питомец добавляется только после согласия человека")
    func addsAfterConfirmation() async {
        let edits = Edits()
        let result = await runner(edits: edits).call("add_pet", arguments: ["pet": Self.pet])
        #expect(!result.isError, "\(result.text)")
        guard case .addPet(let data)? = await edits.all.first else {
            Issue.record("питомец не дошёл до приложения")
            return
        }
        #expect(String(decoding: data, as: UTF8.self) == Self.pet)

        let declined = Edits()
        let refusal = await runner(confirmed: false, edits: declined).call(
            "add_pet", arguments: ["pet": Self.pet])
        #expect(refusal.isError)
        #expect(await declined.all.isEmpty)
    }

    @Test("ошибка в сетке называет кадр — агент может поправить именно его")
    func explainsErrors() async {
        let edits = Edits()
        let broken = Self.pet.replacingOccurrences(of: #"[["rb"]]},"walk""#, with: #"[["rx"]]},"walk""#)
        let result = await runner(edits: edits).call("add_pet", arguments: ["pet": broken])
        #expect(result.isError)
        #expect(result.text.contains("idle 1"))
        #expect(await edits.all.isEmpty)
    }

    @Test("список показывает встроенных и своих; удалить можно только своего")
    func listAndRemove() async throws {
        let blob = try PetFile.decode(Data(Self.pet.utf8))
        let edits = Edits()
        let runner = runner(pets: [blob], edits: edits)
        let list = await runner.call("list_pets", arguments: [:])
        #expect(list.text.contains("cat  (built-in)"))
        #expect(list.text.contains("blob  «Blob»"))
        #expect(await runner.call("remove_pet", arguments: ["pet": "cat"]).isError)
        #expect(await runner.call("add_pet", arguments: ["pet": Self.pet]).text.contains("already exists"))
        let removed = await runner.call("remove_pet", arguments: ["pet": "blob"])
        #expect(!removed.isError)
        guard case .removePet(let id)? = await edits.all.last else {
            Issue.record("удаление не дошло до приложения")
            return
        }
        #expect(id == "blob")
    }
}
