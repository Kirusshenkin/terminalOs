import AppKit
import Foundation
public import HostsKit
public import MCPBridge

/// Доступ ИИ к хостам и журнал его действий.
@MainActor
extension AppModel {
    /// Читает журнал с диска: он переживает перезапуск, в отличие от памяти.
    func loadAudit() async {
        auditEntries = await audit.readAll()
    }

    /// Отдаёт политике режимы из профиля: свой у хоста, иначе от группы.
    ///
    /// Вызывается сразу после чтения профиля, а не при открытии страницы
    /// доступа: мост принимает запросы с запуска, и до этого момента все
    /// хосты выглядели бы выключенными.
    func syncMCPModesFromBook() async {
        for host in book.hosts {
            let mode = book.mcpMode(for: host)
            await policy.setMode(mode, for: host.id)
            mcpModes[host.id] = mode
        }
    }

    /// Путь к мосту внутри установленного приложения.
    var shimPath: String {
        Bundle.main.bundleURL.appendingPathComponent("Contents/MacOS/phosphor-mcp").path
    }

    /// Команда (или фрагмент конфига), которой мост подключается к агенту.
    public func clientSetup(_ client: ClientRegistration.Client) -> String {
        client.setup(shimPath: shimPath)
    }

    func copyClientSetup(_ client: ClientRegistration.Client) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(clientSetup(client), forType: .string)
    }

    /// Смотрит, какие агенты видят мост. Файлы читаются вне главного потока:
    /// `.claude.json` бывает в мегабайты, а страница перерисовывается часто.
    func refreshClientRegistrations() async {
        let home = FileManager.default.homeDirectoryForCurrentUser
        clientStatus = await Task.detached(priority: .utility) {
            var result: [ClientRegistration.Client: ClientRegistration.Status] = [:]
            for client in ClientRegistration.Client.allCases {
                // Нет файла или нет доступа — значит, агент мост не видит;
                // именно это и показывает строка статуса.
                let data = try? Data(contentsOf: home.appendingPathComponent(client.configPath))
                result[client] = data.map(client.status(inConfig:)) ?? .missing
            }
            return result
        }.value
    }

    /// Меняет режим доступа и сразу это записывает.
    ///
    /// Смена режима — тоже действие, о котором стоит знать: «когда это стало
    /// полным доступом?» — вопрос, на который журнал обязан отвечать.
    func setMCPMode(_ mode: MCPMode, for host: ServerHost) async {
        await policy.setMode(mode, for: host.id)
        mcpModes[host.id] = mode

        // Режим живёт в профиле, иначе перезапуск молча выключает доступ (#3).
        // Неудачная запись видна на плашке saveError — результат тут не нужен.
        if let index = book.hosts.firstIndex(where: { $0.id == host.id }) {
            book.hosts[index].mcpMode = mode
            _ = await saveNow()
        }

        await audit.record(
            AuditEntry(
                tool: "policy", hostName: host.name, arguments: "mode=\(mode.rawValue)",
                decision: "changed", succeeded: true,
                summary: "\(strings("mcp.mode")) \(strings.mcpMode(mode))"
            ))
        auditEntries = await audit.entries()
    }
}
