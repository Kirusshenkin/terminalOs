public import DockerKit
public import Foundation
public import HostsKit
public import MetricsKit
public import PhosphorCore
public import ProvisionKit
public import SSHKit
public import ThemeKit

/// Which screen the window is showing.
public enum Screen2: String, CaseIterable, Sendable {
    case hosts, terminal, docker, monitor, keys, theme
}

/// Кто живёт в углу.
public enum Pet: String, CaseIterable, Sendable {
    case cat, glider
    public var title: String {
        switch self {
        case .cat: "CAT"
        case .glider: "GLIDER"
        }
    }
}

/// Строка скроллбэка.
public struct TerminalLine: Sendable, Identifiable {
    public var id: Int
    public var text: String
    public var kind: Kind
    public enum Kind: Sendable { case prompt, output, warning, error }
}

/// Application state.
///
/// Lives on the main actor because every field feeds a view; everything that
/// touches the network happens in the actors under `SSHKit` and arrives here as
/// finished values.
@MainActor
@Observable
public final class AppModel {
    public var isUnlocked = false
    public var screen: Screen2 = .hosts
    public var language: Language = .system
    public var themeID = BuiltInThemes.phosphor.id
    public var eggs = EasterEggs()
    public var pet: Pet = .cat

    public var book = HostBook()
    public var selectedGroup: HostGroup.ID?
    public var query = ""
    public var selectedHost: ServerHost.ID?

    public var containers: [Container] = []
    public var selectedContainer: String?
    public var snapshots = RingBuffer<Snapshot>(capacity: 1_800)
    public var profile: HostProfile?
    public var provisionOffer: HostProfile?

    /// Terminal scrollback, bounded on purpose.
    public var scrollback = RingBuffer<TerminalLine>(capacity: 50_000)

    public var strings: Strings { Strings(language: language) }

    /// Theme for the current context: a host's group can override the default,
    /// which is how production ends up unmistakably red.
    public var style: Style {
        var id = themeID
        if let hostID = selectedHost,
            let host = book.hosts.first(where: { $0.id == hostID }),
            let groupTheme = book.group(for: host)?.themeID
        {
            id = groupTheme
        }
        return Style(theme: BuiltInThemes.theme(id: id))
    }

    public var visibleHosts: [ServerHost] {
        book.search(query, groupID: selectedGroup)
    }

    public init() {}

    /// Sample content so the window is not empty before a real connection.
    public func loadDemoData() {
        let prod = HostGroup(name: "prod", themeID: "ruby", guardLevel: .always, mcpMode: .readOnly)
        let web = HostGroup(name: "web", themeID: "ice")
        let lab = HostGroup(name: "lab")
        book.groups = [prod, web, lab]
        book.hosts = [
            ServerHost(
                name: "app-1", address: "192.0.2.11", groupID: prod.id, tags: ["ssh", "app"], osName: "ubuntu"
            ),
            ServerHost(
                name: "worker-1", address: "192.0.2.12", groupID: prod.id, tags: ["ssh", "worker"],
                osName: "ubuntu"),
            ServerHost(
                name: "worker-2", address: "192.0.2.13", groupID: prod.id, tags: ["ssh", "worker"],
                osName: "ubuntu"),
            ServerHost(
                name: "lobby", address: "198.51.100.2", groupID: web.id, tags: ["ssh", "lobby"],
                osName: "debian"),
            ServerHost(
                name: "web.dev", address: "198.51.100.3", groupID: web.id, tags: ["ssh", "dev"],
                osName: "debian"),
            ServerHost(
                name: "sandbox", address: "203.0.113.5", groupID: lab.id, tags: ["ssh", "lab"],
                osName: "debian"),
            ServerHost(name: "203.0.113.9", address: "203.0.113.9", tags: ["ssh", "root"]),
        ]
        book.snippets = [
            Snippet(name: "логи контейнера", command: "docker logs --tail 200 {{container}}"),
            Snippet(name: "перезапуск стека", command: "cd {{path}} && docker compose restart"),
        ]
        containers = [
            Container(
                id: "3f9a2c7e11b0", name: "api-gateway", image: "api:2.14", state: .running,
                status: "Up 6 days", ports: "127.0.0.1:8080->8080", project: "prod", health: "healthy"),
            Container(
                id: "9b1e0d4a22c1", name: "postgres-main", image: "pg:16", state: .running,
                status: "Up 41 days", ports: "", project: "prod", health: "healthy"),
            Container(
                id: "77aa31ff90de", name: "worker-billing", image: "wrk:2.1", state: .running,
                status: "Up 2 hours (unhealthy)", ports: "", project: "prod", health: "unhealthy"),
            Container(
                id: "1c0de55ab332", name: "migrator", image: "api:2.14", state: .exited,
                status: "Exited (0) 6 days ago", ports: "", project: "prod", health: nil),
        ]
        selectedContainer = containers.first?.id
        for (index, line) in Self.demoScrollback.enumerated() {
            scrollback.append(TerminalLine(id: index, text: line.0, kind: line.1))
        }
    }

    private static let demoScrollback: [(String, TerminalLine.Kind)] = [
        ("root@app-1:~# docker compose ps", .prompt),
        ("NAME              IMAGE        STATUS", .output),
        ("api-gateway       api:2.14     Up 6 days", .output),
        ("postgres-main     pg:16        Up 41 days", .output),
        ("worker-billing    wrk:2.1      Up 2 hours (unhealthy)", .warning),
        ("migrator          api:2.14     Exited (0) 6 days ago", .warning),
        ("", .output),
        ("root@app-1:~# journalctl -u api --since '10 min ago' | tail -3", .prompt),
        ("11:41:08 api[912]  GET /v2/session 200 14ms", .output),
        ("11:41:09 api[912]  POST /v2/pay 201 62ms", .output),
        ("11:41:12 api[912]  WARN retry upstream billing", .warning),
    ]
}
