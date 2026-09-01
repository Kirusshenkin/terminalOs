public import Foundation
public import PhosphorCore

/// Something you can do to a container.
///
/// Modelled as a type rather than a string so the destructive ones cannot be
/// invoked by accident, and so the interface can ask before the dangerous half.
public enum ContainerAction: String, CaseIterable, Sendable {
    case start, stop, restart, pause, unpause, kill, remove

    public var verb: String {
        self == .remove ? "rm" : rawValue
    }

    /// Actions that lose something you cannot get back by repeating them.
    public var isDestructive: Bool {
        switch self {
        case .kill, .remove: true
        case .start, .stop, .restart, .pause, .unpause: false
        }
    }

    public var title: String {
        switch self {
        case .start: "запустить"
        case .stop: "остановить"
        case .restart: "перезапустить"
        case .pause: "приостановить"
        case .unpause: "продолжить"
        case .kill: "убить"
        case .remove: "удалить"
        }
    }

    /// Which actions make sense in a given state, so the interface offers only
    /// those and never sends a command the daemon will refuse.
    public static func available(for state: Container.State) -> [ContainerAction] {
        switch state {
        case .running: [.restart, .stop, .pause, .kill, .remove]
        case .paused: [.unpause, .stop, .kill, .remove]
        case .exited, .created, .dead: [.start, .remove]
        case .restarting: [.stop, .kill]
        case .unknown: [.remove]
        }
    }

    /// The exact command, with the identifier quoted.
    public func command(id: String, prefix: String = "docker") -> String {
        "\(prefix) \(verb) \(Shell.quote(id))"
    }
}

/// What happened when an action ran.
public struct ActionOutcome: Sendable, Equatable {
    public var action: ContainerAction
    public var containerName: String
    public var succeeded: Bool
    /// Message for the person, not the raw stderr dump.
    public var message: String

    public init(action: ContainerAction, containerName: String, succeeded: Bool, message: String) {
        self.action = action
        self.containerName = containerName
        self.succeeded = succeeded
        self.message = message
    }

    /// Turns docker's complaint into something actionable.
    public static func from(
        result: CommandResult, action: ContainerAction, container: String
    ) -> ActionOutcome {
        guard !result.succeeded else {
            return ActionOutcome(
                action: action, containerName: container,
                succeeded: true, message: "\(action.title): готово"
            )
        }
        let stderr = result.stderr.lowercased()
        let message: String =
            if stderr.contains("permission denied") {
                "нет доступа к сокету docker — нужен sudo или группа docker"
            } else if stderr.contains("no such container") {
                "контейнера уже нет"
            } else if stderr.contains("is not running") {
                "контейнер не запущен"
            } else if stderr.contains("cannot remove") && stderr.contains("running") {
                "сначала остановить: удалять работающий контейнер docker не даёт"
            } else {
                String(result.stderr.prefix(200)).trimmingCharacters(in: .whitespacesAndNewlines)
            }
        return ActionOutcome(
            action: action, containerName: container, succeeded: false, message: message
        )
    }
}
