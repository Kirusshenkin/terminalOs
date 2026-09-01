public import Foundation
public import HostsKit
public import PhosphorCore

/// What went wrong reaching a host.
///
/// The cases exist so the interface can tell "the proxy is down" from "the
/// server is not answering" from "it refused the key". Without that distinction
/// diagnosis turns into guesswork.
public enum TransportError: Error, Equatable {
    case proxyUnreachable(host: String, port: Int)
    case hostUnreachable(String)
    case authenticationFailed
    case hostKeyChanged
    case commandFailed(status: Int32, stderr: String)
    case cancelled
}

/// Anything that can carry commands to a host.
///
/// The protocol exists so the SSH engine is a decision we can revisit: a
/// process-based transport works everywhere today, a native one can slot in
/// later without touching the panels above.
public protocol SSHTransport: Actor {
    var host: ServerHost { get }
    func run(_ command: String, timeout: Duration) async throws -> CommandResult
    func stream(_ command: String, onLine: @escaping @Sendable (String) -> Void) async throws
    func close() async
}

public extension SSHTransport {
    func run(_ command: String) async throws -> CommandResult {
        try await run(command, timeout: .seconds(30))
    }
}
