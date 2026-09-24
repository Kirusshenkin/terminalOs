public import Foundation
public import HostsKit
public import PhosphorCore
public import SSHKit

/// Проброс порта: локальный или удалённый.
public struct PortForward: Identifiable, Codable, Hashable, Sendable {
    public enum Direction: String, Codable, CaseIterable, Sendable {
        /// Порт на моей машине ведёт на сервер: `-L`.
        case local
        /// Порт на сервере ведёт ко мне: `-R`.
        case remote

        public var flag: String { self == .local ? "-L" : "-R" }
    }

    public var id: UUID
    public var direction: Direction
    public var listenPort: Int
    public var targetHost: String
    public var targetPort: Int
    public var hostID: ServerHost.ID
    /// Поднимать автоматически при подключении к хосту.
    public var autoStart: Bool

    public init(
        id: UUID = UUID(), direction: Direction = .local,
        listenPort: Int, targetHost: String = "127.0.0.1", targetPort: Int,
        hostID: ServerHost.ID, autoStart: Bool = false
    ) {
        self.id = id
        self.direction = direction
        self.listenPort = listenPort
        self.targetHost = targetHost
        self.targetPort = targetPort
        self.hostID = hostID
        self.autoStart = autoStart
    }

    /// Спецификация в том виде, в каком её понимает ssh.
    ///
    /// Локальный слушает только на `127.0.0.1`: пробросить порт и случайно
    /// открыть его всей сети — обидная ошибка, и по умолчанию её быть не должно.
    public var specification: String {
        direction == .local
            ? "127.0.0.1:\(listenPort):\(targetHost):\(targetPort)"
            : "\(listenPort):\(targetHost):\(targetPort)"
    }
}

/// Поднимает и опускает пробросы на живом соединении.
///
/// Использует управляющий сокет: `ssh -O forward` добавляет проброс к уже
/// открытому соединению, без второго логина и без отдельного процесса.
public actor ForwardManager {
    private let host: ServerHost
    private let reach: Reach
    private let controlPath: String
    // Свой список поднятых пробросов убран, а не удалён: его никто не читал,
    // потому что состояние держит приложение (`AppModel.activeForwards`) — там
    // же, где кнопки. Две копии одного факта разъезжаются молча, а эта ещё и
    // умирала вместе с менеджером при переподключении.
    // private var active: Set<UUID> = []

    public init(host: ServerHost, reach: Reach, controlPath: String) {
        self.host = host
        self.reach = reach
        self.controlPath = controlPath
    }

    public func start(_ forward: PortForward) async throws {
        try await control("forward", forward)
    }

    public func stop(_ forward: PortForward) async throws {
        try await control("cancel", forward)
    }

    private func control(_ verb: String, _ forward: PortForward) async throws {
        var arguments = SSHInvocation.arguments(host: host, reach: reach, controlPath: controlPath)
        arguments += [
            "-O", verb, forward.direction.flag, forward.specification,
            SSHInvocation.target(host),
        ]
        let result = try await Subprocess.run(
            executable: SSHInvocation.executable, arguments: arguments, timeout: .seconds(15))
        guard result.succeeded else {
            throw Self.explain(result.stderr, forward: forward)
        }
    }

    /// Раскладывает жалобу ssh по причинам, у каждой из которых своё лекарство.
    static func explain(_ stderr: String, forward: PortForward) -> ForwardProblem {
        let lower = stderr.lowercased()
        if lower.contains("address already in use") { return .portTaken(forward.listenPort) }
        if lower.contains("not a control") || lower.contains("control socket") { return .noConnection }
        if lower.contains("permission denied") { return .needsPrivilege(forward.listenPort) }
        return .other(String(stderr.prefix(160)).trimmingCharacters(in: .whitespacesAndNewlines))
    }
}

/// Почему проброс не поднялся.
public enum ForwardProblem: Error, Sendable, Equatable {
    /// Порт на этой машине уже занят.
    case portTaken(Int)
    /// Нет живого соединения с хостом.
    case noConnection
    /// Порт ниже 1024 требует прав.
    case needsPrivilege(Int)
    case other(String)
}
