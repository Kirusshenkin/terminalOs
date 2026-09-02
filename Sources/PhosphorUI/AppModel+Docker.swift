public import DockerKit
public import HostsKit
public import KeysKit
public import PhosphorCore
public import ProvisionKit
public import SSHKit
public import SessionKit

/// Действия над контейнерами и их логи.
@MainActor
extension AppModel {
    /// Запускает действие: разрушающие — только через подтверждение.
    public func request(_ action: ContainerAction, on container: Container) {
        if action.isDestructive {
            pendingAction = PendingAction(action: action, container: container)
        } else {
            Task { await perform(action, on: container) }
        }
    }

    public func confirm(_ pending: PendingAction) {
        pendingAction = nil
        Task { await perform(pending.action, on: pending.container) }
    }

    private func perform(_ action: ContainerAction, on container: Container) async {
        guard let session else {
            lastOutcome = ActionOutcome(
                action: action, containerName: container.name,
                succeeded: false, message: "нет подключения к хосту"
            )
            return
        }
        lastOutcome = await session.perform(action, on: container)
    }

    /// Подтягивает образы, тома и сети выбранного хоста.
    public func loadResources() async {
        guard let session else {
            images = []
            volumes = []
            networks = []
            return
        }
        let fetched = await session.resources()
        images = fetched.images
        volumes = fetched.volumes
        networks = fetched.networks
    }

    /// Переключает поток логов на другой контейнер.
    public func watchLogs(of container: Container) async {
        logTask?.cancel()
        logs.removeAll()
        guard let session else { return }
        // Строки складываются в поток и разбираются одним потребителем:
        // задача на строку выполняется в произвольном порядке, и лог
        // перемешивается — незаметно и обидно.
        let (lines, continuation) = AsyncStream<String>.makeStream(
            bufferingPolicy: .bufferingNewest(4096))
        let stream = await session.streamLogs(for: container) { line in
            continuation.yield(line)
        }
        logTask = Task { [weak self] in
            defer { stream.cancel() }
            for await line in lines {
                await MainActor.run { self?.logs.append(line) }
            }
        }
    }

    public func stopWatchingLogs() {
        logTask?.cancel()
        logTask = nil
    }

}
