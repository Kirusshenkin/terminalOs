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

/// Что можно сделать с образом, томом или сетью.
///
/// Отдельный тип, а не строка команды в кнопке: так все разрушающие действия
/// видны в одном месте и ни одно не уедет на сервер без подтверждения.
public enum ResourceAction: Sendable, Equatable {
    case removeImage(id: String, name: String)
    case pruneImages
    case removeVolume(name: String)
    case pruneVolumes
    case removeNetwork(id: String, name: String)
    case pruneNetworks

    /// Всё здесь необратимо, но сносить один объект и подчищать все
    /// неиспользуемые — риск разного масштаба, и предупреждать надо по-разному.
    public var title: String {
        switch self {
        case .removeImage: "удалить образ"
        case .pruneImages: "удалить безымянные образы"
        case .removeVolume: "удалить том"
        case .pruneVolumes: "удалить неиспользуемые тома"
        case .removeNetwork: "удалить сеть"
        case .pruneNetworks: "удалить неиспользуемые сети"
        }
    }

    public var subject: String {
        switch self {
        case .removeImage(_, let name): name
        case .removeVolume(let name): name
        case .removeNetwork(_, let name): name
        case .pruneImages: "все образы без имени"
        case .pruneVolumes: "все тома, которые никто не подключил"
        case .pruneNetworks: "все сети, к которым никто не подключён"
        }
    }

    /// Чем это грозит. Текст пишем до того, как человек нажмёт «да».
    public var warning: String {
        switch self {
        case .removeImage:
            "образ придётся качать заново; контейнеры на нём удалить не даст"
        case .pruneImages:
            "слои без имени уйдут — следующая сборка будет дольше"
        case .removeVolume:
            "данные внутри тома пропадут навсегда"
        case .pruneVolumes:
            "данные всех неподключённых томов пропадут навсегда"
        case .removeNetwork:
            "контейнеры в этой сети потеряют связь друг с другом"
        case .pruneNetworks:
            "пользовательские сети без контейнеров будут удалены"
        }
    }

    public func command(prefix: String = "docker") -> String {
        switch self {
        case .removeImage(let id, _): "\(prefix) image rm \(Shell.quote(id))"
        case .pruneImages: "\(prefix) image prune -f"
        case .removeVolume(let name): "\(prefix) volume rm \(Shell.quote(name))"
        case .pruneVolumes: "\(prefix) volume prune -f"
        case .removeNetwork(let id, _): "\(prefix) network rm \(Shell.quote(id))"
        case .pruneNetworks: "\(prefix) network prune -f"
        }
    }

    /// Превращает жалобу docker в понятную фразу.
    public static func explain(_ result: CommandResult) -> String {
        guard !result.succeeded else { return "готово" }
        let stderr = result.stderr.lowercased()
        if stderr.contains("permission denied") {
            return "нет доступа к сокету docker — нужен sudo или группа docker"
        }
        if stderr.contains("in use") || stderr.contains("being used") {
            return "занято: сначала убрать контейнеры, которые это используют"
        }
        if stderr.contains("no such") {
            return "этого уже нет"
        }
        return String(result.stderr.prefix(200))
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
