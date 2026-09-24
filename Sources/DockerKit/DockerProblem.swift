/// What docker complained about, sorted into cases that each have a fix.
///
/// Docker's stderr is a dump, not an explanation; the words for each case
/// live in the interface and in the bridge.
public enum DockerProblem: Error, Sendable, Equatable {
    /// No access to the docker socket: needs sudo or the docker group.
    case noSocketAccess
    /// The container or object is already gone.
    case gone
    case notRunning
    /// Docker refuses to remove a running container.
    case stopFirst
    /// Something still uses the object.
    case inUse
    /// Anything else, with docker's own words trimmed.
    case other(String)

    public static func classify(_ stderr: String) -> DockerProblem {
        let lower = stderr.lowercased()
        if lower.contains("permission denied") { return .noSocketAccess }
        if lower.contains("cannot remove") && lower.contains("running") { return .stopFirst }
        if lower.contains("is not running") { return .notRunning }
        if lower.contains("in use") || lower.contains("being used") { return .inUse }
        if lower.contains("no such") { return .gone }
        return .other(String(stderr.prefix(200)).trimmingCharacters(in: .whitespacesAndNewlines))
    }
}
