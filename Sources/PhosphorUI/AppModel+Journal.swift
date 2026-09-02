public import Foundation
public import HostsKit
public import KeysKit

/// Известные хосты и журнал подключений.
@MainActor
extension AppModel {
    public func loadKnownHosts() {
        let path = KnownHostsFile.defaultPath()
        guard let text = try? String(contentsOfFile: path, encoding: .utf8) else {
            knownHosts = []
            knownHostsError = "файл ~/.ssh/known_hosts не найден — ты ещё никому не доверился"
            return
        }
        knownHosts = KnownHostsFile.parse(text)
        knownHostsError = nil
    }

    /// Забывает запись: следующее подключение спросит доверие заново.
    public func forget(_ entry: KnownHost) {
        let path = KnownHostsFile.defaultPath()
        guard let text = try? String(contentsOfFile: path, encoding: .utf8) else { return }
        let remaining = knownHosts.filter { $0.id != entry.id }
        let rendered = KnownHostsFile.render(remaining, from: text)
        do {
            try rendered.write(toFile: path, atomically: true, encoding: .utf8)
            knownHosts = remaining
            knownHostsError = nil
        } catch {
            knownHostsError = "не удалось записать known_hosts: \(error.localizedDescription)"
        }
    }

    public func loadConnectionLog() async {
        connectionEvents = await connections.readAll()
    }

    func record(_ kind: ConnectionEvent.Kind, host: ServerHost, detail: String? = nil) async {
        await connections.record(
            ConnectionEvent(
                hostName: host.name, address: "\(host.user)@\(host.address):\(host.port)",
                reach: book.reach(for: host).summary, kind: kind, detail: detail
            ))
        connectionEvents = await connections.readAll()
    }
}
