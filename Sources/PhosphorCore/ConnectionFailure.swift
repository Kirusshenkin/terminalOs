public import Foundation

/// Why a host could not be reached — as a type, so the interface can name it
/// in the person's language and the bridge in its own.
///
/// "Could not connect" is useless: the fix differs completely between a proxy
/// that is down, a server that is asleep and a key that was removed.
public enum ConnectionFailure: Error, Sendable, Equatable {
    case proxyDown(host: String, port: Int)
    case denied(host: String)
    case hostKeyChanged(host: String)
    /// First visit: the key is not known yet and has to be accepted on purpose.
    case hostKeyUnknown(host: String)
    case unreachable(address: String)
    /// The server said something itself; its words are passed on as they are.
    case remote(String)
    case other(host: String)
    /// The chain of bastions cannot be followed; nothing was dialled.
    case route(RouteProblem)
    /// The failure happened on a bastion, not on the host behind it. `inner`
    /// names the bastion, `bastionID` lets the app act on it — trust its key,
    /// open its editor.
    indirect case bastion(bastionID: UUID, inner: ConnectionFailure)
}

/// Why a host's chain of bastions cannot be followed.
///
/// Each case fails closed: falling back to a direct connection would send
/// traffic past the path the person chose, which is worse than not connecting.
public enum RouteProblem: Error, Sendable, Hashable {
    /// `host` jumps through a bastion that is no longer in the list.
    case missingBastion(host: String)
    /// The chain comes back to `host`.
    case loop(host: String)
    /// More bastions in a row than `Route.maxHops`.
    case tooDeep(host: String)
}
