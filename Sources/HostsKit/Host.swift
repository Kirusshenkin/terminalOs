public import Foundation
public import PhosphorCore

/// How the app reaches a host. There is no global "VPN on" switch: reachability
/// is a property of the host, visible on its card.
public enum Reach: Codable, Hashable, Sendable {
    /// Straight TCP.
    case direct
    /// Through a local SOCKS5 proxy — V2Box, Xray, anything listening locally.
    case socks(host: String, port: Int)
    /// Through another saved host acting as a bastion.
    case jump(hostID: ServerHost.ID)

    public var summary: String {
        switch self {
        case .direct: "напрямую"
        case .socks(let host, let port): "прокси \(host):\(port)"
        case .jump: "через бастион"
        }
    }
}

/// How strictly the biometric lock applies to a host.
public enum GuardLevel: String, Codable, CaseIterable, Sendable {
    case never  // не спрашивать
    case dangerous  // при опасных действиях
    case always  // при подключении

    public var title: String {
        switch self {
        case .never: "не спрашивать"
        case .dangerous: "при опасных действиях"
        case .always: "при подключении"
        }
    }
}

/// What an MCP client may do with a host. New hosts start disabled on purpose.
public enum MCPMode: String, Codable, CaseIterable, Sendable {
    case disabled
    case readOnly
    case confirm
    case full

    public var title: String {
        switch self {
        case .disabled: "выключено"
        case .readOnly: "только чтение"
        case .confirm: "с подтверждением"
        case .full: "полный"
        }
    }
}

/// A saved server.
public struct ServerHost: Codable, Identifiable, Hashable, Sendable {
    public typealias ID = UUID

    public var id: ID
    public var name: String
    public var address: String
    public var port: Int
    public var user: String
    /// One group at most. The group carries settings; tags do not.
    public var groupID: HostGroup.ID?
    /// Free-form labels used only for search and filtering.
    public var tags: [String]
    public var reach: Reach
    /// Nil means inherit from the group.
    public var guardLevel: GuardLevel?
    public var mcpMode: MCPMode?
    /// Filled in by the capability probe after the first connection.
    public var osName: String?
    public var lastSeen: Date?

    public init(
        id: ID = UUID(),
        name: String,
        address: String,
        port: Int = 22,
        user: String = "root",
        groupID: HostGroup.ID? = nil,
        tags: [String] = [],
        reach: Reach = .direct,
        guardLevel: GuardLevel? = nil,
        mcpMode: MCPMode? = nil,
        osName: String? = nil,
        lastSeen: Date? = nil
    ) {
        self.id = id
        self.name = name
        self.address = address
        self.port = port
        self.user = user
        self.groupID = groupID
        self.tags = tags
        self.reach = reach
        self.guardLevel = guardLevel
        self.mcpMode = mcpMode
        self.osName = osName
        self.lastSeen = lastSeen
    }

    /// Short OS marker for the card, derived from `/etc/os-release`.
    public var osBadge: String {
        guard let osName else { return "SRV" }
        let lower = osName.lowercased()
        if lower.contains("ubuntu") { return "UBU" }
        if lower.contains("debian") { return "DEB" }
        if lower.contains("alpine") { return "ALP" }
        if lower.contains("fedora") || lower.contains("rhel") || lower.contains("centos") { return "RHL" }
        if lower.contains("arch") { return "ARC" }
        return "SRV"
    }
}

/// A group of hosts. The group is where shared settings live: reachability,
/// theme, default key, MCP mode. A host belongs to at most one.
public struct HostGroup: Codable, Identifiable, Hashable, Sendable {
    public typealias ID = UUID

    public var id: ID
    public var name: String
    /// Theme identifier applied to every host in the group. Production in red
    /// so the window you are deleting a container in is unmistakable.
    public var themeID: String?
    public var reach: Reach?
    public var guardLevel: GuardLevel
    public var mcpMode: MCPMode
    /// Recipe offered for freshly provisioned members of this group.
    public var recipeID: String?

    public init(
        id: ID = UUID(),
        name: String,
        themeID: String? = nil,
        reach: Reach? = nil,
        guardLevel: GuardLevel = .dangerous,
        mcpMode: MCPMode = .disabled,
        recipeID: String? = nil
    ) {
        self.id = id
        self.name = name
        self.themeID = themeID
        self.reach = reach
        self.guardLevel = guardLevel
        self.mcpMode = mcpMode
        self.recipeID = recipeID
    }
}
