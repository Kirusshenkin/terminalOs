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

    /// Переключает поток логов на другой контейнер.
    public func watchLogs(of container: Container) async {
        logTask?.cancel()
        logs.removeAll()
        guard let session else { return }
        logTask = await session.streamLogs(for: container) { [weak self] line in
            Task { @MainActor in self?.logs.append(line) }
        }
    }

    public func stopWatchingLogs() {
        logTask?.cancel()
        logTask = nil
    }

}
