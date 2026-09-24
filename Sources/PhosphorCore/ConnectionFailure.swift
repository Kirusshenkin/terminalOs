/// Why a host could not be reached — as a type, so the interface can name it
/// in the person's language and the bridge in its own.
///
/// "Could not connect" is useless: the fix differs completely between a proxy
/// that is down, a server that is asleep and a key that was removed.
public enum ConnectionFailure: Error, Sendable, Equatable {
    case proxyDown(host: String, port: Int)
    case denied(host: String)
    case hostKeyChanged(host: String)
    case unreachable(address: String)
    /// The server said something itself; its words are passed on as they are.
    case remote(String)
    case other(host: String)
}
