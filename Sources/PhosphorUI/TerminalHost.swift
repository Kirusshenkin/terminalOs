import AppKit
public import HostsKit
public import PhosphorCore
public import SwiftUI
public import TerminalCore
public import ThemeKit

/// Puts the real emulator into SwiftUI.
///
/// The view is created once and kept: rebuilding it would throw away the shell
/// and everything on screen. Only the theme is pushed on update.
public struct TerminalHost: NSViewRepresentable {
    /// Куда открывать шелл.
    public enum Destination: Equatable {
        case local
        case remote(host: ServerHost, reach: Reach, controlPath: String, session: String?)
    }

    private let theme: Theme
    private let destination: Destination
    private let onGuardRequest: (AnsiGuard.Request) -> Void

    public init(
        theme: Theme,
        destination: Destination,
        onGuardRequest: @escaping (AnsiGuard.Request) -> Void
    ) {
        self.theme = theme
        self.destination = destination
        self.onGuardRequest = onGuardRequest
    }

    public func makeNSView(context: Context) -> TerminalSurface {
        let surface = TerminalSurface(frame: .zero)
        surface.apply(theme: theme)
        surface.onGuardRequest = onGuardRequest
        start(surface)
        context.coordinator.destination = destination
        return surface
    }

    public func updateNSView(_ surface: TerminalSurface, context: Context) {
        surface.apply(theme: theme)
        surface.onGuardRequest = onGuardRequest
        // Перезапускаем шелл, только если сменился адрес: пересоздавать его на
        // каждой перерисовке значит выбрасывать всё, что на экране.
        guard context.coordinator.destination != destination else { return }
        context.coordinator.destination = destination
        start(surface)
    }

    public func makeCoordinator() -> Coordinator { Coordinator() }

    public final class Coordinator {
        var destination: Destination?
    }

    private func start(_ surface: TerminalSurface) {
        switch destination {
        case .local:
            surface.startLocalShell()
        case .remote(let host, let reach, let controlPath, let session):
            surface.startRemoteShell(
                host: host, reach: reach, controlPath: controlPath, tmuxSession: session)
        }
    }
}

/// What the terminal wants a person to decide before it happens.
public struct GuardPrompt: Identifiable, Sendable {
    public var id = UUID()
    public var request: AnsiGuard.Request

    /// Ключ, а не строка: тип живёт вне интерфейса и языка не знает.
    public var titleKey: String {
        switch request {
        case .clipboardWrite: "term.clipboard"
        case .unsafeLink: "term.oddLink"
        }
    }

    /// The exact content, shown in full: agreeing to something invisible is
    /// how a log line ends up executing on your Mac.
    public var detail: String {
        switch request {
        case .clipboardWrite(let text): text
        case .unsafeLink(let uri): uri
        }
    }
}
