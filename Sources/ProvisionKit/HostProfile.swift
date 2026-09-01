public import Foundation
public import PhosphorCore

/// What we learned about a server on first contact.
///
/// Computed once per connection and reused by the docker and metrics panels
/// instead of guessing at every request.
public struct HostProfile: Sendable, Equatable, Codable {
    public var osName: String
    public var osVersion: String
    public var uptimeSeconds: Int
    public var isRoot: Bool
    public var canSudo: Bool
    public var dockerPath: String?
    public var dockerNeedsSudo: Bool
    public var isPodman: Bool
    public var hasNginx: Bool
    public var hasCertbot: Bool
    public var hasUFW: Bool
    public var containerCount: Int
    public var authorizedKeyCount: Int
    public var packageManager: String?

    /// A server nobody has moved into yet.
    ///
    /// Age alone is not enough — a box can be up for a week and already carry a
    /// running stack — so the verdict needs both youth and emptiness.
    public var isFresh: Bool {
        uptimeSeconds < 86_400 * 2
            && dockerPath == nil
            && !hasNginx
            && containerCount == 0
    }

    /// The command prefix for docker on this host.
    public var dockerPrefix: String {
        guard let dockerPath else { return "docker" }
        let binary = isPodman ? "podman" : dockerPath
        return dockerNeedsSudo ? "sudo \(binary)" : binary
    }

    /// Supported for provisioning. Guessing a package manager we have not
    /// tested is how recipes damage servers.
    public var isProvisionable: Bool {
        packageManager == "apt"
    }
}

/// One command that collects the whole profile, and its parser.
public enum HostProbe {
    /// Everything in a single exec: one round trip, one channel.
    public static let command = """
        echo "OS $(. /etc/os-release 2>/dev/null && echo "$ID ${VERSION_ID:-?}" || echo unknown ?)"; \
        echo "UP $(cut -d. -f1 /proc/uptime 2>/dev/null || echo 0)"; \
        echo "ID $(id -u)"; \
        echo "SUDO $(sudo -n true 2>/dev/null && echo yes || echo no)"; \
        echo "DOCKER $(command -v docker || echo -)"; \
        echo "PODMAN $(command -v podman || echo -)"; \
        echo "DOCKEROK $(docker info >/dev/null 2>&1 && echo yes || echo no)"; \
        echo "NGINX $(command -v nginx || echo -)"; \
        echo "CERTBOT $(command -v certbot || echo -)"; \
        echo "UFW $(command -v ufw || echo -)"; \
        echo "PKG $(command -v apt-get >/dev/null && echo apt || (command -v dnf >/dev/null && echo dnf) || echo -)"; \
        echo "CONTAINERS $(docker ps -aq 2>/dev/null | wc -l | tr -d ' ')"; \
        echo "KEYS $(grep -cvE '^\\s*(#|$)' ~/.ssh/authorized_keys 2>/dev/null || echo 0)"
        """

    public static func parse(_ output: String) -> HostProfile {
        var values: [String: String] = [:]
        for line in output.components(separatedBy: .newlines) {
            let parts = line.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
            guard parts.count == 2 else { continue }
            values[String(parts[0])] = String(parts[1]).trimmingCharacters(in: .whitespaces)
        }
        let osParts = (values["OS"] ?? "unknown ?").split(separator: " ", maxSplits: 1)
        let dockerPath = values["DOCKER"].flatMap { $0 == "-" ? nil : $0 }
        let podmanPath = values["PODMAN"].flatMap { $0 == "-" ? nil : $0 }

        return HostProfile(
            osName: String(osParts.first ?? "unknown"),
            osVersion: osParts.count > 1 ? String(osParts[1]) : "?",
            uptimeSeconds: Int(values["UP"] ?? "0") ?? 0,
            isRoot: values["ID"] == "0",
            canSudo: values["SUDO"] == "yes",
            dockerPath: dockerPath ?? podmanPath,
            // Docker present but `docker info` refused means the socket needs
            // privileges — the single most common reason panels come up empty.
            dockerNeedsSudo: dockerPath != nil && values["DOCKEROK"] == "no",
            isPodman: dockerPath == nil && podmanPath != nil,
            hasNginx: values["NGINX"].map { $0 != "-" } ?? false,
            hasCertbot: values["CERTBOT"].map { $0 != "-" } ?? false,
            hasUFW: values["UFW"].map { $0 != "-" } ?? false,
            containerCount: Int(values["CONTAINERS"] ?? "0") ?? 0,
            authorizedKeyCount: Int(values["KEYS"] ?? "0") ?? 0,
            packageManager: values["PKG"].flatMap { $0 == "-" ? nil : $0 }
        )
    }
}
