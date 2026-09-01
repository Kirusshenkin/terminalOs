import Foundation
import Testing

@testable import DockerKit
@testable import HostsKit
@testable import MCPBridge
@testable import PhosphorCore
@testable import SessionKit

@Suite("Политика доступа MCP")
struct AccessPolicyTests {
    private let host = UUID()
    private var read: Tool {
        ToolCatalog.tool(named: "list_containers")
            ?? Tool(name: "list_containers", summary: "", kind: .read)
    }

    private var write: Tool {
        ToolCatalog.tool(named: "run_command")
            ?? Tool(name: "run_command", summary: "", kind: .write)
    }

    @Test("новый хост выключен: забыть настроить — не значит открыть")
    func defaultsToDisabled() async {
        let policy = AccessPolicy()
        #expect(await policy.mode(for: host) == .disabled)
        let decision = await policy.decide(tool: read, host: host, command: nil)
        #expect(decision == .deny("для этого хоста MCP выключен"))
    }

    @Test("режим чтения пропускает чтение и отклоняет запись")
    func readOnlySeparatesKinds() async {
        let policy = AccessPolicy()
        await policy.setMode(.readOnly, for: host)
        #expect(await policy.decide(tool: read, host: host, command: nil) == .allow)
        #expect(
            await policy.decide(tool: write, host: host, command: "ls")
                == .deny("хост доступен только для чтения"))
    }

    @Test("в режиме подтверждения запись спрашивает и показывает команду")
    func confirmShowsCommand() async {
        let policy = AccessPolicy()
        await policy.setMode(.confirm, for: host)
        #expect(
            await policy.decide(tool: write, host: host, command: "systemctl restart api")
                == .confirm("systemctl restart api"))
    }

    @Test("запрещённые команды не открывает даже полный режим")
    func denyListBeatsFullAccess() async {
        let policy = AccessPolicy()
        await policy.setMode(.full, for: host)
        for command in [
            "rm -rf /",
            "sudo rm -rf / --no-preserve-root",
            "mkfs.ext4 /dev/sda1",
            "dd if=/dev/zero of=/dev/sda",
            "shutdown -h now",
            ":(){ :|:& };:",
            "chmod -R 777 /",
        ] {
            let decision = await policy.decide(tool: write, host: host, command: command)
            guard case .deny = decision else {
                Issue.record("пропущено: \(command)")
                continue
            }
        }
        // При этом обычная работа не страдает.
        #expect(await policy.decide(tool: write, host: host, command: "rm -rf /srv/app/cache") == .allow)
        #expect(await policy.decide(tool: write, host: host, command: "docker restart api") == .allow)
    }

    @Test("согласие живёт ограниченное время, а не навсегда")
    func grantExpires() async {
        let policy = AccessPolicy()
        await policy.setMode(.confirm, for: host)
        let start = ContinuousClock.now
        await policy.grant(for: host, now: start)

        #expect(
            await policy.decide(tool: write, host: host, command: "ls", now: start + .seconds(60))
                == .allow)
        // После окончания срока — снова вопрос.
        let later = start + .seconds(1000)
        guard case .confirm = await policy.decide(tool: write, host: host, command: "ls", now: later) else {
            Issue.record("по истечении срока должно снова спрашивать")
            return
        }
    }

    @Test("выключение хоста отзывает выданное согласие")
    func disablingRevokes() async {
        let policy = AccessPolicy()
        await policy.setMode(.confirm, for: host)
        await policy.grant(for: host)
        await policy.setMode(.disabled, for: host)
        await policy.setMode(.confirm, for: host)
        guard case .confirm = await policy.decide(tool: write, host: host, command: "ls") else {
            Issue.record("после выключения согласие должно исчезнуть")
            return
        }
    }

    @Test("шквал пишущих вызовов упирается в ограничение частоты")
    func rateLimited() async {
        let policy = AccessPolicy()
        await policy.setMode(.full, for: host)
        let now = ContinuousClock.now
        for _ in 0..<20 { await policy.recordWrite(now: now) }
        #expect(
            await policy.decide(tool: write, host: host, command: "ls", now: now)
                == .deny("слишком много пишущих вызовов подряд"))
        // Через окно счётчик отпускает.
        #expect(
            await policy.decide(tool: write, host: host, command: "ls", now: now + .seconds(120))
                == .allow)
    }
}

@Suite("Журнал действий ИИ")
struct AuditLogTests {
    private func temporaryURL() -> URL {
        URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("phosphor-\(UUID().uuidString)/audit.jsonl")
    }

    private func entry(_ tool: String, succeeded: Bool = true) -> AuditEntry {
        AuditEntry(
            tool: tool, hostName: "prod-01", arguments: "{}",
            decision: "allow", succeeded: succeeded, summary: "готово"
        )
    }

    @Test("записи только дозаписываются: подчистить след нечем")
    func appendsOnly() async throws {
        let url = temporaryURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        let log = AuditLog(url: url)
        await log.record(entry("run_command"))
        await log.record(entry("container_action"))
        await log.close()

        // Второй журнал по тому же пути обязан дописать, а не начать заново.
        let again = AuditLog(url: url)
        await again.record(entry("list_hosts"))
        await again.close()

        let all = await AuditLog(url: url).readAll()
        #expect(all.count == 3)
        #expect(all.map(\.tool) == ["run_command", "container_action", "list_hosts"])
    }

    @Test("файл доступен только владельцу")
    func filePermissions() async throws {
        let url = temporaryURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let log = AuditLog(url: url)
        await log.record(entry("run_command"))
        await log.close()

        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        #expect((attributes[.posixPermissions] as? NSNumber)?.int16Value == 0o600)
    }

    @Test("испорченная строка не прячет остальные записи")
    func survivesCorruptLine() async throws {
        let url = temporaryURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let log = AuditLog(url: url)
        await log.record(entry("run_command"))
        await log.close()

        var text = try String(contentsOf: url, encoding: .utf8)
        text += "{ это не запись\n"
        try text.write(to: url, atomically: true, encoding: .utf8)

        let all = await AuditLog(url: url).readAll()
        #expect(all.count == 1)
    }

    @Test("недавние записи держатся в памяти для экрана активности")
    func keepsRecent() async {
        let url = temporaryURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let log = AuditLog(url: url)
        for index in 0..<5 { await log.record(entry("tool\(index)")) }
        #expect(await log.entries().count == 5)
        await log.close()
    }
}

@Suite("Исполнитель инструментов MCP")
struct ToolRunnerTests {
    private func temporaryURL() -> URL {
        URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("phosphor-\(UUID().uuidString)/audit.jsonl")
    }

    /// Собирает исполнителя с одним хостом и заданным режимом.
    /// Собранное окружение для одного теста.
    private struct Setup {
        var runner: ToolRunner
        var host: ServerHost
        var policy: AccessPolicy
        var audit: AuditLog
    }

    private func makeRunner(
        mode: MCPMode,
        confirmAnswer: Bool = true,
        auditURL: URL
    ) async -> Setup {
        let host = ServerHost(name: "prod-01", address: "10.0.0.1")
        let book = HostBook(hosts: [host])
        let policy = AccessPolicy()
        await policy.setMode(mode, for: host.id)
        let audit = AuditLog(url: auditURL)
        let runner = ToolRunner(
            policy: policy, audit: audit,
            book: { book },
            sessions: { _ in nil },  // подключения нет: проверяем решения, не выполнение
            confirm: { _, _ in confirmAnswer }
        )
        return Setup(runner: runner, host: host, policy: policy, audit: audit)
    }

    @Test("список хостов доступен без привязки к хосту")
    func listsHosts() async throws {
        let url = temporaryURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let setup = await makeRunner(mode: .disabled, auditURL: url)
        let result = await setup.runner.call("list_hosts", arguments: [:])
        #expect(!result.isError)
        #expect(result.text.contains("prod-01"))
        await setup.audit.close()
    }

    @Test("выключенный хост отклоняет даже чтение")
    func disabledDeniesEverything() async throws {
        let url = temporaryURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let setup = await makeRunner(mode: .disabled, auditURL: url)
        let result = await setup.runner.call(
            "list_containers", arguments: ["host": setup.host.id.uuidString])
        #expect(result.isError)
        #expect(result.text.contains("выключен"))
        await setup.audit.close()
    }

    @Test("отказ человека останавливает запись")
    func refusalStops() async throws {
        let url = temporaryURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let setup = await makeRunner(mode: .confirm, confirmAnswer: false, auditURL: url)
        let result = await setup.runner.call(
            "run_command",
            arguments: [
                "host": setup.host.id.uuidString, "command": "systemctl restart api",
            ])
        #expect(result.isError)
        #expect(result.text.contains("отклонил"))
        await setup.audit.close()

        // Отказ тоже попадает в журнал: он часть истории.
        let entries = await AuditLog(url: url).readAll()
        #expect(entries.contains { $0.decision == "refused" })
    }

    @Test("сухой прогон рассказывает намерение и ничего не делает")
    func dryRunDescribes() async throws {
        let url = temporaryURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let setup = await makeRunner(mode: .full, auditURL: url)
        let result = await setup.runner.call(
            "run_command",
            arguments: ["host": setup.host.id.uuidString, "command": "rm -rf /srv/old"],
            mode: .dryRun
        )
        #expect(!result.isError)
        #expect(result.text.contains("выполнил бы"))
        #expect(result.text.contains("/srv/old"))
        await setup.audit.close()

        let entries = await AuditLog(url: url).readAll()
        #expect(entries.last?.decision == "dry-run")
    }

    @Test("запрещённая команда не проходит даже в полном режиме")
    func denyListStillApplies() async throws {
        let url = temporaryURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let setup = await makeRunner(mode: .full, auditURL: url)
        let result = await setup.runner.call(
            "run_command",
            arguments: [
                "host": setup.host.id.uuidString, "command": "rm -rf /",
            ])
        #expect(result.isError)
        #expect(result.text.contains("запрещена"))
        await setup.audit.close()
    }

    @Test("каждый вызов оставляет запись в журнале")
    func everythingIsLogged() async throws {
        let url = temporaryURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let setup = await makeRunner(mode: .readOnly, auditURL: url)
        _ = await setup.runner.call("list_hosts", arguments: [:])
        _ = await setup.runner.call(
            "list_containers", arguments: ["host": setup.host.id.uuidString])
        _ = await setup.runner.call(
            "run_command",
            arguments: [
                "host": setup.host.id.uuidString, "command": "ls",
            ])
        await setup.audit.close()

        let entries = await AuditLog(url: url).readAll()
        #expect(entries.count == 3)
        #expect(entries.map(\.tool) == ["list_hosts", "list_containers", "run_command"])
    }

    @Test("секреты в аргументах не попадают в журнал")
    func secretsAreMaskedInAudit() async throws {
        let url = temporaryURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let setup = await makeRunner(mode: .readOnly, auditURL: url)
        _ = await setup.runner.call(
            "list_containers",
            arguments: [
                "host": setup.host.id.uuidString, "api_key": "sk-live-4471",
            ])
        await setup.audit.close()

        let entries = await AuditLog(url: url).readAll()
        let arguments = entries.last?.arguments ?? ""
        #expect(!arguments.contains("sk-live-4471"))
        #expect(arguments.contains(Redaction.mask))
    }

    @Test("неизвестный инструмент отвергается, а не угадывается")
    func unknownToolRefused() async throws {
        let url = temporaryURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let setup = await makeRunner(mode: .full, auditURL: url)
        let result = await setup.runner.call("delete_everything", arguments: [:])
        #expect(result.isError)
        await setup.audit.close()
    }
}
