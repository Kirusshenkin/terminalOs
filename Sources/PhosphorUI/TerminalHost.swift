import AppKit
public import PhosphorCore
public import SwiftUI
public import TerminalCore
public import ThemeKit

/// Puts the real emulator into SwiftUI.
///
/// The view is created once and kept: rebuilding it would throw away the shell
/// and everything on screen. Only the theme is pushed on update.
public struct TerminalHost: NSViewRepresentable {
    private let theme: Theme
    private let onGuardRequest: (AnsiGuard.Request) -> Void

    public init(theme: Theme, onGuardRequest: @escaping (AnsiGuard.Request) -> Void) {
        self.theme = theme
        self.onGuardRequest = onGuardRequest
    }

    public func makeNSView(context: Context) -> TerminalSurface {
        let surface = TerminalSurface(frame: .zero)
        surface.apply(theme: theme)
        surface.onGuardRequest = onGuardRequest
        surface.startLocalShell()
        return surface
    }

    public func updateNSView(_ surface: TerminalSurface, context: Context) {
        surface.apply(theme: theme)
        surface.onGuardRequest = onGuardRequest
    }
}

/// What the terminal wants a person to decide before it happens.
public struct GuardPrompt: Identifiable, Sendable {
    public var id = UUID()
    public var request: AnsiGuard.Request

    public var title: String {
        switch request {
        case .clipboardWrite: "сервер хочет записать в буфер обмена"
        case .unsafeLink: "ссылка с необычной схемой"
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
