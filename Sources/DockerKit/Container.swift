public import Foundation
public import PhosphorCore

/// A container as the daemon reports it.
public struct Container: Identifiable, Hashable, Sendable {
    public enum State: String, Sendable {
        case running, exited, paused, restarting, created, dead, unknown

        public var isHealthyLooking: Bool { self == .running }

        public var title: String {
            switch self {
            case .running: "работает"
            case .exited: "остановлен"
            case .paused: "на паузе"
            case .restarting: "перезапускается"
            case .created: "создан"
            case .dead: "мёртв"
            case .unknown: "неизвестно"
            }
        }
    }

    public var id: String
    public var name: String
    public var image: String
    public var state: State
    public var status: String
    public var ports: String
    /// `com.docker.compose.project`, used to group containers into stacks.
    public var project: String?
    public var health: String?

    public init(
        id: String, name: String, image: String, state: State,
        status: String, ports: String = "", project: String? = nil, health: String? = nil
    ) {
        self.id = id
        self.name = name
        self.image = image
        self.state = state
        self.status = status
        self.ports = ports
        self.project = project
        self.health = health
    }

    /// Health from `docker inspect`, when the image declares a healthcheck.
    public var isUnhealthy: Bool { health?.lowercased() == "unhealthy" }
}

/// Live resource figures from `docker stats`.
public struct ContainerStats: Sendable, Equatable {
    public var id: String
    public var name: String
    public var cpu: Double
    public var memoryUsed: Int64
    public var memoryLimit: Int64
    public var pids: Int

    public init(id: String, name: String, cpu: Double, memoryUsed: Int64, memoryLimit: Int64, pids: Int) {
        self.id = id
        self.name = name
        self.cpu = cpu
        self.memoryUsed = memoryUsed
        self.memoryLimit = memoryLimit
        self.pids = pids
    }
}

/// Commands and parsers for the docker CLI.
///
/// The daemon is reached through the CLI over the existing SSH channel rather
/// than by exposing the Engine API: it works on every server that has docker,
/// without opening a socket or tunnelling to one.
public enum DockerCLI {
    /// Everything the container list needs, one JSON object per line.
    public static func list(prefix: String = "docker") -> String {
        "\(prefix) ps -a --no-trunc --format '{{json .}}'"
    }

    public static func stats(prefix: String = "docker") -> String {
        "\(prefix) stats --no-stream --format '{{json .}}'"
    }

    public static func logs(
        id: String, tail: Int = 500, follow: Bool = true, prefix: String = "docker"
    ) -> String {
        let follows = follow ? "-f " : ""
        return "\(prefix) logs \(follows)--tail \(tail) --timestamps \(Shell.quote(id))"
    }

    public static func action(_ verb: String, id: String, prefix: String = "docker") -> String {
        "\(prefix) \(verb) \(Shell.quote(id))"
    }

    public static func inspect(id: String, prefix: String = "docker") -> String {
        "\(prefix) inspect \(Shell.quote(id))"
    }

    /// Разбирает `.Config.Env` из ответа `docker inspect`.
    ///
    /// Значение может само содержать `=` — делим по первому и только по нему,
    /// иначе `DSN=postgres://u:p@h/db?x=1` теряет хвост.
    public static func parseEnvironment(_ output: String) -> [(name: String, value: String)] {
        guard let data = output.data(using: .utf8),
            let objects = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]],
            let config = objects.first?["Config"] as? [String: Any],
            let lines = config["Env"] as? [String]
        else { return [] }

        return lines.compactMap { line in
            guard let split = line.firstIndex(of: "=") else { return nil }
            let name = String(line[line.startIndex..<split])
            guard !name.isEmpty else { return nil }
            return (name, String(line[line.index(after: split)...]))
        }
    }

    /// Parses `docker ps --format '{{json .}}'`, one object per line.
    ///
    /// Lines that do not parse are skipped rather than failing the batch: a
    /// single odd container should not blank the whole panel.
    public static func parseList(_ output: String) -> [Container] {
        output.components(separatedBy: .newlines).compactMap { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty, trimmed.hasPrefix("{"),
                let data = trimmed.data(using: .utf8),
                let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            else { return nil }

            let id = (object["ID"] as? String) ?? (object["Id"] as? String) ?? ""
            guard !id.isEmpty else { return nil }
            let status = (object["Status"] as? String) ?? ""
            let rawState = ((object["State"] as? String) ?? "").lowercased()
            let state =
                Container.State(rawValue: rawState)
                ?? (status.lowercased().hasPrefix("up") ? .running : .unknown)

            var project: String?
            if let labels = object["Labels"] as? String {
                for pair in labels.split(separator: ",") where pair.hasPrefix("com.docker.compose.project=") {
                    project = String(pair.dropFirst("com.docker.compose.project=".count))
                }
            }
            let health =
                status.lowercased().contains("unhealthy")
                ? "unhealthy"
                : status.lowercased().contains("healthy") ? "healthy" : nil

            return Container(
                id: id,
                name: (object["Names"] as? String) ?? (object["Name"] as? String) ?? id,
                image: (object["Image"] as? String) ?? "",
                state: state,
                status: status,
                ports: (object["Ports"] as? String) ?? "",
                project: project,
                health: health
            )
        }
    }

    /// Parses `docker stats --no-stream --format '{{json .}}'`.
    public static func parseStats(_ output: String) -> [ContainerStats] {
        output.components(separatedBy: .newlines).compactMap { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("{"), let data = trimmed.data(using: .utf8),
                let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            else { return nil }
            let usage = (object["MemUsage"] as? String) ?? ""
            let parts = usage.components(separatedBy: " / ")
            return ContainerStats(
                id: (object["ID"] as? String) ?? (object["Container"] as? String) ?? "",
                name: (object["Name"] as? String) ?? "",
                cpu: percent((object["CPUPerc"] as? String) ?? ""),
                memoryUsed: parts.count == 2 ? bytes(parts[0]) : 0,
                memoryLimit: parts.count == 2 ? bytes(parts[1]) : 0,
                pids: Int((object["PIDs"] as? String) ?? "") ?? 0
            )
        }
    }

    static func percent(_ text: String) -> Double {
        Double(text.replacingOccurrences(of: "%", with: "").trimmingCharacters(in: .whitespaces)).map {
            $0 / 100
        } ?? 0
    }

    /// Docker prints `1.234GiB`, `640MiB`, `88.5kB`. Both binary and decimal
    /// suffixes appear depending on the field, so both are handled.
    static func bytes(_ text: String) -> Int64 {
        let value = text.trimmingCharacters(in: .whitespaces)
        let units: [(String, Double)] = [
            ("GiB", 1_073_741_824), ("MiB", 1_048_576), ("KiB", 1_024),
            ("GB", 1_000_000_000), ("MB", 1_000_000), ("kB", 1_000), ("B", 1),
        ]
        for (suffix, multiplier) in units where value.hasSuffix(suffix) {
            let number = Double(value.dropLast(suffix.count)) ?? 0
            return Int64(number * multiplier)
        }
        return Int64(Double(value) ?? 0)
    }
}
