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

    public init(host: ServerHost, reach: Reach) {
        self.host = host
        self.reach = reach
        // Socket names have a hard length limit, so the identifier is hashed.
        let short = String(host.id.uuidString.prefix(8))
        self.controlPath = NSTemporaryDirectory() + "phosphor-\(short).sock"
    }

    /// Base arguments shared by every invocation.
    ///
    /// `StrictHostKeyChecking=yes` is deliberate: a changed host key is a block,
    /// not a prompt. `BatchMode` keeps ssh from stopping on a hidden question.
    private var baseArguments: [String] {
        var arguments = [
            "-o", "ControlMaster=auto",
            "-o", "ControlPath=\(controlPath)",
            "-o", "ControlPersist=120",
            "-o", "StrictHostKeyChecking=yes",
            "-o", "BatchMode=yes",
            "-o", "ConnectTimeout=8",
            // Terrapin (CVE-2023-48795) applies to ChaCha20-Poly1305 and to CBC
            // with Encrypt-then-MAC. Preferring AES-GCM sidesteps it entirely
            // on servers that support it.
            "-o", "Ciphers=aes256-gcm@openssh.com,aes128-gcm@openssh.com,aes256-ctr,aes128-ctr",
            // Agent forwarding stays off: on a compromised host it signs
            // anything in your name.
            "-o", "ForwardAgent=no",
            "-p", String(host.port),
        ]
        if case .socks(let proxyHost, let proxyPort) = reach {
            // Hand the *name* to the proxy so DNS resolves on its side: no leak,
            // and no "that domain does not resolve here".
            arguments += ["-o", "ProxyCommand=/usr/bin/nc -x \(proxyHost):\(proxyPort) -X 5 %h %p"]
        }
        return arguments
    }

    public func run(_ command: String, timeout: Duration = .seconds(30)) async throws -> CommandResult {
        if case .socks(let proxyHost, let proxyPort) = reach {
            guard await Reachability.canConnect(host: proxyHost, port: proxyPort, timeout: .seconds(2)) else {
                throw TransportError.proxyUnreachable(host: proxyHost, port: proxyPort)
            }
        }
        let target = "\(host.user)@\(host.address)"
        let result = try await Subprocess.run(
            executable: "/usr/bin/ssh",
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
        let target = "\(host.user)@\(host.address)"
        try await Subprocess.stream(
            executable: "/usr/bin/ssh",
            arguments: baseArguments + [target, command],
            onLine: onLine
        )
    }

    public func close() async {
        let target = "\(host.user)@\(host.address)"
        _ = try? await Subprocess.run(
            executable: "/usr/bin/ssh",
            arguments: ["-o", "ControlPath=\(controlPath)", "-O", "exit", target],
            timeout: .seconds(5)
        )
    }
}
