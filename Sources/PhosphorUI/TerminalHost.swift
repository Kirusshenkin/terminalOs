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
    private let surfaces: TerminalSurfaces
    private let slot: TerminalSurfaces.Slot
    private let destination: Destination
    private let onGuardRequest: (AnsiGuard.Request) -> Void

    public init(
        theme: Theme,
        surfaces: TerminalSurfaces,
        slot: TerminalSurfaces.Slot,
        destination: Destination,
        onGuardRequest: @escaping (AnsiGuard.Request) -> Void
    ) {
        self.theme = theme
        self.surfaces = surfaces
        self.slot = slot
        self.destination = destination
        self.onGuardRequest = onGuardRequest
    }

    /// Берём поверхность слота, а не создаём новую: раздел уходит с экрана —
    /// SwiftUI выбрасывает вид, и вместе с ним умер бы шелл. Шелл запускаем
    /// только если его там нет: либо сменился адрес, либо прошлый завершился
    /// сам (`exit` на той стороне).
    public func makeNSView(context: Context) -> TerminalSurface {
        let (surface, moved) = surfaces.surface(for: slot, destination: destination)
        surface.apply(theme: theme)
        surface.onGuardRequest = onGuardRequest
        if moved || !surface.isRunning { start(surface) }
        return surface
    }

    public func updateNSView(_ surface: TerminalSurface, context: Context) {
        surface.apply(theme: theme)
        surface.onGuardRequest = onGuardRequest
        // Перезапускаем шелл, только если сменился адрес: пересоздавать его на
        // каждой перерисовке значит выбрасывать всё, что на экране. Умерший
        // шелл здесь не воскрешаем — иначе `exit` мгновенно подменялся бы
        // новым приглашением, и человек не понял бы, что произошло.
        let (_, moved) = surfaces.surface(for: slot, destination: destination)
        if moved { start(surface) }
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

/// Живые поверхности терминала — в стороне от жизненного цикла SwiftUI-вида.
///
/// Раздел уходит с экрана — SwiftUI выбрасывает NSView, а с ним и ssh: ушёл на
/// «Докер», вернулся — шелл начался с нуля, и всё, что в нём крутилось, убито.
/// Поэтому поверхности живут здесь и переиспользуются по слоту. Слотов ровно
/// столько, сколько панелей на экране, — это и есть верхняя граница.
@MainActor
public final class TerminalSurfaces {
    /// Какая из панелей: одна основная и одна во втором окне сплита.
    public enum Slot: Hashable { case primary, second }

    private var surfaces: [Slot: TerminalSurface] = [:]
    private var destinations: [Slot: TerminalHost.Destination] = [:]

    public init() {}

    /// Поверхность слота — прежняя, если она уже была. Второе значение говорит,
    /// что адрес сменился и шелл надо поднимать заново.
    fileprivate func surface(
        for slot: Slot, destination: TerminalHost.Destination
    ) -> (surface: TerminalSurface, moved: Bool) {
        let moved = destinations[slot] != destination
        destinations[slot] = destination
        if let existing = surfaces[slot] { return (existing, moved) }
        let made = TerminalSurface(frame: .zero)
        surfaces[slot] = made
        return (made, true)
    }

    /// Гасит шелл слота и забывает поверхность: панель закрыли насовсем, и
    /// оставлять за ней живой ssh без окна незачем.
    public func discard(_ slot: Slot) {
        surfaces.removeValue(forKey: slot)?.stop()
        destinations[slot] = nil
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
