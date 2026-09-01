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
        Tool(name: "list_hosts", summary: "Серверы и статус подключения", kind: .read),
        Tool(name: "host_metrics", summary: "Ядра, память, диск, сеть, аптайм", kind: .read),
        Tool(name: "list_containers", summary: "Контейнеры с состоянием и метриками", kind: .read),
        Tool(name: "container_logs", summary: "Последние строки логов", kind: .read),
        Tool(name: "container_inspect", summary: "Подробности контейнера", kind: .read),
        Tool(name: "list_authorized_keys", summary: "Ключи на сервере", kind: .read),
        Tool(name: "run_command", summary: "Выполнить команду на хосте", kind: .write),
        Tool(name: "container_action", summary: "start / stop / restart / rm", kind: .write),
        Tool(name: "manage_authorized_key", summary: "Добавить или удалить ключ", kind: .write),
    ]

    public static func tool(named name: String) -> Tool? {
        all.first { $0.name == name }
    }
}
