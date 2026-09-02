public import Foundation
public import HostsKit
public import SSHKit
public import SessionKit

/// Пробросы портов: список живёт в профиле, состояние — в соединении.
@MainActor
extension AppModel {
    /// Переносит пробросы из профиля в рабочий вид и обратно.
    func syncForwardsFromBook() {
        forwards = book.forwards.map {
            PortForward(
                id: $0.id,
                direction: PortForward.Direction(rawValue: $0.direction) ?? .local,
                listenPort: $0.listenPort, targetHost: $0.targetHost,
                targetPort: $0.targetPort, hostID: $0.hostID, autoStart: $0.autoStart
            )
        }
    }

    private func syncForwardsToBook() {
        book.forwards = forwards.map {
            ForwardSpec(
                id: $0.id, direction: $0.direction.rawValue, listenPort: $0.listenPort,
                targetHost: $0.targetHost, targetPort: $0.targetPort,
                hostID: $0.hostID, autoStart: $0.autoStart
            )
        }
    }

    public func addForward(
        direction: PortForward.Direction, listenPort: Int, targetHost: String, targetPort: Int
    ) {
        guard let hostID = selectedHost else { return }
        forwards.append(
            PortForward(
                direction: direction, listenPort: listenPort,
                targetHost: targetHost.trimmingCharacters(in: .whitespaces),
                targetPort: targetPort, hostID: hostID
            ))
        syncForwardsToBook()
        scheduleSave()
    }

    public func removeForward(_ forward: PortForward) {
        Task { await stopForward(forward) }
        forwards.removeAll { $0.id == forward.id }
        syncForwardsToBook()
        scheduleSave()
    }

    public func setAutoStart(_ value: Bool, for forward: PortForward) {
        guard let index = forwards.firstIndex(where: { $0.id == forward.id }) else { return }
        forwards[index].autoStart = value
        syncForwardsToBook()
        scheduleSave()
    }

    public func toggleForward(_ forward: PortForward) async {
        if activeForwards.contains(forward.id) {
            await stopForward(forward)
        } else {
            await startForward(forward)
        }
    }

    func startForward(_ forward: PortForward) async {
        guard let manager = forwardManager() else {
            forwardError = "нет живого соединения с хостом — подключись сначала"
            return
        }
        do {
            try await manager.start(forward)
            activeForwards.insert(forward.id)
            forwardError = nil
        } catch TransportError.commandFailed(_, let reason) {
            forwardError = reason
        } catch {
            forwardError = "\(error)"
        }
    }

    func stopForward(_ forward: PortForward) async {
        guard let manager = forwardManager() else { return }
        try? await manager.stop(forward)
        activeForwards.remove(forward.id)
    }

    /// Поднимает всё, что помечено «при подключении».
    func startAutoForwards() async {
        for forward in forwards where forward.autoStart && forward.hostID == selectedHost {
            await startForward(forward)
        }
    }

    private func forwardManager() -> ForwardManager? {
        guard let host = book.hosts.first(where: { $0.id == selectedHost }),
            let socket = sessionSocketPath
        else { return nil }
        return ForwardManager(host: host, reach: book.reach(for: host), controlPath: socket)
    }
}
