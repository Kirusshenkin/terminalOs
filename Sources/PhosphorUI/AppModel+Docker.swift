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
                succeeded: false, message: strings("err.noSession")
            )
            return
        }
        lastOutcome = await session.perform(action, on: container)
    }

    /// Переносит новый интервал опроса в живую сессию, не дожидаясь
    /// переподключения.
    public func applyPollInterval() {
        guard let session else { return }
        Task { await session.setPollInterval(.seconds(pollSeconds)) }
    }

    /// Меняет глубину буфера логов. Старые строки при уменьшении отбрасываются:
    /// буфер на то и кольцевой.
    public func applyLogCapacity() {
        var fresh = RingBuffer<String>(capacity: logLines)
        for line in logs.elements.suffix(logLines) { fresh.append(line) }
        logs = fresh
    }

    /// Читает переменные окружения контейнера с сервера.
    ///
    /// Значения секретных по имени переменных маскируются здесь же: между
    /// сервером и экраном они не задерживаются ни в одном промежуточном виде.
    public func loadEnvironment(for container: Container) async {
        containerEnvironment = []
        containerEnvironmentNote = nil
        guard let session else {
            containerEnvironmentNote = strings("err.noSession")
            return
        }
        do {
            let result = try await session.run(DockerCLI.inspect(id: container.id))
            guard result.succeeded else {
                containerEnvironmentNote =
                    result.stderr.isEmpty ? strings("err.inspectSilent") : result.stderr
                return
            }
            let parsed = DockerCLI.parseEnvironment(result.stdout)
            containerEnvironment = Redaction.apply(to: parsed)
            if parsed.isEmpty { containerEnvironmentNote = strings("dock.noEnv") }
        } catch {
            containerEnvironmentNote = "\(error)"
        }
    }

    /// Спрашивает перед удалением: у образов, томов и сетей отмены нет.
    public func request(_ action: ResourceAction) {
        pendingResource = PendingResource(action: action)
    }

    public func confirm(_ pending: PendingResource) {
        pendingResource = nil
        Task { await perform(pending.action) }
    }

    private func perform(_ action: ResourceAction) async {
        guard let session else {
            resourcesMessage = strings("err.noSession")
            return
        }
        do {
            let result = try await session.run(action.command())
            resourcesMessage = "\(action.title): \(ResourceAction.explain(result))"
        } catch {
            resourcesMessage = "\(action.title): \(error)"
        }
        await loadResources()
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
