public import DockerKit
public import Foundation
public import HostsKit
public import MetricsKit
public import PhosphorCore
public import ProvisionKit
public import SSHKit

/// What the interface knows about one host right now.
public struct SessionState: Sendable {
    public enum Phase: Sendable, Equatable {
        case idle
        case connecting
        case probing
        case ready
        /// Failed, with a message that says what to do next.
        case failed(String)
    }

    public var phase: Phase = .idle
    public var profile: HostProfile?
    public var containers: [Container] = []
    public var stats: [String: ContainerStats] = [:]
    public var latest: Snapshot?
    public var previous: Snapshot?

    public init() {}

    /// Per-core usage, empty until two snapshots exist — usage is a difference,
    /// so a single reading genuinely says nothing.
    public var coreUsage: [Double] {
        guard let previous, let latest else { return [] }
        return SnapshotParser.usage(from: previous, to: latest)
    }

    public var coreSteal: [Double] {
        guard let previous, let latest else { return [] }
        return SnapshotParser.steal(from: previous, to: latest)
    }

    public var throughput: [SnapshotParser.Throughput] {
        guard let previous, let latest else { return [] }
        return SnapshotParser.throughput(from: previous, to: latest)
    }
}

/// Everything happening against one server, over one connection.
///
/// The shell, container queries and the metrics loop all ride the same
/// multiplexed SSH connection: one login, one authentication, one place to
/// notice that the host went away.
/// Собирает строки в блок между разделителями `---`.
///
/// Простая структура без собственной конкурентности: порядок обеспечивает тот,
/// кто её вызывает. Оборачивать каждую строку в отдельную задачу нельзя — они
/// выполняются в произвольном порядке, и блоки перемешиваются.
private struct BlockCollector {
    private var lines: [String] = []

    /// Возвращает готовый блок, когда он завершён.
    mutating func feed(_ line: String) -> String? {
        guard line != "---" else {
            let block = lines.joined(separator: "\n")
            lines.removeAll(keepingCapacity: true)
            return block.isEmpty ? nil : block
        }
        lines.append(line)
        // Сервер, печатающий мусор, не должен раздувать буфер бесконечно.
        if lines.count > 512 { lines.removeAll(keepingCapacity: true) }
        return nil
    }
}

public actor HostSession {
    nonisolated public let host: ServerHost

    private let transport: any SSHTransport
    private var state = SessionState()
    private var pollTask: Task<Void, Never>?
    private var metricsTask: Task<Void, Never>?
    private var observers: [UUID: @Sendable (SessionState) -> Void] = [:]

    /// How often the container list is refreshed while the window is in front.
    public var pollInterval: Duration = .seconds(4)
    /// Polling stops entirely when nobody is looking. A terminal is open all
    /// day; a background window has no business waking the CPU.
    public private(set) var isActive = true

    public init(host: ServerHost, reach: Reach) {
        self.host = host
        self.transport = SystemSSHTransport(host: host, reach: reach)
    }

    public init(host: ServerHost, transport: any SSHTransport) {
        self.host = host
        self.transport = transport
    }

    /// Текущее состояние одним значением.
    public var current: SessionState { state }

    /// Registers an observer and hands it the current state immediately.
    public func observe(_ body: @escaping @Sendable (SessionState) -> Void) -> UUID {
        let token = UUID()
        observers[token] = body
        body(state)
        return token
    }

    public func stopObserving(_ token: UUID) {
        observers[token] = nil
    }

    private func publish() {
        for observer in observers.values { observer(state) }
    }

    private func set(phase: SessionState.Phase) {
        state.phase = phase
        publish()
    }

    /// Connects, builds the host profile, then starts the two loops.
    public func start() async {
        guard state.phase == .idle else { return }
        set(phase: .connecting)
        do {
            set(phase: .probing)
            let result = try await transport.run(HostProbe.command, timeout: .seconds(20))
            guard result.succeeded else {
                throw TransportError.commandFailed(status: result.status, stderr: result.stderr)
            }
            state.profile = HostProbe.parse(result.stdout)
            set(phase: .ready)
            startPolling()
            startMetrics()
        } catch {
            set(phase: .failed(Self.explain(error, host: host)))
        }
    }

    /// Turns a failure into something that says what to do about it.
    ///
    /// "Could not connect" is useless: the fix differs completely between a
    /// proxy that is down, a server that is asleep and a key that was removed.
    static func explain(_ error: any Error, host: ServerHost) -> String {
        switch error {
        case TransportError.proxyUnreachable(let proxy, let port):
            "прокси \(proxy):\(port) не отвечает — запущен ли V2Box?"
        case TransportError.authenticationFailed:
            "\(host.name) отказал в доступе — ключа нет в authorized_keys?"
        case TransportError.hostKeyChanged:
            "ключ хоста \(host.name) изменился — подключение остановлено"
        case TransportError.hostUnreachable(let address):
            "\(address) не отвечает"
        case TransportError.commandFailed(_, let stderr) where !stderr.isEmpty:
            String(stderr.prefix(200))
        default:
            "не удалось подключиться к \(host.name)"
        }
    }

    public func setActive(_ active: Bool) {
        isActive = active
    }

    /// Refreshes containers and their figures while anyone is watching.
    private func startPolling() {
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                if await self.isActive { await self.refreshContainers() }
                try? await Task.sleep(for: await self.pollInterval)
            }
        }
    }

    public func refreshContainers() async {
        let prefix = state.profile?.dockerPrefix ?? "docker"
        guard state.profile?.dockerPath != nil else { return }
        if let list = try? await transport.run(DockerCLI.list(prefix: prefix)), list.succeeded {
            state.containers = DockerCLI.parseList(list.stdout)
        }
        if let stats = try? await transport.run(DockerCLI.stats(prefix: prefix)), stats.succeeded {
            state.stats = Dictionary(
                DockerCLI.parseStats(stats.stdout).map { ($0.name, $0) },
                uniquingKeysWith: { first, _ in first }
            )
        }
        publish()
    }

    /// One long-lived channel printing `/proc` snapshots, rather than a storm
    /// of exec calls.
    ///
    /// Строки проходят через поток с единственным потребителем: порядок здесь
    /// не роскошь, а условие правильности — снимок, собранный из перемешанных
    /// строк, даёт неверные дельты.
    private func startMetrics() {
        metricsTask?.cancel()
        metricsTask = Task { [weak self] in
            guard let self else { return }
            let (lines, continuation) = AsyncStream<String>.makeStream(
                bufferingPolicy: .bufferingNewest(4096))

            let reader = Task {
                try? await self.stream(ProcProbe.loop()) { line in
                    continuation.yield(line)
                }
                continuation.finish()
            }
            defer { reader.cancel() }

            var collector = BlockCollector()
            for await line in lines {
                if let block = collector.feed(line) { await self.accept(block: block) }
            }
        }
    }

    private func stream(_ command: String, onLine: @escaping @Sendable (String) -> Void) async throws {
        try await transport.stream(command, onLine: onLine)
    }

    private func accept(block: String) {
        guard let snapshot = SnapshotParser.parse(block) else { return }
        state.previous = state.latest
        state.latest = snapshot
        publish()
    }

    /// Выполняет действие над контейнером и сразу обновляет список.
    ///
    /// Разрушающие действия сюда доходят только после подтверждения в
    /// интерфейсе: решение принимает человек, а не эта функция.
    public func perform(_ action: ContainerAction, on container: Container) async -> ActionOutcome {
        let prefix = state.profile?.dockerPrefix ?? "docker"
        do {
            let result = try await transport.run(
                action.command(id: container.id, prefix: prefix), timeout: .seconds(45))
            let outcome = ActionOutcome.from(
                result: result, action: action, container: container.name)
            await refreshContainers()
            return outcome
        } catch {
            return ActionOutcome(
                action: action, containerName: container.name,
                succeeded: false, message: Self.explain(error, host: host)
            )
        }
    }

    /// Поток логов контейнера.
    ///
    /// Буфер ограничен сверху: неограниченный — это утечка с отложенным сроком,
    /// а логи умеют идти мегабайтами в секунду.
    public func streamLogs(
        for container: Container,
        tail: Int = 500,
        onLine: @escaping @Sendable (String) -> Void
    ) -> Task<Void, Never> {
        let prefix = state.profile?.dockerPrefix ?? "docker"
        let command = DockerCLI.logs(id: container.id, tail: tail, prefix: prefix)
        return Task { [transport] in
            try? await transport.stream(command, onLine: onLine)
        }
    }

    public func run(_ command: String) async throws -> CommandResult {
        try await transport.run(command)
    }

    public func stop() async {
        pollTask?.cancel()
        metricsTask?.cancel()
        pollTask = nil
        metricsTask = nil
        await transport.close()
        state.phase = .idle
        publish()
    }
}
