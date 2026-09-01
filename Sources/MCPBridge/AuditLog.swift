public import Foundation
public import PhosphorCore

/// Одна запись о том, что делал ИИ.
public struct AuditEntry: Codable, Sendable, Equatable, Identifiable {
    public var id: UUID
    public var time: Date
    public var tool: String
    public var hostName: String
    public var arguments: String
    public var decision: String
    public var succeeded: Bool
    public var summary: String

    public init(
        id: UUID = UUID(), time: Date = Date(), tool: String, hostName: String,
        arguments: String, decision: String, succeeded: Bool, summary: String
    ) {
        self.id = id
        self.time = time
        self.tool = tool
        self.hostName = hostName
        self.arguments = arguments
        self.decision = decision
        self.succeeded = succeeded
        self.summary = summary
    }

    /// Строка для файла: одна запись — одна строка JSON.
    var line: String {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(self) else { return "" }
        return String(decoding: data, as: UTF8.self)
    }
}

/// Журнал действий ИИ, только на дозапись.
///
/// Смысл не в самом факте логирования, а в том, что **пишущего инструмента для
/// этого журнала не существует**: модель может выполнить действие, но не может
/// подчистить след. Поэтому файл открывается на дозапись и никогда не
/// перезаписывается целиком.
public actor AuditLog {
    private let url: URL
    private var handle: FileHandle?
    /// Последние записи для экрана «Активность ИИ»; на диске лежит всё.
    private var recent = RingBuffer<AuditEntry>(capacity: 500)

    public init(url: URL? = nil) {
        self.url = url ?? Self.defaultURL()
    }

    public static func defaultURL() -> URL {
        let base =
            FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first ?? URL(fileURLWithPath: NSHomeDirectory())
        return base.appendingPathComponent("Phosphor/audit.jsonl")
    }

    public func record(_ entry: AuditEntry) {
        recent.append(entry)
        let line = entry.line + "\n"
        guard let data = line.data(using: .utf8) else { return }
        do {
            try append(data)
        } catch {
            // Потеря записи не должна ронять приложение, но и молчать нельзя.
            recent.append(
                AuditEntry(
                    tool: "audit", hostName: "—", arguments: "",
                    decision: "запись в журнал не удалась", succeeded: false,
                    summary: "\(error)"
                ))
        }
    }

    private func append(_ data: Data) throws {
        if handle == nil {
            let directory = url.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            if !FileManager.default.fileExists(atPath: url.path) {
                FileManager.default.createFile(
                    atPath: url.path, contents: nil,
                    attributes: [.posixPermissions: NSNumber(value: Int16(0o600))]
                )
            }
            handle = try FileHandle(forWritingTo: url)
        }
        guard let handle else { return }
        try handle.seekToEnd()
        try handle.write(contentsOf: data)
        // Журнал теряет смысл, если запись переживёт падение только иногда.
        try handle.synchronize()
    }

    public func entries() -> [AuditEntry] { recent.elements }

    /// Читает журнал с диска целиком. Битые строки пропускаются: одна
    /// испорченная запись не должна прятать все остальные.
    public func readAll() -> [AuditEntry] {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return text.split(separator: "\n").compactMap { line in
            guard let data = line.data(using: .utf8) else { return nil }
            return try? decoder.decode(AuditEntry.self, from: data)
        }
    }

    public func close() {
        try? handle?.close()
        handle = nil
    }
}
