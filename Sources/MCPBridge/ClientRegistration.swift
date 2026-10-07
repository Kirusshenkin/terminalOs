public import Foundation

/// Is the bridge registered in Claude Code, and how to register it.
///
/// Only answers "is there an entry named so-and-so": the rest of the config
/// belongs to another program and is never kept, logged or written.
public enum ClientRegistration {
    /// Server name the bridge is registered under.
    public static let serverName = "phosphor"

    /// Command that registers the bridge for every project of this user.
    ///
    /// Without `--scope user` Claude Code files the server under the current
    /// directory only, and in any other folder the bridge silently isn't there.
    public static func claudeCodeCommand(shimPath: String) -> String {
        "claude mcp add --scope user \(serverName) -- '\(shimPath.replacingOccurrences(of: "'", with: #"'\''"#))'"
    }

    /// Where Claude Code sees the bridge.
    public enum Status: Sendable, Equatable {
        /// User scope: every folder.
        case everywhere
        /// Local scope only: the folders it was added from, nowhere else.
        case someFolders
        case missing
    }

    /// Reads `~/.claude.json`: user scope at the top level, local scope under
    /// `projects.<path>.mcpServers`.
    ///
    /// A file that isn't JSON counts as "missing" — that is what the person
    /// needs to know, and the reason why is Claude Code's business.
    public static func status(inClaudeConfig data: Data) -> Status {
        // Not JSON → missing; see above why the reason is dropped.
        guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            return .missing
        }
        if hasServer(root) { return .everywhere }
        let projects = root["projects"] as? [String: Any] ?? [:]
        let local = projects.values.contains { ($0 as? [String: Any]).map(hasServer) ?? false }
        return local ? .someFolders : .missing
    }

    private static func hasServer(_ scope: [String: Any]) -> Bool {
        (scope["mcpServers"] as? [String: Any])?[serverName] != nil
    }

    /// Кодирующий агент, которому можно отдать мост. Каждый хранит свои MCP-серверы
    /// у себя, и приложение их только читает: подключает человек, выполнив
    /// команду или вставив фрагмент.
    public enum Client: String, CaseIterable, Sendable, Identifiable {
        case claudeCode, codex, gemini, cursor

        public var id: String { rawValue }

        public var title: String {
            switch self {
            case .claudeCode: "Claude Code"
            case .codex: "Codex"
            case .gemini: "Gemini CLI"
            case .cursor: "Cursor"
            }
        }

        /// Файл, где агент держит свои серверы, от домашней папки.
        public var configPath: String {
            switch self {
            case .claudeCode: ".claude.json"
            case .codex: ".codex/config.toml"
            case .gemini: ".gemini/settings.json"
            case .cursor: ".cursor/mcp.json"
            }
        }

        /// Подключается ли командой в терминале. Нет — фрагментом в конфиг:
        /// у Cursor команды для этого нет.
        public var isCommand: Bool { self != .cursor }

        /// Что выполнить (или вставить), чтобы агент увидел мост во всех папках.
        public func setup(shimPath: String) -> String {
            let quoted = "'" + shimPath.replacingOccurrences(of: "'", with: #"'\''"#) + "'"
            switch self {
            case .claudeCode:
                return ClientRegistration.claudeCodeCommand(shimPath: shimPath)
            case .codex:
                // Codex держит серверы только в своём общем конфиге — папки ему не нужны.
                return "codex mcp add \(serverName) -- \(quoted)"
            case .gemini:
                // Без `--scope user` Gemini пишет в `.gemini` текущей папки.
                return "gemini mcp add --scope user \(serverName) \(quoted)"
            case .cursor:
                return #"{ "mcpServers": { "\#(serverName)": { "command": \#(jsonString(shimPath)) } } }"#
            }
        }

        /// Где агент видит мост, по содержимому его конфига.
        public func status(inConfig data: Data) -> Status {
            switch self {
            case .claudeCode:
                return ClientRegistration.status(inClaudeConfig: data)
            case .codex:
                return ClientRegistration.hasTOMLServer(String(decoding: data, as: UTF8.self))
                    ? .everywhere : .missing
            case .gemini, .cursor:
                // Не JSON — значит, агент моста не видит; почему — его дело.
                guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
                    return .missing
                }
                return hasServer(root) ? .everywhere : .missing
            }
        }
    }

    /// Есть ли в TOML-конфиге Codex таблица `[mcp_servers.phosphor]`. Полный
    /// разбор TOML ради одного заголовка не нужен: Codex пишет его ровно так,
    /// а руками его иногда берут в кавычки.
    static func hasTOMLServer(_ text: String) -> Bool {
        let headers = ["[mcp_servers.\(serverName)]", "[mcp_servers.\"\(serverName)\"]"]
        return text.split(whereSeparator: \.isNewline).contains { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            return headers.contains { trimmed.hasPrefix($0) }
        }
    }

    /// Строка как JSON-литерал: путь с кавычками или обратной чертой не ломает фрагмент.
    static func jsonString(_ value: String) -> String {
        // Строка всегда кодируется в JSON; на всякий случай — та же строка в кавычках.
        let encoder = JSONEncoder()
        encoder.outputFormatting = .withoutEscapingSlashes
        guard let data = try? encoder.encode(value) else { return "\"\(value)\"" }
        return String(decoding: data, as: UTF8.self)
    }
}
