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

/// Инструмент в том виде, в каком его ждёт MCP-клиент.
public struct ToolDescription: Codable, Sendable {
    public var name: String
    public var description: String
    /// Имена аргументов: схему шим соберёт сам.
    public var arguments: [String]

    public init(name: String, description: String, arguments: [String]) {
        self.name = name
        self.description = description
        self.arguments = arguments
    }
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
                arguments: argumentNames(for: tool.name)
            )
        }
    }

    static func argumentNames(for tool: String) -> [String] {
        switch tool {
        case "list_hosts": []
        case "run_command": ["host", "command"]
        case "container_logs": ["host", "container", "tail"]
        case "container_inspect": ["host", "container"]
        case "container_action": ["host", "container", "action"]
        case "manage_authorized_key": ["host", "operation", "key"]
        case "add_host": ["name", "address", "user", "port", "tags"]
        case "update_host": ["host", "name", "address", "user", "port", "tags"]
        case "remove_host": ["host"]
        default: ["host"]
        }
    }
}
