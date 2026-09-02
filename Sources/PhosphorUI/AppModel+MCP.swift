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

    /// Меняет режим доступа и сразу это записывает.
    ///
    /// Смена режима — тоже действие, о котором стоит знать: «когда это стало
    /// полным доступом?» — вопрос, на который журнал обязан отвечать.
    func setMCPMode(_ mode: MCPMode, for host: ServerHost) async {
        await policy.setMode(mode, for: host.id)
        mcpModes[host.id] = mode
        await audit.record(
            AuditEntry(
                tool: "policy", hostName: host.name, arguments: "mode=\(mode.rawValue)",
                decision: "changed", succeeded: true,
                summary: "\(strings("mcp.mode")) \(mode.title)"
            ))
        auditEntries = await audit.entries()
    }
}
