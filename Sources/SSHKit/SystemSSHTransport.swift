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
    public nonisolated let socketPath: String

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
            if stderr.contains("host key") && stderr.contains("changed") {
                throw TransportError.hostKeyChanged
            }
            if stderr.contains("could not resolve") || stderr.contains("connection timed out") {
                throw TransportError.hostUnreachable(host.address)
            }
        }
        return result
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
