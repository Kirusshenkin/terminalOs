public import Foundation
public import HostsKit

/// Что инструмент делает с сервером.
public enum ToolClass: String, Sendable, Equatable {
    /// Только смотрит. Безопасно отдавать без подтверждения.
    case read
    /// Меняет состояние сервера. Требует явного решения человека.
    case write
}

/// Инструмент, который приложение отдаёт наружу.
public struct Tool: Sendable, Equatable, Identifiable {
    public var id: String { name }
    public var name: String
    public var summary: String
    public var kind: ToolClass

    public init(name: String, summary: String, kind: ToolClass) {
        self.name = name
        self.summary = summary
        self.kind = kind
    }
}

/// Полный список того, что вообще может быть вызвано.
///
/// Список закрытый и короткий намеренно: каждый инструмент — это дверь в твою
/// инфраструктуру, и «а давайте ещё вот такой» здесь стоит дороже, чем кажется.
public enum ToolCatalog {
    public static let all: [Tool] = [
        Tool(name: "list_hosts", summary: "servers and connection status", kind: .read),
        Tool(name: "host_metrics", summary: "cores, memory, disk, network, uptime", kind: .read),
        Tool(
            name: "host_report",
            summary: "what is wrong with the host: thresholds applied",
            kind: .read),
        Tool(name: "list_containers", summary: "containers with state and metrics", kind: .read),
        Tool(name: "container_logs", summary: "last log lines", kind: .read),
        Tool(name: "container_inspect", summary: "container details", kind: .read),
        Tool(
            name: "list_authorized_keys",
            summary: "keys on server: fingerprint, algorithm, comment",
            kind: .read),
        Tool(name: "run_command", summary: "run command on host", kind: .write),
        Tool(
            name: "container_action",
            summary: "start / stop / restart / pause / unpause / kill / remove",
            kind: .write),
        Tool(
            name: "manage_authorized_key",
            summary: "add key by line or remove by fingerprint",
            kind: .write),
        Tool(name: "add_host", summary: "add server to list", kind: .write),
        Tool(name: "update_host", summary: "update server in list", kind: .write),
        Tool(name: "remove_host", summary: "remove server from list", kind: .write),
    ]

    public static func tool(named name: String) -> Tool? {
        all.first { $0.name == name }
    }
}
