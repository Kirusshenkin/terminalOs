public import PhosphorCore

/// The resolved way to a host: which bastions to pass through and how the
/// first of them — or the host itself, when there are none — is reached.
///
/// `Reach` is what the person set; `Route` is what ssh needs. A `.jump` only
/// names another host, and that host may have its own proxy or bastion, so
/// the chain is unrolled here, once, where the whole address book is known.
public struct Route: Hashable, Sendable {
    /// Bastions are rare beyond one; three is generous and stops a chain that
    /// was built by accident before ssh does something surprising with it.
    public static let maxHops = 3

    /// How the outermost hop is dialled: `.direct` or `.socks`, never `.jump`.
    public var entry: Reach
    /// Bastions in the order the connection passes them, outermost first.
    public var bastions: [ServerHost]
    /// Set when the chain is broken. Such a route must not be dialled at all.
    public var problem: RouteProblem?

    public init(entry: Reach = .direct, bastions: [ServerHost] = [], problem: RouteProblem? = nil) {
        self.entry = entry
        self.bastions = bastions
        self.problem = problem
    }

    public static let direct = Route()

    static func broken(_ problem: RouteProblem) -> Route {
        Route(problem: problem)
    }
}

extension HostBook {
    /// Unrolls the host's bastions into a route. Never falls back to a direct
    /// connection: a broken chain comes back with `problem` set.
    public func route(for host: ServerHost) -> Route {
        var chain: [ServerHost] = []
        var seen: Set<ServerHost.ID> = [host.id]
        var current = host
        while case .jump(let id) = reach(for: current) {
            guard let bastion = hosts.first(where: { $0.id == id }) else {
                return .broken(.missingBastion(host: current.name))
            }
            guard seen.insert(id).inserted else { return .broken(.loop(host: bastion.name)) }
            guard chain.count < Route.maxHops else { return .broken(.tooDeep(host: host.name)) }
            chain.append(bastion)
            current = bastion
        }
        return Route(entry: reach(for: current), bastions: chain.reversed())
    }

    /// Hosts that can serve as a bastion for `host`: everything except the
    /// host itself and hosts whose own route already passes through it.
    public func bastionCandidates(for host: ServerHost.ID?) -> [ServerHost] {
        hosts.filter { candidate in
            guard let host else { return true }
            if candidate.id == host { return false }
            return !route(for: candidate).bastions.contains { $0.id == host }
        }
    }
}
