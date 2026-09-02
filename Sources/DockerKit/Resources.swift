public import Foundation
public import PhosphorCore

/// Образ на сервере.
public struct DockerImage: Identifiable, Sendable, Equatable {
    public var id: String
    public var repository: String
    public var tag: String
    public var size: Int64
    public var created: String

    /// Образ без имени: остаётся после пересборки и занимает место молча.
    public var isDangling: Bool { repository == "<none>" || tag == "<none>" }
    public var name: String { isDangling ? "<без имени>" : "\(repository):\(tag)" }
}

/// Том с данными.
public struct DockerVolume: Identifiable, Sendable, Equatable {
    public var id: String { name }
    public var name: String
    public var driver: String
    public var mountpoint: String
}

/// Сеть.
public struct DockerNetwork: Identifiable, Sendable, Equatable {
    public var id: String
    public var name: String
    public var driver: String
    public var scope: String
}

public extension DockerCLI {
    static func images(prefix: String = "docker") -> String {
        "\(prefix) image ls -a --format '{{json .}}'"
    }

    static func volumes(prefix: String = "docker") -> String {
        "\(prefix) volume ls --format '{{json .}}'"
    }

    static func networks(prefix: String = "docker") -> String {
        "\(prefix) network ls --format '{{json .}}'"
    }

    /// Разбирает построчный JSON в объекты заданного вида.
    private static func objects(_ output: String) -> [[String: Any]] {
        output.components(separatedBy: .newlines).compactMap { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("{"), let data = trimmed.data(using: .utf8) else { return nil }
            return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        }
    }

    static func parseImages(_ output: String) -> [DockerImage] {
        objects(output).compactMap { object in
            guard let id = object["ID"] as? String, !id.isEmpty else { return nil }
            return DockerImage(
                id: id,
                repository: (object["Repository"] as? String) ?? "<none>",
                tag: (object["Tag"] as? String) ?? "<none>",
                size: bytes((object["Size"] as? String) ?? "0"),
                created: (object["CreatedSince"] as? String) ?? ""
            )
        }
    }

    static func parseVolumes(_ output: String) -> [DockerVolume] {
        objects(output).compactMap { object in
            guard let name = object["Name"] as? String, !name.isEmpty else { return nil }
            return DockerVolume(
                name: name,
                driver: (object["Driver"] as? String) ?? "local",
                mountpoint: (object["Mountpoint"] as? String) ?? ""
            )
        }
    }

    static func parseNetworks(_ output: String) -> [DockerNetwork] {
        objects(output).compactMap { object in
            guard let id = object["ID"] as? String, !id.isEmpty else { return nil }
            return DockerNetwork(
                id: id,
                name: (object["Name"] as? String) ?? "",
                driver: (object["Driver"] as? String) ?? "",
                scope: (object["Scope"] as? String) ?? ""
            )
        }
    }
}
