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
}
