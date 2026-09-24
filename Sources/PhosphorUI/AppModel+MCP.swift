public import AppKit
public import Foundation
public import HostsKit
public import MCPBridge

/// Доступ ИИ к хостам и журнал его действий.
@MainActor
extension AppModel {
    /// Читает журнал с диска: он переживает перезапуск, в отличие от памяти.
    func loadAudit() async {
        auditEntries = await audit.readAll()
        for host in book.hosts {
            mcpModes[host.id] = await policy.mode(for: host.id)
        }
    }

    /// Проверяет, зарегистрирован ли Phosphor в ~/.claude.json.
    ///
    /// Читает только наличие записи, никогда не пишет конфиг.
    func isPhosphorRegistered() -> Bool {
        let claudeJsonURL = FileManager.default
            .homeDirectoryForCurrentUser
            .appendingPathComponent(".claude.json")

        guard FileManager.default.fileExists(atPath: claudeJsonURL.path) else {
            return false
        }

        do {
            let data = try Data(contentsOf: claudeJsonURL)
            if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
               let servers = json["mcpServers"] as? [String: Any],
               servers["phosphor"] != nil {
                return true
            }
        } catch {
            // Если файл не читается, считаем что нет подключения
            return false
        }

        return false
    }

    /// Копирует команду регистрации в буфер обмена.
    func copyBridgeCommand() {
        let shimPath = Bundle.main.bundleURL
            .appendingPathComponent("Contents/MacOS/phosphor-mcp").path
        let command = "claude mcp add phosphor \(shimPath)"

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(command, forType: .string)
    }

    /// Команда для регистрации в Claude Code (вместо JSON конфига).
    public var bridgeCliCommand: String {
        let shimPath = Bundle.main.bundleURL
            .appendingPathComponent("Contents/MacOS/phosphor-mcp").path
        return "claude mcp add phosphor \(shimPath)"
    }

    /// Меняет режим доступа и сразу это записывает.
    ///
    /// Смена режима — тоже действие, о котором стоит знать: «когда это стало
    /// полным доступом?» — вопрос, на который журнал обязан отвечать.
    func setMCPMode(_ mode: MCPMode, for host: ServerHost) async {
        await policy.setMode(mode, for: host.id)
        mcpModes[host.id] = mode

        // Сохраняем режим в профиле, чтобы он пережил перезапуск.
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
