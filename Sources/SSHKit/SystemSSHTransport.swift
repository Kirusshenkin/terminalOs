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
    private let reach: Reach
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

    public init(host: ServerHost, reach: Reach) {
        self.host = host
        self.reach = reach
        // Socket names have a hard length limit, so the identifier is hashed.
        let short = String(host.id.uuidString.prefix(8))
        self.controlPath = NSTemporaryDirectory() + "phosphor-\(short).sock"
        self.socketPath = controlPath
    }

    /// Аргументы, общие для каждого вызова.
    private var baseArguments: [String] {
        SSHInvocation.arguments(host: host, reach: reach, controlPath: controlPath)
    }

    public func run(_ command: String, timeout: Duration = .seconds(30)) async throws -> CommandResult {
        if case .socks(let proxyHost, let proxyPort) = reach {
            guard await Reachability.canConnect(host: proxyHost, port: proxyPort, timeout: .seconds(2)) else {
                throw TransportError.proxyUnreachable(host: proxyHost, port: proxyPort)
            }
        }
        let target = SSHInvocation.target(host)
        let result = try await Subprocess.run(
            executable: SSHInvocation.executable,
            arguments: baseArguments + [target, command],
            timeout: timeout
        )
        if result.status != 0 {
            let stderr = result.stderr.lowercased()
            if stderr.contains("permission denied") { throw TransportError.authenticationFailed }
            // «No ED25519 host key is known for …» — первый визит, а не подмена.
            if stderr.contains("host key is known") { throw TransportError.hostKeyUnknown }
            if stderr.contains("host key") && stderr.contains("changed") {
                throw TransportError.hostKeyChanged
            }
            if stderr.contains("could not resolve") || stderr.contains("connection timed out") {
                throw TransportError.hostUnreachable(host.address)
            }
        }
        return result
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
        _ = try await Subprocess.run(
            executable: SSHInvocation.executable,
            arguments: probe + baseArguments + [SSHInvocation.target(host), "true"],
            timeout: .seconds(15))
        guard let lines = try? String(contentsOfFile: scratch, encoding: .utf8),
            !lines.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { throw TransportError.hostUnreachable(host.address) }
        let listing = try await Subprocess.run(
            executable: "/usr/bin/ssh-keygen", arguments: ["-l", "-f", scratch], timeout: .seconds(5))
        return ScannedHostKey(lines: lines, fingerprints: ScannedHostKey.fingerprints(listing.stdout))
    }

    /// Записывает принятый ключ в `~/.ssh/known_hosts`. Только по явному
    /// согласию человека, увидевшего отпечаток.
    public func trust(_ key: ScannedHostKey, knownHosts path: String = NSHomeDirectory() + "/.ssh/known_hosts") throws {
        let manager = FileManager.default
        if !manager.fileExists(atPath: path) {
            guard manager.createFile(atPath: path, contents: nil, attributes: [.posixPermissions: 0o600]) else {
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
            guard parts.count >= 2, let hash = parts.first(where: { $0.hasPrefix("SHA256:") }) else { return nil }
            let kind = parts.last.map { $0.trimmingCharacters(in: CharacterSet(charactersIn: "()")) } ?? ""
            return kind.isEmpty ? String(hash) : "\(kind) \(hash)"
        }
    }
}
