public import Foundation

/// Факт подключения: куда, когда и через что.
///
/// Только факт. Содержимое сессий сюда не попадает никогда — скроллбэк по
/// умолчанию вообще не пишется на диск, и журнал не должен становиться обходным
/// путём для этого правила.
public struct ConnectionEvent: Codable, Identifiable, Sendable, Equatable {
    public enum Kind: String, Codable, Sendable {
        case connected, disconnected, failed
    }

    public var id: UUID
    public var time: Date
    public var hostName: String
    public var address: String
    public var reach: String
    public var kind: Kind
    /// Причина, если не получилось.
    public var detail: String?

    public init(
        id: UUID = UUID(), time: Date = Date(), hostName: String, address: String,
        reach: String, kind: Kind, detail: String? = nil
    ) {
        self.id = id
        self.time = time
        self.hostName = hostName
        self.address = address
        self.reach = reach
        self.kind = kind
        self.detail = detail
    }

    public var title: String {
        switch kind {
        case .connected: "подключение"
        case .disconnected: "отключение"
        case .failed: "не удалось"
        }
    }
}

/// Хранит историю подключений построчным JSON.
public actor ConnectionLog {
    private let url: URL
    private var recent: [ConnectionEvent] = []

    public init(url: URL? = nil) {
        self.url = url ?? Self.defaultURL()
    }

    public static func defaultURL() -> URL {
        let base =
            FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first ?? URL(fileURLWithPath: NSHomeDirectory())
        return base.appendingPathComponent("Phosphor/connections.jsonl")
    }

    public func record(_ event: ConnectionEvent) {
        recent.append(event)
        if recent.count > 500 { recent.removeFirst(recent.count - 500) }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(event) else { return }
        var line = data
        line.append(0x0A)
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let handle = try? FileHandle(forWritingTo: url) {
            defer { try? handle.close() }
            try? handle.seekToEnd()
            try? handle.write(contentsOf: line)
        } else {
            FileManager.default.createFile(
                atPath: url.path, contents: line,
                attributes: [.posixPermissions: NSNumber(value: Int16(0o600))])
        }
    }

    /// Последние события, новые сверху.
    public func readAll(limit: Int = 300) -> [ConnectionEvent] {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return recent.reversed() }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let all = text.split(separator: "\n").compactMap { line -> ConnectionEvent? in
            guard let data = line.data(using: .utf8) else { return nil }
            return try? decoder.decode(ConnectionEvent.self, from: data)
        }
        return Array(all.suffix(limit).reversed())
    }
}
