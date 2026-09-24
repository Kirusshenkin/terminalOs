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
    public enum Failure: Sendable, Equatable {
        case docker(DockerProblem)
        case connection(ConnectionFailure)
        case noSession
    }

    public var action: ContainerAction
    public var containerName: String
    /// `nil` — получилось.
    public var failure: Failure?
    public var succeeded: Bool { failure == nil }

    public init(action: ContainerAction, containerName: String, failure: Failure?) {
        self.action = action
        self.containerName = containerName
        self.failure = failure
    }

    /// Turns docker's complaint into something actionable.
    public static func from(
        result: CommandResult, action: ContainerAction, container: String
    ) -> ActionOutcome {
        ActionOutcome(
            action: action, containerName: container,
            failure: result.succeeded ? nil : .docker(DockerProblem.classify(result.stderr)))
    }
}
