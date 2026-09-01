public import DockerKit
public import Foundation
public import HostsKit
public import PhosphorCore
public import SessionKit

/// Что вернул инструмент.
public struct ToolResult: Sendable, Equatable {
    public var text: String
    public var isError: Bool

    public init(text: String, isError: Bool = false) {
        self.text = text
        self.isError = isError
    }
}

/// Как именно выполнять вызов.
public enum RunMode: Sendable, Equatable {
    /// По-настоящему.
    case live
    /// Сухой прогон: инструмент рассказывает, что сделал бы, и ничего не делает.
    ///
    /// Нужен не для отладки, а для доверия: можно посмотреть намерение
    /// целиком, прежде чем пускать его на боевой сервер.
    case dryRun
}

/// Выполняет вызовы инструментов через политику и пишет их в журнал.
///
/// Ключевая мысль здесь такая: результаты инструментов — логи контейнеров,
/// вывод команд — это **недоверенный текст**, который модель может принять за
/// инструкции. Фильтровать его бесполезно. Защита в другом: пишущее действие не
/// выполняется без решения человека, что бы в этом тексте ни было написано.
public actor ToolRunner {
    /// Спрашивает человека. Возвращает `true`, если он согласился.
    public typealias Confirm = @Sendable (String, String) async -> Bool

    private let policy: AccessPolicy
    private let audit: AuditLog
    private let confirm: Confirm
    private let sessions: @Sendable (ServerHost.ID) async -> HostSession?
    private let book: @Sendable () async -> HostBook

    public init(
        policy: AccessPolicy,
        audit: AuditLog,
        book: @escaping @Sendable () async -> HostBook,
        sessions: @escaping @Sendable (ServerHost.ID) async -> HostSession?,
        confirm: @escaping Confirm
    ) {
        self.policy = policy
        self.audit = audit
        self.book = book
        self.sessions = sessions
        self.confirm = confirm
    }

    /// Выполняет вызов инструмента.
    public func call(
        _ name: String,
        arguments: [String: String],
        mode: RunMode = .live
    ) async -> ToolResult {
        guard let tool = ToolCatalog.tool(named: name) else {
            return ToolResult(text: "неизвестный инструмент: \(name)", isError: true)
        }

        // Инструменты, не привязанные к хосту, отвечают сразу.
        if name == "list_hosts" {
            let result = await listHosts()
            await log(tool: tool, host: "—", arguments: arguments, decision: "allow", result: result)
            return result
        }

        guard let hostID = arguments["host"].flatMap(UUID.init(uuidString:)),
            let host = await book().hosts.first(where: { $0.id == hostID })
        else {
            return ToolResult(text: "не указан или не найден хост", isError: true)
        }

        let command = arguments["command"]
        let decision = await policy.decide(tool: tool, host: hostID, command: command)

        switch decision {
        case .deny(let reason):
            let result = ToolResult(text: "отказано: \(reason)", isError: true)
            await log(
                tool: tool, host: host.name, arguments: arguments,
                decision: "deny: \(reason)", result: result)
            return result

        case .confirm(let what):
            guard await confirm(host.name, what) else {
                let result = ToolResult(text: "человек отклонил действие", isError: true)
                await log(
                    tool: tool, host: host.name, arguments: arguments,
                    decision: "refused", result: result)
                return result
            }
            await policy.grant(for: hostID)

        case .allow:
            break
        }

        if mode == .dryRun {
            let result = ToolResult(text: "сухой прогон: \(plan(tool: tool, arguments: arguments))")
            await log(
                tool: tool, host: host.name, arguments: arguments,
                decision: "dry-run", result: result)
            return result
        }

        if tool.kind == .write { await policy.recordWrite() }
        let result = await execute(tool, host: host, arguments: arguments)
        await log(
            tool: tool, host: host.name, arguments: arguments,
            decision: "allow", result: result)
        return result
    }

    /// Что инструмент сделал бы, словами.
    private func plan(tool: Tool, arguments: [String: String]) -> String {
        switch tool.name {
        case "run_command": "выполнил бы: \(arguments["command"] ?? "—")"
        case "container_action":
            "\(arguments["action"] ?? "—") для контейнера \(arguments["container"] ?? "—")"
        case "manage_authorized_key":
            "\(arguments["operation"] ?? "—") ключа \(arguments["fingerprint"] ?? "—")"
        default: tool.summary
        }
    }

    private func listHosts() async -> ToolResult {
        let hosts = await book().hosts
        guard !hosts.isEmpty else { return ToolResult(text: "хостов нет") }
        let lines = hosts.map { host in
            "\(host.id.uuidString)  \(host.name)  \(host.user)@\(host.address):\(host.port)"
        }
        return ToolResult(text: lines.joined(separator: "\n"))
    }

    private func execute(
        _ tool: Tool, host: ServerHost, arguments: [String: String]
    ) async -> ToolResult {
        guard let session = await sessions(host.id) else {
            return ToolResult(text: "нет подключения к \(host.name)", isError: true)
        }
        let state = await session.current

        switch tool.name {
        case "host_metrics": return metrics(state)
        case "list_containers": return containerList(state)
        case "container_logs": return await logs(state, session: session, arguments: arguments)
        case "container_inspect": return await inspect(state, session: session, arguments: arguments)
        case "list_authorized_keys":
            return await run("cat ~/.ssh/authorized_keys 2>/dev/null || true", on: session)
        case "run_command":
            guard let command = arguments["command"] else {
                return ToolResult(text: "не указана команда", isError: true)
            }
            return await run(command, on: session)
        case "container_action":
            return await containerAction(state, session: session, arguments: arguments)
        default:
            return ToolResult(text: "инструмент пока не реализован", isError: true)
        }
    }

    private func metrics(_ state: SessionState) -> ToolResult {
        guard let snapshot = state.latest else {
            return ToolResult(text: "метрики ещё не собраны", isError: true)
        }
        let usage = state.coreUsage.map { ByteFormat.percent($0) }.joined(separator: " ")
        let disks = snapshot.filesystems
            .map { "\($0.mount) \(ByteFormat.percent($0.usage))" }
            .joined(separator: ", ")
        return ToolResult(
            text: """
                аптайм: \(ByteFormat.duration(seconds: snapshot.uptime))
                загрузка: \(snapshot.loadOne) \(snapshot.loadFive) \(snapshot.loadFifteen)
                ядра: \(usage.isEmpty ? "—" : usage)
                память: \(ByteFormat.size(snapshot.memoryUsed)) из \(ByteFormat.size(snapshot.memoryTotal))
                диски: \(disks.isEmpty ? "—" : disks)
                """)
    }

    private func containerList(_ state: SessionState) -> ToolResult {
        guard !state.containers.isEmpty else { return ToolResult(text: "контейнеров нет") }
        return ToolResult(
            text: state.containers.map { container in
                "\(container.name)  \(container.image)  \(container.state.rawValue)  \(container.status)"
            }.joined(separator: "\n"))
    }

    /// Находит контейнер по имени или идентификатору.
    private func container(in state: SessionState, arguments: [String: String]) -> Container? {
        guard let key = arguments["container"] else { return nil }
        return state.containers.first { $0.name == key || $0.id == key }
    }

    private func logs(
        _ state: SessionState, session: HostSession, arguments: [String: String]
    ) async -> ToolResult {
        guard let container = container(in: state, arguments: arguments) else {
            return ToolResult(text: "контейнер не найден", isError: true)
        }
        // Верхний предел жёсткий: мегабайт логов в ответе бесполезен и дорог.
        let tail = min(Int(arguments["tail"] ?? "") ?? 100, 1_000)
        let command = DockerCLI.logs(
            id: container.id, tail: tail, follow: false,
            prefix: state.profile?.dockerPrefix ?? "docker")
        return await run(command, on: session)
    }

    private func inspect(
        _ state: SessionState, session: HostSession, arguments: [String: String]
    ) async -> ToolResult {
        guard let container = container(in: state, arguments: arguments) else {
            return ToolResult(text: "контейнер не найден", isError: true)
        }
        return await run(
            DockerCLI.inspect(id: container.id, prefix: state.profile?.dockerPrefix ?? "docker"),
            on: session)
    }

    private func containerAction(
        _ state: SessionState, session: HostSession, arguments: [String: String]
    ) async -> ToolResult {
        guard let raw = arguments["action"], let action = ContainerAction(rawValue: raw),
            let container = container(in: state, arguments: arguments)
        else { return ToolResult(text: "не указано действие или контейнер", isError: true) }
        let outcome = await session.perform(action, on: container)
        return ToolResult(text: outcome.message, isError: !outcome.succeeded)
    }

    /// Выполняет команду и обрезает вывод.
    ///
    /// Мегабайт логов в ответе бесполезен и дорог, поэтому предел жёсткий.
    private func run(_ command: String, on session: HostSession) async -> ToolResult {
        do {
            let result = try await session.run(command)
            let text = result.succeeded ? result.stdout : result.stderr
            let trimmed = String(text.prefix(16_000))
            return ToolResult(
                text: trimmed.isEmpty ? "(пусто)" : trimmed,
                isError: !result.succeeded
            )
        } catch {
            return ToolResult(text: "\(error)", isError: true)
        }
    }

    private func log(
        tool: Tool, host: String, arguments: [String: String],
        decision: String, result: ToolResult
    ) async {
        // Секреты не попадают в журнал даже как аргументы.
        let safe =
            arguments
            .map { "\($0.key)=\(Redaction.isSecret(name: $0.key) ? Redaction.mask : $0.value)" }
            .sorted()
            .joined(separator: " ")
        await audit.record(
            AuditEntry(
                tool: tool.name, hostName: host, arguments: String(safe.prefix(400)),
                decision: decision, succeeded: !result.isError,
                summary: String(result.text.prefix(200))
            ))
    }
}
