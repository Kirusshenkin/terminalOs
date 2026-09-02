public import Foundation
public import HostsKit
public import KeysKit

/// Правка списка хостов. Любое изменение сразу планирует запись профиля.
@MainActor
extension AppModel {
    /// Итог импорта: что распознали и что пропустили.
    ///
    /// Пропущенное показывается, а не замалчивается: непонятая директива должна
    /// быть видимой недоработкой, а не тихим сбоем в три часа ночи.
    public struct ImportReport: Sendable {
        public var source: String
        public var added: Int
        public var skipped: [(directive: String, line: Int)]

        public init(source: String, added: Int, skipped: [(directive: String, line: Int)] = []) {
            self.source = source
            self.added = added
            self.skipped = skipped
        }
    }

    /// Единый ключ, по которому хост считается «уже есть»: адрес, юзер и порт.
    /// Импорт из любого источника не задваивает то, что уже в книге.
    private func existingKeys() -> Set<String> {
        Set(book.hosts.map { "\($0.user)@\($0.address):\($0.port)" })
    }

    private func appendNew(_ hosts: [ServerHost], source: String) -> ImportReport {
        let known = existingKeys()
        let fresh = hosts.filter { !known.contains("\($0.user)@\($0.address):\($0.port)") }
        book.hosts.append(contentsOf: fresh)
        if !fresh.isEmpty { scheduleSave() }
        return ImportReport(source: source, added: fresh.count)
    }

    /// Хосты из `~/.ssh/known_hosts` — машины, которым ты уже доверился.
    @discardableResult
    public func importKnownHosts() -> ImportReport {
        let text =
            (try? String(
                contentsOfFile: KnownHostsFile.defaultPath(), encoding: .utf8)) ?? ""
        return appendNew(KnownHostsFile.servers(text), source: "known_hosts")
    }

    /// Адреса из истории подключений Termius. Юзер и порт там были
    /// зашифрованы — их проставит человек; ценно то, что адрес реальный.
    @discardableResult
    public func importTermiusHistory() -> ImportReport {
        // Если рядом лежит расшифрованное хранилище Termius (реальные хосты с
        // именами и юзерами) — берём его; иначе довольствуемся историей IP.
        if let (vault, url) = readTermiusVault() {
            let report = appendNew(vault, source: strings("hosts.termius"))
            // Хосты теперь в шифрованном профиле — плейнтекст-дамп больше не
            // нужен и не должен лежать на диске (см. §8 плана: секреты живут
            // в Keychain и шифрованном профиле, а не в открытом файле).
            try? FileManager.default.removeItem(at: url)
            return report
        }
        let entries = TermiusHistory.scan()
        return appendNew(
            TermiusHistory.hosts(from: entries, existing: book.hosts), source: strings("hosts.termius"))
    }

    /// Хост из расшифрованного дампа Termius.
    private struct TermiusVaultHost: Decodable {
        var name: String
        var address: String
        var port: Int
        var user: String
        var tags: [String]
    }

    /// Читает расшифрованные хосты Termius, если дамп подготовлен рядом с
    /// профилем. Пустой или отсутствующий файл — не ошибка: тогда работает
    /// импорт истории.
    private func readTermiusVault() -> (hosts: [ServerHost], url: URL)? {
        let base = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        guard let url = base?.appendingPathComponent("Phosphor/termius-hosts.json"),
            let data = try? Data(contentsOf: url),
            let decoded = try? JSONDecoder().decode([TermiusVaultHost].self, from: data)
        else { return nil }
        let hosts = decoded.map {
            ServerHost(
                name: $0.name, address: $0.address, port: $0.port,
                user: $0.user, tags: $0.tags)
        }
        return (hosts, url)
    }

    public func addHost(_ host: ServerHost) {
        book.hosts.append(host)
        scheduleSave()
    }

    /// Есть ли уже такой хост в списке — по юзеру, адресу и порту.
    public func isSaved(_ host: ServerHost) -> Bool {
        existingKeys().contains("\(host.user)@\(host.address):\(host.port)")
    }

    /// Сохраняет хост, который предложили запомнить после подключения.
    public func acceptRememberOffer() {
        guard let host = rememberOffer else { return }
        if !isSaved(host) { addHost(host) }
        rememberOffer = nil
    }

    /// Последние серверы, к которым реально подключались, новые сверху и без
    /// повторов. Данные берём из журнала — те самые, что человек вводил.
    public struct RecentTarget: Identifiable, Sendable {
        public var id: String { "\(host.user)@\(host.address):\(host.port)" }
        public var host: ServerHost
        public var time: Date
        public var saved: Bool
    }

    public func recentTargets(limit: Int = 8) -> [RecentTarget] {
        var seen: Set<String> = []
        var result: [RecentTarget] = []
        for event in connectionEvents where event.kind == .connected {
            guard let host = hostFromLogAddress(event.address, name: event.hostName) else { continue }
            let key = "\(host.user)@\(host.address):\(host.port)"
            guard seen.insert(key).inserted else { continue }
            result.append(RecentTarget(host: host, time: event.time, saved: isSaved(host)))
            if result.count >= limit { break }
        }
        return result
    }

    /// Разбирает `user@host:port` из журнала обратно в хост для подстановки.
    private func hostFromLogAddress(_ address: String, name: String) -> ServerHost? {
        guard let at = address.firstIndex(of: "@") else { return nil }
        let user = String(address[..<at])
        let rest = address[address.index(after: at)...]
        let hostPart = rest.split(separator: ":", maxSplits: 1)
        guard let hostname = hostPart.first, !user.isEmpty, !hostname.isEmpty else { return nil }
        let port = hostPart.count > 1 ? Int(hostPart[1]) ?? 22 : 22
        // Если хост сохранён — берём его целиком (с reach, тегами, группой),
        // иначе собираем из того, что записано в журнале.
        if let saved = book.hosts.first(where: {
            $0.user == user && $0.address == hostname && $0.port == port
        }) {
            return saved
        }
        return ServerHost(
            name: name.isEmpty ? String(hostname) : name,
            address: String(hostname), port: port, user: user)
    }

    public func update(_ host: ServerHost) {
        guard let index = book.hosts.firstIndex(where: { $0.id == host.id }) else { return }
        book.hosts[index] = host
        scheduleSave()
    }

    /// Копия хоста рядом: удобно, когда серверы отличаются одной цифрой.
    public func duplicate(_ host: ServerHost) {
        var copy = host
        copy.id = UUID()
        copy.name = host.name + strings("host.copySuffix")
        book.hosts.append(copy)
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

    /// Удаляет группу, не трогая её хосты: они просто остаются без группы.
    ///
    /// Удалять сервер вместе с папкой, в которой он лежал, — не то, чего ждёшь
    /// от удаления папки.
    public func removeGroup(_ group: HostGroup) {
        for index in book.hosts.indices where book.hosts[index].groupID == group.id {
            book.hosts[index].groupID = nil
        }
        book.groups.removeAll { $0.id == group.id }
        if selectedGroup == group.id { selectedGroup = nil }
        scheduleSave()
    }

    public func renameGroup(_ group: HostGroup, to name: String) {
        guard let index = book.groups.firstIndex(where: { $0.id == group.id }) else { return }
        book.groups[index].name = name.trimmingCharacters(in: .whitespaces)
        scheduleSave()
    }

    @discardableResult
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
            return ImportReport(source: "~/.ssh/config", added: 0)
        }
        let parsed = SSHConfigImport.parse(text)
        var report = appendNew(SSHConfigImport.hosts(from: parsed), source: "~/.ssh/config")
        report.skipped = parsed.skipped
        return report
    }
}
