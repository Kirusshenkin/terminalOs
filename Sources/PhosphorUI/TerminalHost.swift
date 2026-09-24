import AppKit
public import HostsKit
public import PhosphorCore
public import SwiftUI
public import TerminalCore
public import ThemeKit

/// Puts the real emulator into SwiftUI.
///
/// Вид здесь — пустой контейнер: живёт и переживает его та поверхность, что
/// лежит в `TerminalSurfaces`. Обновление вида только показывает нужную и
/// красит тему.
public struct TerminalHost: NSViewRepresentable {
    /// Куда открывать шелл. Он же ключ поверхности: разные сессии на одном
    /// хосте — это разные ленты, и каждая живёт своей жизнью.
    public enum Destination: Hashable {
        /// Обычный одноразовый шелл на этом Маке: закрыл — и нет его.
        case local
        /// Постоянная сессия на этом Маке: тот же tmux, что и на сервере,
        /// только здесь. Путь к нему часть адреса потому, что он же ключ
        /// поверхности, а ставят tmux один раз и надолго.
        case localSession(name: String, tmux: String)
        case remote(host: ServerHost, reach: Reach, controlPath: String, session: String?)
    }

    private let theme: Theme
    private let surfaces: TerminalSurfaces
    private let destination: Destination
    private let onGuardRequest: (AnsiGuard.Request) -> Void

    public init(
        theme: Theme,
        surfaces: TerminalSurfaces,
        destination: Destination,
        onGuardRequest: @escaping (AnsiGuard.Request) -> Void
    ) {
        self.theme = theme
        self.surfaces = surfaces
        self.destination = destination
        self.onGuardRequest = onGuardRequest
    }

    public func makeNSView(context: Context) -> TerminalSlot {
        let slot = TerminalSlot(frame: .zero)
        // Вход в раздел — единственное место, где мёртвый шелл поднимается
        // заново: человек вернулся и смотрит, значит ждёт приглашения.
        mount(in: slot, reviving: true)
        return slot
    }

    public func updateNSView(_ slot: TerminalSlot, context: Context) {
        // На перерисовке шелл не трогаем: `exit` на той стороне иначе мгновенно
        // подменялся бы новым приглашением, и человек не понял бы, что было.
        mount(in: slot, reviving: false)
    }

    /// Ставит в панель поверхность нужного адреса.
    ///
    /// Смена адреса — это не перезапуск шелла в той же поверхности, а показ
    /// другой: `ssh` за прежней остаётся жив, и возврат к ней отдаёт ленту
    /// такой, какой её оставили.
    private func mount(in slot: TerminalSlot, reviving: Bool) {
        let surface = surfaces.surface(for: destination, start: start)
        surface.apply(theme: theme)
        surface.onGuardRequest = onGuardRequest
        if reviving, !surface.isRunning { start(surface) }
        slot.show(surface)
    }

    private func start(_ surface: TerminalSurface) {
        Self.start(surface, at: destination)
    }

    /// Запускает шелл адреса в поверхности. Один на все пути запуска: первый
    /// показ, возврат в раздел и переподключение по ⇧⌘R.
    static func start(_ surface: TerminalSurface, at destination: Destination) {
        switch destination {
        case .local:
            surface.startLocalShell()
        case .localSession(let name, let tmux):
            surface.startLocalShell(
                tmux: tmux, session: name, environment: LocalTmux.environment())
        case .remote(let host, let reach, let controlPath, let session):
            surface.startRemoteShell(
                host: host, reach: reach, controlPath: controlPath, tmuxSession: session)
        }
    }
}

/// Панель терминала: пустой контейнер, в котором показывается поверхность
/// текущего адреса.
///
/// Контейнер нужен потому, что SwiftUI не даёт подменить NSView после создания:
/// без него панель была бы навсегда привязана к первому шеллу, который в ней
/// открыли.
public final class TerminalSlot: NSView {
    fileprivate func show(_ surface: TerminalSurface) {
        guard surface.superview !== self else { return }
        subviews.forEach { $0.removeFromSuperview() }
        surface.frame = bounds
        surface.autoresizingMask = [.width, .height]
        addSubview(surface)
        window?.makeFirstResponder(surface)
    }
}

/// Живые поверхности терминала — в стороне от жизненного цикла SwiftUI-вида.
///
/// Раздел уходит с экрана — SwiftUI выбрасывает NSView, а с ним и ssh: ушёл на
/// «Докер», вернулся — шелл начался с нуля, и всё, что в нём крутилось, убито.
/// Поэтому поверхности живут здесь и переиспользуются по адресу: сессия, спейс
/// и локальный шелл — каждая со своей лентой, переключение между ними ничего не
/// перезапускает.
@MainActor
public final class TerminalSurfaces {
    private var surfaces: [TerminalHost.Destination: TerminalSurface] = [:]
    /// Порядок последнего показа: при переполнении гаснет самый давний.
    private var recent: [TerminalHost.Destination] = []
    /// Верхняя граница. За каждой поверхностью стоит живой `ssh` и скроллбэк, а
    /// кэш без потолка — это утечка с отложенным сроком. Сессия на сервере при
    /// этом не страдает: tmux продолжает работать, и возврат к ней — новый
    /// attach, а не пустой шелл.
    static let limit = 8

    public init() {}

    /// Поверхность адреса — прежняя, если она уже была, иначе новая и сразу
    /// запущенная. Запуск отдан вызывающему: он один знает, локальный это шелл
    /// или `ssh`.
    fileprivate func surface(
        for destination: TerminalHost.Destination, start: (TerminalSurface) -> Void
    ) -> TerminalSurface {
        touch(destination)
        if let existing = surfaces[destination] { return existing }
        let made = TerminalSurface(frame: .zero)
        surfaces[destination] = made
        start(made)
        evictOverflow()
        return made
    }

    /// Поверхность адреса, если она уже есть. Ничего не создаёт и не запускает.
    public func existing(_ destination: TerminalHost.Destination) -> TerminalSurface? {
        surfaces[destination]
    }

    /// Поднимает шелл в поверхности, если он умер (например, вместе с
    /// соединением). Живой не трогает: в нём может идти работа.
    func reviveIfDead(_ destination: TerminalHost.Destination) {
        guard let surface = surfaces[destination], !surface.isRunning else { return }
        TerminalHost.start(surface, at: destination)
    }

    /// Гасит шелл адреса и забывает поверхность: панель закрыли насовсем, и
    /// оставлять за ней живой ssh без окна незачем.
    public func discard(_ destination: TerminalHost.Destination) {
        surfaces.removeValue(forKey: destination)?.stop()
        recent.removeAll { $0 == destination }
    }

    private func touch(_ destination: TerminalHost.Destination) {
        recent.removeAll { $0 == destination }
        recent.append(destination)
    }

    /// Самые давние поверхности гасим первыми: та, на которую смотрят, всегда
    /// в конце очереди.
    private func evictOverflow() {
        while recent.count > Self.limit, let oldest = recent.first {
            discard(oldest)
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
