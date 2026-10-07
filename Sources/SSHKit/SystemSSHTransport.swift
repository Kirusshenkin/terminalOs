public import Foundation
public import HostsKit
public import PhosphorCore

/// Runs commands through `/usr/bin/ssh`, multiplexed over one connection.
///
/// `ControlMaster` means the first connection authenticates and every later
/// command rides the same socket: no repeated logins, no repeated Touch ID, and
/// the shell, the docker queries and the metrics loop all share one channel.
public actor SystemSSHTransport: SSHTransport {
    nonisolated public let host: ServerHost

    private let controlPath: String
    private let route: Route
    /// Когда прокси в последний раз подтверждённо отвечал.
    ///
    /// Проверять его перед каждой командой — лишний коннект каждые несколько
    /// секунд; не проверять вовсе — вернуться к неотличимым ошибкам.
    private var proxyCheckedAt: ContinuousClock.Instant?
    private let proxyCheckLifetime: Duration = .seconds(30)

    /// Путь к управляющему сокету этого хоста.
    ///
    /// Публичный, потому что интерактивный шелл в терминале обязан ехать по
    /// тому же соединению: иначе будет второй логин и второй Touch ID.
    nonisolated public let socketPath: String

    public init(host: ServerHost, route: Route) {
        self.host = host
        self.route = route
        self.controlPath = SSHInvocation.controlPath(for: host)
        self.socketPath = controlPath
    }

    /// Аргументы, общие для каждого вызова.
    private var baseArguments: [String] {
        SSHInvocation.arguments(host: host, route: route, controlPath: controlPath)
    }

    public func run(_ command: String, timeout: Duration = .seconds(30)) async throws -> CommandResult {
        try await run(command, input: nil, timeout: timeout)
    }

    /// То же, но с данными на stdin команды: так на сервер едет файл любого
    /// размера, без упора в предел длины командной строки.
    public func run(
        _ command: String, input: Data?, timeout: Duration = .seconds(30)
    ) async throws -> CommandResult {
        if let problem = route.problem { throw TransportError.route(problem) }
        if case .socks(let proxyHost, let proxyPort) = route.entry {
            guard await Reachability.canConnect(host: proxyHost, port: proxyPort, timeout: .seconds(2)) else {
                throw TransportError.proxyUnreachable(host: proxyHost, port: proxyPort)
            }
        }
        let target = SSHInvocation.target(host)
        let result = try await Subprocess.run(
            executable: SSHInvocation.executable,
            arguments: baseArguments + [target, command],
            input: input,
            timeout: timeout
        )
        if result.status != 0 {
            if let failure = SSHFailure.classify(result.stderr, host: host, bastions: route.bastions) {
                throw failure
            }
            if let failure = await diagnoseBastions(stderr: result.stderr) { throw failure }
        }
        return result
    }

    /// Ищет, на каком бастионе оборвался путь, — проверкой, а не догадкой.
    ///
    /// С `ControlPersist` ssh отправляет stderr вложенного ProxyCommand в
    /// /dev/null: отказ бастиона виден только как «Connection closed by UNKNOWN».
    /// Поэтому бастионы проверяются по очереди, снаружи внутрь, каждый своим
    /// входом; первый, кто не пустил, и есть причина. Все пустили — значит,
    /// последний не достучался до цели.
    private func diagnoseBastions(stderr: String) async -> TransportError? {
        guard !route.bastions.isEmpty, stderr.lowercased().contains("connection closed") else {
            return nil
        }
        for (index, bastion) in route.bastions.enumerated() {
            let before = Route(entry: route.entry, bastions: Array(route.bastions.prefix(index)))
            let probe = SystemSSHTransport(host: bastion, route: before)
            do {
                _ = try await probe.run("true", timeout: .seconds(15))
            } catch let failure as TransportError {
                if case .bastion = failure { return failure }
                return .bastion(bastion, failure)
            } catch {
                return .bastion(bastion, .hostUnreachable(bastion.address))
            }
        }
        return .hostUnreachable(host.address)
    }

    /// Выполняет команду, только если канал к хосту уже открыт. nil — канала нет.
    ///
    /// Для фонового опроса: он не должен логиниться сам. Вход из фона — это
    /// Touch ID или пароль, всплывающий без видимой причины. `ControlMaster=no`
    /// и `BatchMode=yes` стоят впереди: у ssh побеждает первое значение опции.
    public func runIfConnected(_ command: String, timeout: Duration = .seconds(10)) async -> CommandResult? {
        let target = SSHInvocation.target(host)
        // Проверка сокета локальная и мгновенная. Ошибка запуска значит то же,
        // что и мёртвый канал: опросить хост сейчас нельзя.
        guard
            let check = try? await Subprocess.run(
                executable: SSHInvocation.executable,
                arguments: ["-o", "ControlPath=\(controlPath)", "-O", "check", target],
                timeout: .seconds(3)),
            check.status == 0
        else { return nil }
        // Обрыв посреди опроса — та же картина «нет связи», что и nil выше;
        // различать их рейлу незачем.
        return try? await Subprocess.run(
            executable: SSHInvocation.executable,
            arguments: ["-o", "ControlMaster=no", "-o", "BatchMode=yes"] + baseArguments + [target, command],
            timeout: timeout)
    }

    /// Runs a long-lived command, delivering output line by line.
    public func stream(_ command: String, onLine: @escaping @Sendable (String) -> Void) async throws {
        let target = SSHInvocation.target(host)
        try await Subprocess.stream(
            executable: SSHInvocation.executable,
            arguments: baseArguments + [target, command],
            onLine: onLine
        )
    }

    /// Убеждается, что прокси на месте, не чаще раза в полминуты.
    private func ensureProxyAlive(host proxyHost: String, port proxyPort: Int) async throws {
        if let checked = proxyCheckedAt, ContinuousClock.now - checked < proxyCheckLifetime {
            return
        }
        guard
            await Reachability.canConnect(
                host: proxyHost, port: proxyPort, timeout: .seconds(2)
            )
        else {
            proxyCheckedAt = nil
            throw TransportError.proxyUnreachable(host: proxyHost, port: proxyPort)
        }
        proxyCheckedAt = .now
    }

    // MARK: - Первый визит

    /// Достаёт ключ сервера, которого ещё нет в known_hosts, — не входя на него.
    ///
    /// ssh пишет ключ во временный файл на этапе обмена ключами, а вход
    /// заведомо не случится: все способы аутентификации выключены. Так ключ
    /// приходит тем же путём, что и при настоящем подключении, — через прокси
    /// или бастион, если они заданы, — а `ssh-keyscan` про них не знает.
    public func scanHostKey() async throws -> ScannedHostKey {
        let scratch = NSTemporaryDirectory() + "phosphor-scan-\(UUID().uuidString)"
        defer {
            // Временный файл с публичным ключом: не секрет, и если не удалился,
            // его подберёт система вместе с остальным временным.
            try? FileManager.default.removeItem(atPath: scratch)
        }
        let probe = [
            "-o", "UserKnownHostsFile=\(scratch)", "-o", "GlobalKnownHostsFile=/dev/null",
            "-o", "StrictHostKeyChecking=accept-new", "-o", "HashKnownHosts=no",
            "-o", "ControlMaster=no", "-o", "ControlPath=none", "-o", "BatchMode=yes",
            "-o", "PubkeyAuthentication=no", "-o", "PasswordAuthentication=no",
            "-o", "KbdInteractiveAuthentication=no",
        ]
        if let problem = route.problem { throw TransportError.route(problem) }
        let scan = try await Subprocess.run(
            executable: SSHInvocation.executable,
            arguments: probe + baseArguments + [SSHInvocation.target(host), "true"],
            timeout: .seconds(15))
        guard let lines = try? String(contentsOfFile: scratch, encoding: .utf8),
            !lines.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            // Вход на цель заведомо не случится, поэтому её отказы не в счёт;
            // а вот бастион, не пустивший дальше, — настоящая причина.
            if case .bastion(let bastion, let failure)? =
                SSHFailure.classify(scan.stderr, host: host, bastions: route.bastions)
            {
                throw TransportError.bastion(bastion, failure)
            }
            if case .bastion(let bastion, let failure)? = await diagnoseBastions(stderr: scan.stderr) {
                throw TransportError.bastion(bastion, failure)
            }
            throw TransportError.hostUnreachable(host.address)
        }
        let listing = try await Subprocess.run(
            executable: "/usr/bin/ssh-keygen", arguments: ["-l", "-f", scratch], timeout: .seconds(5))
        return ScannedHostKey(lines: lines, fingerprints: ScannedHostKey.fingerprints(listing.stdout))
    }

    /// Записывает принятый ключ в `~/.ssh/known_hosts`. Только по явному
    /// согласию человека, увидевшего отпечаток.
    public func trust(
        _ key: ScannedHostKey, knownHosts path: String = NSHomeDirectory() + "/.ssh/known_hosts"
    ) throws {
        let manager = FileManager.default
        if !manager.fileExists(atPath: path) {
            guard manager.createFile(atPath: path, contents: nil, attributes: [.posixPermissions: 0o600])
            else {
                throw TransportError.commandFailed(status: 1, stderr: "cannot create \(path)")
            }
        }
        let handle = try FileHandle(forWritingTo: URL(fileURLWithPath: path))
        defer { try? handle.close() }  // закрытие после записи не теряет данных
        try handle.seekToEnd()
        // Файл может не кончаться переводом строки — тогда ключ прилип бы к
        // чужой записи и испортил обе.
        var text = key.lines.hasSuffix("\n") ? key.lines : key.lines + "\n"
        if try handle.offset() > 0 { text = "\n" + text }
        try handle.write(contentsOf: Data(text.utf8))
    }
    public func close() async {
        let target = SSHInvocation.target(host)
        _ = try? await Subprocess.run(
            executable: SSHInvocation.executable,
            arguments: ["-o", "ControlPath=\(controlPath)", "-O", "exit", target],
            timeout: .seconds(5)
        )
        proxyCheckedAt = nil
    }
}

/// Ключ сервера, пришедший при первом визите: строки для known_hosts и
/// отпечатки, которые человек сверяет с консолью провайдера.
public struct ScannedHostKey: Sendable, Equatable {
    public var lines: String
    public var fingerprints: [String]

    public init(lines: String, fingerprints: [String]) {
        self.lines = lines
        self.fingerprints = fingerprints
    }

    /// `256 SHA256:abc… host (ED25519)` → `ED25519 SHA256:abc…`. Чистая функция.
    public static func fingerprints(_ listing: String) -> [String] {
        listing.split(separator: "\n").compactMap { line in
            let parts = line.split(separator: " ")
            guard parts.count >= 2, let hash = parts.first(where: { $0.hasPrefix("SHA256:") }) else {
                return nil
            }
            let kind = parts.last.map { $0.trimmingCharacters(in: CharacterSet(charactersIn: "()")) } ?? ""
            return kind.isEmpty ? String(hash) : "\(kind) \(hash)"
        }
    }
}
