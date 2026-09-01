public import Foundation

/// Reads `~/.ssh/config` once, as an import.
///
/// The file is not consulted at connection time: it is turned into our own
/// hosts, and whatever we could not understand is reported so it shows up as a
/// visible gap rather than a silent failure at 3am.
public enum SSHConfigImport {
    public struct Entry: Equatable, Sendable {
        public var alias: String
        public var hostName: String?
        public var user: String?
        public var port: Int?
        public var identityFile: String?
        public var proxyJump: String?
    }

    public struct Result: Sendable {
        public var entries: [Entry]
        /// Directives we chose not to interpret, with the line they came from.
        public var skipped: [(directive: String, line: Int)]
    }

    private static let understood: Set<String> = [
        "host", "hostname", "user", "port", "identityfile", "proxyjump",
    ]

    /// Parses the subset we support. Wildcards, `Match` and `Include` are
    /// reported as skipped rather than half-guessed.
    public static func parse(_ text: String) -> Result {
        var entries: [Entry] = []
        var skipped: [(String, Int)] = []
        var current: Entry?

        for (index, rawLine) in text.components(separatedBy: .newlines).enumerated() {
            guard let (keyword, value) = directive(in: rawLine) else { continue }

            if keyword == "host" {
                if let entry = current { entries.append(entry) }
                current = startHost(value, line: index + 1, skipped: &skipped)
                continue
            }
            guard understood.contains(keyword) else {
                skipped.append((keyword, index + 1))
                continue
            }
            if current != nil { assign(keyword: keyword, value: value, to: &current) }
        }
        if let entry = current { entries.append(entry) }
        return Result(entries: entries, skipped: skipped.map { (directive: $0.0, line: $0.1) })
    }

    /// Splits a line into keyword and value, ignoring blanks and comments.
    private static func directive(in rawLine: String) -> (String, String)? {
        let line = rawLine.trimmingCharacters(in: .whitespaces)
        guard !line.isEmpty, !line.hasPrefix("#") else { return nil }
        let parts = line.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
        guard parts.count == 2 else { return nil }
        let keyword = parts[0].trimmingCharacters(in: CharacterSet(charactersIn: "=")).lowercased()
        let value = parts[1].trimmingCharacters(in: CharacterSet(charactersIn: " ="))
        return (keyword, value)
    }

    /// A pattern is not a host: importing `*` would create a fiction.
    private static func startHost(
        _ value: String, line: Int, skipped: inout [(String, Int)]
    ) -> Entry? {
        guard !value.contains("*"), !value.contains("?"), !value.contains(" ") else {
            skipped.append(("Host \(value)", line))
            return nil
        }
        return Entry(alias: value)
    }

    private static func assign(keyword: String, value: String, to entry: inout Entry?) {
        switch keyword {
        case "hostname": entry?.hostName = value
        case "user": entry?.user = value
        case "port": entry?.port = Int(value)
        case "identityfile": entry?.identityFile = value
        case "proxyjump": entry?.proxyJump = value
        default: break
        }
    }

    /// Turns parsed entries into hosts, resolving `ProxyJump` between them.
    public static func hosts(from result: Result) -> [ServerHost] {
        var made: [String: ServerHost] = [:]
        for entry in result.entries {
            let host = ServerHost(
                name: entry.alias,
                address: entry.hostName ?? entry.alias,
                port: entry.port ?? 22,
                user: entry.user ?? NSUserName(),
                tags: ["ssh-config"]
            )
            made[entry.alias] = host
        }
        for entry in result.entries {
            guard let jump = entry.proxyJump, var host = made[entry.alias] else { continue }
            let target = jump.contains("@") ? String(jump.split(separator: "@").last ?? "") : jump
            if let bastion = made[target] {
                host.reach = .jump(hostID: bastion.id)
                made[entry.alias] = host
            }
        }
        return result.entries.compactMap { made[$0.alias] }
    }
}
