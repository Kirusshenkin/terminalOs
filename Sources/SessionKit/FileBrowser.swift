public import Foundation
public import HostsKit
public import PhosphorCore
public import SSHKit

/// Запись в удалённой директории.
public struct RemoteFile: Identifiable, Sendable, Equatable {
    public var name: String
    public var permissions: String
    public var owner: String
    public var size: Int64
    public var modified: Date?
    public var isDirectory: Bool
    public var isSymlink: Bool
    /// Куда указывает ссылка, если это ссылка.
    public var linkTarget: String?

    public init(
        name: String, permissions: String, owner: String, size: Int64,
        modified: Date?, isDirectory: Bool, isSymlink: Bool, linkTarget: String?
    ) {
        self.name = name
        self.permissions = permissions
        self.owner = owner
        self.size = size
        self.modified = modified
        self.isDirectory = isDirectory
        self.isSymlink = isSymlink
        self.linkTarget = linkTarget
    }

    public var id: String { name }

    public var kind: String {
        if isSymlink { return "ссылка" }
        if isDirectory { return "папка" }
        return (name as NSString).pathExtension.isEmpty
            ? "файл" : (name as NSString).pathExtension
    }
}

/// Разбирает вывод `ls -la` с эпохой вместо даты.
///
/// Формат даты у `ls` зависит от локали и возраста файла, поэтому мы просим
/// секунды с эпохи: разбирать «Jan 5 2023» и «янв 5 12:03» одинаково — это
/// источник тихих ошибок.
public enum ListingParser {
    /// Команда листинга. Имя пути экранируется.
    public static func command(path: String) -> String {
        "ls -la --time-style=+%s -- \(Shell.quote(path)) 2>/dev/null"
            + " || ls -la -- \(Shell.quote(path))"
    }

    public static func parse(_ output: String) -> [RemoteFile] {
        output.components(separatedBy: .newlines).compactMap(entry)
    }

    private static func entry(_ line: String) -> RemoteFile? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, !trimmed.hasPrefix("total ") else { return nil }

        // `права ссылок владелец группа размер время имя`
        let fields = trimmed.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
        guard fields.count >= 7, fields[0].count >= 10 else { return nil }

        let permissions = fields[0]
        guard let size = Int64(fields[4]) else { return nil }

        // Имя начинается после поля времени; сколько бы полей ни занимала дата,
        // мы находим её конец по позиции в исходной строке.
        let timeField = fields[5]
        let isEpoch = timeField.count >= 9 && Int64(timeField) != nil
        let nameFieldIndex = isEpoch ? 6 : 8
        guard fields.count > nameFieldIndex else { return nil }
        let name = fields[nameFieldIndex...].joined(separator: " ")
        guard name != ".", name != ".." || true else { return nil }

        let isSymlink = permissions.hasPrefix("l")
        var target: String?
        var displayName = name
        if isSymlink, let arrow = name.range(of: " -> ") {
            displayName = String(name[name.startIndex..<arrow.lowerBound])
            target = String(name[arrow.upperBound...])
        }

        return RemoteFile(
            name: displayName,
            permissions: permissions,
            owner: "\(fields[2]) \(fields[3])",
            size: size,
            modified: isEpoch ? Int64(timeField).map { Date(timeIntervalSince1970: Double($0)) } : nil,
            isDirectory: permissions.hasPrefix("d"),
            isSymlink: isSymlink,
            linkTarget: target
        )
    }
}

/// Просмотр и передача файлов по тому же соединению, что и всё остальное.
public actor FileBrowser {
    private let transport: any SSHTransport
    private let host: ServerHost
    private let reach: Reach
    private let controlPath: String

    public init(transport: any SSHTransport, host: ServerHost, reach: Reach, controlPath: String) {
        self.transport = transport
        self.host = host
        self.reach = reach
        self.controlPath = controlPath
    }

    /// Содержимое директории, папки первыми.
    public func list(_ path: String) async throws -> [RemoteFile] {
        let result = try await transport.run(ListingParser.command(path: path), timeout: .seconds(30))
        guard result.succeeded || !result.stdout.isEmpty else {
            throw TransportError.commandFailed(status: result.status, stderr: result.stderr)
        }
        return ListingParser.parse(result.stdout)
            .filter { $0.name != "." }
            .sorted { left, right in
                if left.name == ".." { return true }
                if right.name == ".." { return false }
                if left.isDirectory != right.isDirectory { return left.isDirectory }
                return left.name.localizedStandardCompare(right.name) == .orderedAscending
            }
    }

    /// Нормализует переход по пути, не позволяя выйти за корень.
    public nonisolated func resolve(_ current: String, entering name: String) -> String {
        if name == ".." {
            let parent = (current as NSString).deletingLastPathComponent
            return parent.isEmpty ? "/" : parent
        }
        return (current as NSString).appendingPathComponent(name)
    }

    /// Скачивает файл, переиспользуя то же соединение.
    public func download(remote: String, to local: URL) async throws {
        try await copy(
            from: "\(SSHInvocation.target(host)):\(remote)",
            to: local.path
        )
    }

    public func upload(local: URL, to remote: String) async throws {
        try await copy(
            from: local.path,
            to: "\(SSHInvocation.target(host)):\(remote)"
        )
    }

    /// `scp` поверх того же управляющего сокета: без второго логина.
    private func copy(from source: String, to destination: String) async throws {
        var arguments = SSHInvocation.arguments(host: host, reach: reach, controlPath: controlPath)
        // scp понимает те же -o, но порт задаётся большой буквой.
        arguments = arguments.map { $0 == "-p" ? "-P" : $0 }
        arguments += ["--", source, destination]
        let result = try await Subprocess.run(
            executable: "/usr/bin/scp", arguments: arguments, timeout: .seconds(3_600))
        guard result.succeeded else {
            throw TransportError.commandFailed(status: result.status, stderr: result.stderr)
        }
    }
}
