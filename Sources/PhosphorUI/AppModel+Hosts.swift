public import Foundation
public import HostsKit

/// Правка списка хостов. Любое изменение сразу планирует запись профиля.
@MainActor
extension AppModel {
    /// Итог импорта: что распознали и что пропустили.
    ///
    /// Пропущенное показывается, а не замалчивается: непонятая директива должна
    /// быть видимой недоработкой, а не тихим сбоем в три часа ночи.
    public struct ImportReport: Sendable {
        public var added: Int
        public var skipped: [(directive: String, line: Int)]
    }

    public func addHost(_ host: ServerHost) {
        book.hosts.append(host)
        scheduleSave()
    }

    public func update(_ host: ServerHost) {
        guard let index = book.hosts.firstIndex(where: { $0.id == host.id }) else { return }
        book.hosts[index] = host
        scheduleSave()
    }

    public func removeHost(_ id: ServerHost.ID) {
        book.hosts.removeAll { $0.id == id }
        if selectedHost == id {
            selectedHost = nil
            Task { await disconnect() }
        }
        scheduleSave()
    }

    public func addGroup(named name: String) -> HostGroup {
        let group = HostGroup(name: name)
        book.groups.append(group)
        scheduleSave()
        return group
    }

    /// Разбирает строку вида `user@host:port` из строки поиска.
    ///
    /// Подключение без сохранения: набрал — поехал, список хостов не засоряется.
    public func parseQuickConnect(_ text: String) -> ServerHost? {
        let value = text.trimmingCharacters(in: .whitespaces)
        guard value.contains("@") else { return nil }
        let parts = value.split(separator: "@", maxSplits: 1)
        guard parts.count == 2, !parts[0].isEmpty else { return nil }
        let target = parts[1].split(separator: ":", maxSplits: 1)
        guard let address = target.first, !address.isEmpty else { return nil }
        let port = target.count > 1 ? Int(target[1]) ?? 22 : 22
        return ServerHost(
            name: String(parts[1]), address: String(address),
            port: port, user: String(parts[0])
        )
    }

    /// Разовый импорт из `~/.ssh/config`.
    ///
    /// Именно разовый: файл не читается при каждом подключении, потому что мы
    /// понимаем не весь его синтаксис и не хотим тихо ошибиться в рантайме.
    @discardableResult
    public func importSSHConfig(
        from url: URL = URL(fileURLWithPath: NSHomeDirectory() + "/.ssh/config")
    ) -> ImportReport {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else {
            return ImportReport(added: 0, skipped: [])
        }
        let parsed = SSHConfigImport.parse(text)
        let known = Set(book.hosts.map { "\($0.user)@\($0.address):\($0.port)" })
        let fresh = SSHConfigImport.hosts(from: parsed).filter {
            !known.contains("\($0.user)@\($0.address):\($0.port)")
        }
        book.hosts.append(contentsOf: fresh)
        if !fresh.isEmpty { scheduleSave() }
        return ImportReport(added: fresh.count, skipped: parsed.skipped)
    }
}
