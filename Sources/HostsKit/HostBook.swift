public import Foundation
public import PhosphorCore

/// The whole address book, as stored inside the encrypted profile.
public struct HostBook: Codable, Sendable {
    public var groups: [HostGroup]
    public var hosts: [ServerHost]
    public var snippets: [Snippet]

    public init(groups: [HostGroup] = [], hosts: [ServerHost] = [], snippets: [Snippet] = []) {
        self.groups = groups
        self.hosts = hosts
        self.snippets = snippets
    }

    public func group(for host: ServerHost) -> HostGroup? {
        guard let id = host.groupID else { return nil }
        return groups.first { $0.id == id }
    }

    /// Effective reachability: the host's own setting wins, then the group's.
    public func reach(for host: ServerHost) -> Reach {
        if case .direct = host.reach, let inherited = group(for: host)?.reach { return inherited }
        return host.reach
    }

    /// Effective lock level, host over group.
    public func guardLevel(for host: ServerHost) -> GuardLevel {
        host.guardLevel ?? group(for: host)?.guardLevel ?? .dangerous
    }

    /// Effective MCP mode, host over group, disabled if neither says otherwise.
    public func mcpMode(for host: ServerHost) -> MCPMode {
        host.mcpMode ?? group(for: host)?.mcpMode ?? .disabled
    }

    /// Filters hosts by a free-text query over name, address, user, tags and
    /// group name, plus an optional group restriction.
    public func search(_ query: String, groupID: HostGroup.ID? = nil) -> [ServerHost] {
        let needle = query.trimmingCharacters(in: .whitespaces).lowercased()
        return hosts.filter { host in
            if let groupID, host.groupID != groupID { return false }
            guard !needle.isEmpty else { return true }
            if host.name.lowercased().contains(needle) { return true }
            if host.address.lowercased().contains(needle) { return true }
            if host.user.lowercased().contains(needle) { return true }
            if host.tags.contains(where: { $0.lowercased().contains(needle) }) { return true }
            if let name = group(for: host)?.name.lowercased(), name.contains(needle) { return true }
            return false
        }
    }

    /// Number of hosts in each group, for the group cards.
    public func counts() -> [HostGroup.ID: Int] {
        var result: [HostGroup.ID: Int] = [:]
        for host in hosts {
            guard let id = host.groupID else { continue }
            result[id, default: 0] += 1
        }
        return result
    }
}

/// A saved command with placeholders such as `{{container}}`.
public struct Snippet: Codable, Identifiable, Hashable, Sendable {
    public var id: UUID
    public var name: String
    public var command: String

    public init(id: UUID = UUID(), name: String, command: String) {
        self.id = id
        self.name = name
        self.command = command
    }

    /// Placeholder names in order of first appearance.
    public var placeholders: [String] {
        var found: [String] = []
        var rest = Substring(command)
        while let open = rest.range(of: "{{"),
            let close = rest.range(of: "}}", range: open.upperBound..<rest.endIndex)
        {
            let name = rest[open.upperBound..<close.lowerBound].trimmingCharacters(in: .whitespaces)
            if !name.isEmpty, !found.contains(name) { found.append(name) }
            rest = rest[close.upperBound...]
        }
        return found
    }

    /// Substitutes values, shell-quoting every one of them.
    ///
    /// Values come from the user and from server output; interpolating them raw
    /// would be a command injection.
    public func expand(_ values: [String: String]) -> String {
        var result = command
        for name in placeholders {
            let replacement = values[name].map(Shell.quote) ?? ""
            result = result.replacingOccurrences(of: "{{\(name)}}", with: replacement)
            result = result.replacingOccurrences(of: "{{ \(name) }}", with: replacement)
        }
        return result
    }
}
