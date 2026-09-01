import Foundation
import Testing

@testable import HostsKit
@testable import MCPBridge
@testable import PhosphorCore

@Suite("Политика доступа MCP")
struct AccessPolicyTests {
    private let host = UUID()
    private var read: Tool { ToolCatalog.tool(named: "list_containers")! }
    private var write: Tool { ToolCatalog.tool(named: "run_command")! }

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
