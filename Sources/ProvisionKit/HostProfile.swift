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
    /// `uname -s`: Linux, Darwin and so on. nil in profiles cached before the
    /// probe asked — those were all collected the Linux way.
    public var kernelName: String?

    public enum OSFamily: String, Sendable, Equatable, Codable {
        case linux, darwin, other
    }

    public var osFamily: OSFamily {
        switch kernelName?.lowercased() {
        case nil, "linux": .linux
        case "darwin": .darwin
        default: .other
        }
    }

    /// Metrics come from `/proc` on Linux and from sysctl and friends on macOS.
    /// Elsewhere the collector would print nothing and the panel would look
    /// disconnected.
    public var hasMetrics: Bool { osFamily != .other }

    /// Name for people: `macOS 15.1` rather than the probe's `macos 15.1`.
    public var displayName: String {
        osFamily == .darwin ? "macOS \(osVersion)" : "\(osName) \(osVersion)"
    }

    /// How a person installs `package` here — for hints and the install button.
    /// nil when the package manager is unknown: a guessed command is worse than
    /// none, because it fails in a way that looks like our bug.
    /// `interactive: false` — for running it ourselves: `sudo -n` refuses at
    /// once instead of waiting for a password nobody can type.
    public func installCommand(for package: String, interactive: Bool = true) -> String? {
        let sudo = isRoot ? "" : interactive ? "sudo " : "sudo -n "
        switch packageManager {
        case "apt" where !interactive:
            // Без человека у терминала: свежий сервер ещё без списков пакетов,
            // а debconf не должен ничего спрашивать.
            return "\(sudo)apt-get update -qq && "
                + "\(sudo)env DEBIAN_FRONTEND=noninteractive apt-get install -y -qq \(package)"
        case "apt": return "\(sudo)apt install -y \(package)"
        case "dnf": return "\(sudo)dnf install -y \(package)"
        case "brew": return "brew install \(package)"
        default: return nil
        }
    }

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
        // `-n`: без терминала sudo не может спросить пароль — пусть сразу
        // откажет, а не повиснет в ожидании ввода, которого не будет.
        return dockerNeedsSudo ? "sudo -n \(binary)" : binary
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
    public static let command = Shell.withPackagePaths + script

    private static let script = """
        echo "KERNEL $(uname -s)"; \
        echo "OS $(if [ -r /etc/os-release ]; then . /etc/os-release && echo "$ID ${VERSION_ID:-?}"; \
            elif command -v sw_vers >/dev/null; then echo "macos $(sw_vers -productVersion)"; \
            else echo unknown ?; fi)"; \
        echo "UP $(cut -d. -f1 /proc/uptime 2>/dev/null || sysctl -n kern.boottime 2>/dev/null \
            | awk -v now="$(date +%s)" '{gsub(",", "", $4); print now - $4}' || echo 0)"; \
        echo "ID $(id -u)"; \
        echo "SUDO $(sudo -n true 2>/dev/null && echo yes || echo no)"; \
        echo "DOCKER $(command -v docker || echo -)"; \
        echo "PODMAN $(command -v podman || echo -)"; \
        echo "DOCKEROK $(docker info >/dev/null 2>&1 && echo yes || echo no)"; \
        echo "NGINX $(command -v nginx || echo -)"; \
        echo "CERTBOT $(command -v certbot || echo -)"; \
        echo "UFW $(command -v ufw || echo -)"; \
        echo "PKG $(if command -v apt-get >/dev/null; then echo apt; \
            elif command -v dnf >/dev/null; then echo dnf; \
            elif command -v brew >/dev/null || [ -x /opt/homebrew/bin/brew ] || [ -x /usr/local/bin/brew ]; \
            then echo brew; else echo -; fi)"; \
        echo "CONTAINERS $( (docker ps -aq 2>/dev/null || sudo -n docker ps -aq 2>/dev/null) | wc -l | tr -d ' ')"; \
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
            // sudo помогает, только если он без пароля: иначе честнее показать
            // отказ docker и подсказку про группу, чем ошибку sudo о терминале.
            dockerNeedsSudo: dockerPath != nil && values["DOCKEROK"] == "no" && values["SUDO"] == "yes",
            isPodman: dockerPath == nil && podmanPath != nil,
            hasNginx: values["NGINX"].map { $0 != "-" } ?? false,
            hasCertbot: values["CERTBOT"].map { $0 != "-" } ?? false,
            hasUFW: values["UFW"].map { $0 != "-" } ?? false,
            containerCount: Int(values["CONTAINERS"] ?? "0") ?? 0,
            authorizedKeyCount: Int(values["KEYS"] ?? "0") ?? 0,
            packageManager: values["PKG"].flatMap { $0 == "-" ? nil : $0 },
            kernelName: values["KERNEL"].flatMap { $0.isEmpty ? nil : $0 }
        )
    }
}
