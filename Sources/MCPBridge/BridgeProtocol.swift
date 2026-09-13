public import DockerKit
public import Foundation

/// Что шим просит у приложения.
public struct BridgeRequest: Codable, Sendable {
    /// Одноразовый пароль сокета: без него запрос не рассматривается.
    public var token: String
    public var method: String
    public var tool: String?
    public var arguments: [String: String]?
    public var dryRun: Bool?

    public init(
        token: String, method: String, tool: String? = nil,
        arguments: [String: String]? = nil, dryRun: Bool? = nil
    ) {
        self.token = token
        self.method = method
        self.tool = tool
        self.arguments = arguments
        self.dryRun = dryRun
    }
}

/// Что приложение отвечает.
public struct BridgeResponse: Codable, Sendable {
    public var ok: Bool
    public var text: String
    public var tools: [ToolDescription]?

    public init(ok: Bool, text: String, tools: [ToolDescription]? = nil) {
        self.ok = ok
        self.text = text
        self.tools = tools
    }
}

/// Аргумент инструмента в том виде, в каком его ждёт MCP-клиент.
///
/// Имя здесь — то же самое, которое читает `ToolRunner`. Разъезд между этими
/// двумя списками не ломает сборку и не виден в тестах на политику: он виден
/// только тогда, когда модель вызывает инструмент и получает «не указан
/// аргумент» на аргумент, который она добросовестно передала.
public struct ToolArgument: Codable, Sendable, Equatable {
    public var name: String
    public var hint: String
    /// Без него вызов заведомо не выполнится.
    public var isRequired: Bool

    public init(name: String, hint: String, isRequired: Bool = false) {
        self.name = name
        self.hint = hint
        self.isRequired = isRequired
    }
}

/// Инструмент в том виде, в каком его ждёт MCP-клиент.
public struct ToolDescription: Codable, Sendable {
    public var name: String
    public var description: String
    /// Аргументы с подсказками: схему шим соберёт сам.
    public var arguments: [ToolArgument]

    public init(name: String, description: String, arguments: [ToolArgument]) {
        self.name = name
        self.description = description
        self.arguments = arguments
    }

    /// Только имена — для проверок и журналов.
    public var argumentNames: [String] { arguments.map(\.name) }
}

/// Где живёт сокет и как выглядит файл с паролем.
///
/// Сокет и токен лежат рядом с профилем, оба с правами 0600: любой процесс на
/// машине, дотянувшийся до сокета, получил бы доступ к твоим серверам.
public enum BridgeLocation {
    public static func directory() -> URL {
        let base =
            FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first ?? URL(fileURLWithPath: NSHomeDirectory())
        return base.appendingPathComponent("Phosphor")
    }

    public static func socketPath() -> String {
        directory().appendingPathComponent("mcp.sock").path
    }

    public static func tokenPath() -> String {
        directory().appendingPathComponent("mcp.token").path
    }

    /// Описания инструментов для клиента.
    public static func descriptions() -> [ToolDescription] {
        ToolCatalog.all.map { tool in
            ToolDescription(
                name: tool.name,
                description: tool.summary + (tool.kind == .write ? " (изменяет сервер)" : ""),
                arguments: arguments(for: tool.name)
            )
        }
    }

    /// Аргументы инструмента. Имена совпадают с теми, что читает `ToolRunner`,
    /// а подсказка зависит от инструмента: `action` у контейнера и `action` у
    /// ключа — это разные наборы слов, и общая подсказка врала бы одному из них.
    static func arguments(for tool: String) -> [ToolArgument] {
        serverArguments(for: tool) ?? bookArguments(for: tool)
    }

    /// Хост и то, что делается на нём.
    private static func serverArguments(for tool: String) -> [ToolArgument]? {
        let container = ToolArgument(
            name: "container", hint: "имя или идентификатор контейнера", isRequired: true)
        switch tool {
        case "run_command":
            return [
                host,
                ToolArgument(
                    name: "command", hint: "команда для выполнения на сервере", isRequired: true),
            ]
        case "container_logs":
            return [
                host, container,
                ToolArgument(name: "tail", hint: "сколько последних строк вернуть, до 1000"),
            ]
        case "container_inspect":
            return [host, container]
        case "container_action":
            return [
                host, container,
                ToolArgument(
                    name: "action",
                    hint: ContainerAction.allCases.map(\.rawValue).joined(separator: ", "),
                    isRequired: true),
            ]
        case "manage_authorized_key":
            return [
                host,
                ToolArgument(name: "action", hint: "add или remove", isRequired: true),
                ToolArgument(
                    name: "key", hint: "строка ключа в формате authorized_keys, для add"),
                ToolArgument(
                    name: "fingerprint",
                    hint: "отпечаток SHA256:… из list_authorized_keys, для remove"),
            ]
        default:
            return nil
        }
    }

    /// Правка собственного списка серверов — на сервер ничего не уходит.
    private static func bookArguments(for tool: String) -> [ToolArgument] {
        let fields = [
            ToolArgument(name: "name", hint: "как назвать сервер в списке"),
            ToolArgument(name: "address", hint: "адрес или имя сервера"),
            ToolArgument(name: "user", hint: "логин, по умолчанию root"),
            ToolArgument(name: "port", hint: "порт, по умолчанию 22"),
            ToolArgument(name: "tags", hint: "метки через запятую"),
        ]
        switch tool {
        case "list_hosts":
            return []
        case "add_host":
            return fields.map {
                $0.name == "address"
                    ? ToolArgument(name: $0.name, hint: $0.hint, isRequired: true) : $0
            }
        case "update_host":
            return [host] + fields
        default:
            // Остальное — чтение состояния хоста: кроме самого хоста, ничего.
            return [host]
        }
    }

    private static let host = ToolArgument(
        name: "host", hint: "идентификатор хоста из list_hosts", isRequired: true)
}
