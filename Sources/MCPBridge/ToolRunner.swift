public import DockerKit
public import KeysKit
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
    /// Применяет правку списка хостов. Живёт в приложении: там запись на диск.
    private let edit: @Sendable (HostEdit) async -> Void

    public init(
        policy: AccessPolicy,
        audit: AuditLog,
        book: @escaping @Sendable () async -> HostBook,
        sessions: @escaping @Sendable (ServerHost.ID) async -> HostSession?,
        edit: @escaping @Sendable (HostEdit) async -> Void = { _ in },
        confirm: @escaping Confirm
    ) {
        self.policy = policy
        self.audit = audit
        self.book = book
        self.sessions = sessions
        self.edit = edit
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

        if name == "add_host" || name == "update_host" || name == "remove_host" {
            return await editHosts(tool: tool, arguments: arguments, mode: mode)
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
        case "host_report": return ToolResult(text: HostReport.text(state))
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
        case "manage_authorized_key":
            return await manageKey(session: session, arguments: arguments)
        default:
            return ToolResult(text: "инструмент пока не реализован", isError: true)
        }
    }

    /// Добавляет или убирает ключ в `authorized_keys` на сервере.
    ///
    /// Защита от самоблокировки живёт здесь, а не в вызывающем: человек может
    /// осознанно снести ключ, которым подключён, — модель не может. Даже с
    /// разрешением на запись она не должна оставить хост без единого рабочего
    /// ключа, потому что назад её никто не пустит.
    private func manageKey(
        session: HostSession, arguments: [String: String]
    ) async -> ToolResult {
        guard let action = arguments["action"], action == "add" || action == "remove" else {
            return ToolResult(text: "нужен action: add или remove", isError: true)
        }
        let read = await run("cat ~/.ssh/authorized_keys 2>/dev/null || true", on: session)
        guard !read.isError else { return read }
        let keys = AuthorizedKeysFile.parse(read.text == "(пусто)" ? "" : read.text)

        let updated: [AuthorizedKey]
        switch action {
        case "add":
            guard let line = arguments["key"], !line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return ToolResult(text: "не указан ключ", isError: true)
            }
            let added = AuthorizedKeysFile.parse(line)
            guard let key = added.first, added.count == 1 else {
                return ToolResult(text: "строка не похожа на один ключ", isError: true)
            }
            guard !keys.contains(where: { $0.fingerprint == key.fingerprint }) else {
                return ToolResult(text: "такой ключ уже есть: \(key.fingerprint)")
            }
            updated = keys + [key]
        default:
            guard let wanted = arguments["fingerprint"], !wanted.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return ToolResult(text: "не указан отпечаток", isError: true)
            }
            let doomed = Set(keys.filter { $0.fingerprint == wanted }.map(\.id))
            guard !doomed.isEmpty else {
                return ToolResult(text: "ключа с таким отпечатком на сервере нет", isError: true)
            }
            guard
                !AuthorizedKeysFile.wouldLockOut(
                    keys: keys, removing: doomed, currentFingerprint: nil)
            else {
                return ToolResult(
                    text: "после удаления не осталось бы ни одного рабочего ключа",
                    isError: true)
            }
            updated = keys.filter { !doomed.contains($0.id) }
        }

        let write = await run(
            AuthorizedKeysFile.writeCommand(content: AuthorizedKeysFile.render(updated)),
            on: session)
        guard !write.isError else { return write }
        return ToolResult(text: "ключей на сервере: \(updated.count)")
    }

    /// Правит список серверов: завести, изменить, убрать.
    ///
    /// Спрашивает человека всегда — в любом режиме, включая полный. Режимы
    /// описывают доверие к **серверу**, а здесь меняется твой собственный
    /// список: адрес, под которым скрывается машина, стоит показать глазами
    /// прежде, чем он туда попадёт. Из списка убирается только запись —
    /// сам сервер остаётся жить, где жил.
    private func editHosts(
        tool: Tool, arguments: [String: String], mode: RunMode
    ) async -> ToolResult {
        let hosts = await book().hosts

        let intent: HostEdit
        let summary: String
        switch tool.name {
        case "add_host":
            guard let address = arguments["address"]?.trimmingCharacters(in: .whitespaces),
                !address.isEmpty
            else { return ToolResult(text: "не указан адрес", isError: true) }
            let host = ServerHost(
                name: arguments["name"]?.isEmpty == false ? arguments["name"]! : address,
                address: address,
                port: arguments["port"].flatMap(Int.init) ?? 22,
                user: arguments["user"]?.isEmpty == false ? arguments["user"]! : "root",
                tags: (arguments["tags"] ?? "")
                    .split(separator: ",")
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                    .filter { !$0.isEmpty }
            )
            guard !hosts.contains(where: { $0.address == host.address && $0.user == host.user })
            else { return ToolResult(text: "такой сервер уже есть в списке") }
            intent = .add(host)
            summary = "завести \(host.user)@\(host.address):\(host.port) как «\(host.name)»"
        case "update_host", "remove_host":
            guard let id = arguments["host"].flatMap(UUID.init(uuidString:)),
                var host = hosts.first(where: { $0.id == id })
            else { return ToolResult(text: "не указан или не найден хост", isError: true) }
            if tool.name == "remove_host" {
                intent = .remove(host.id)
                summary = "убрать «\(host.name)» (\(host.user)@\(host.address)) из списка"
            } else {
                if let value = arguments["name"], !value.isEmpty { host.name = value }
                if let value = arguments["address"], !value.isEmpty { host.address = value }
                if let value = arguments["user"], !value.isEmpty { host.user = value }
                if let value = arguments["port"], let port = Int(value) { host.port = port }
                if let value = arguments["tags"] {
                    host.tags =
                        value
                        .split(separator: ",")
                        .map { $0.trimmingCharacters(in: .whitespaces) }
                        .filter { !$0.isEmpty }
                }
                intent = .update(host)
                summary = "изменить «\(host.name)» на \(host.user)@\(host.address):\(host.port)"
            }
        default:
            return ToolResult(text: "неизвестная правка", isError: true)
        }

        guard mode == .live else { return ToolResult(text: "сделал бы: \(summary)") }
        guard await confirm("список серверов", summary) else {
            let refusal = ToolResult(text: "человек отказал", isError: true)
            await log(
                tool: tool, host: "—", arguments: arguments, decision: "deny", result: refusal)
            return refusal
        }

        await edit(intent)
        let result = ToolResult(text: "готово: \(summary)")
        await log(tool: tool, host: "—", arguments: arguments, decision: "confirm", result: result)
        return result
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
