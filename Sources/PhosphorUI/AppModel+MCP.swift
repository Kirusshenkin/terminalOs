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

    /// Команда, которой мост подключается к Claude Code.
    public var claudeCodeCommand: String {
        ClientRegistration.claudeCodeCommand(shimPath: shimPath)
    }

    func copyClaudeCodeCommand() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(claudeCodeCommand, forType: .string)
    }

    /// Смотрит, подключён ли мост в Claude Code. Файл читается вне главного
    /// потока: он бывает в мегабайты, а страница перерисовывается часто.
    func refreshClaudeCodeRegistration() async {
        let url = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude.json")
        claudeCodeStatus = await Task.detached(priority: .utility) {
            // Нет файла или нет доступа — значит, Claude Code мост не видит;
            // именно это и показывает строка статуса.
            guard let data = try? Data(contentsOf: url) else { return .missing }
            return ClientRegistration.status(inClaudeConfig: data)
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
                summary: "\(strings("mcp.mode")) \(mode.title)"
            ))
        auditEntries = await audit.entries()
    }
}
