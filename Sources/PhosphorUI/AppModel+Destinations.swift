import HostsKit
import SSHKit

/// Куда смотрят панели терминала: адреса живых поверхностей.
extension AppModel {
    /// Куда смотрит терминал: на этот Мак или на выбранный сервер.
    public var terminalDestination: TerminalHost.Destination {
        if localFocused { return localDestination }
        return destination(session: terminalSession ?? "main") ?? .local
    }

    /// Куда смотрит терминал на этом Маке: в постоянную сессию, если она
    /// выбрана и tmux здесь есть, иначе — обычный одноразовый шелл.
    public var localDestination: TerminalHost.Destination {
        guard persistentSessions, let name = localSession, let tmux = localTmuxPath,
            let safe = SSHInvocation.tmuxSessionName(name)
        else { return .local }
        return .localSession(name: safe, tmux: tmux)
    }

    /// Дополнительные панели с их адресами. Пусто — панель одна.
    ///
    /// У сервера и у этого Мака сплит свой: переключился — видишь панели того,
    /// на что смотришь, а остальные ждут возвращения вместе со своими лентами.
    /// На Маке панели — постоянные сессии здешнего tmux; без tmux у
    /// одноразового шелла одна лента, и делить нечего.
    public var extraPanes: [Pane] {
        guard localFocused else {
            return extraSessions.compactMap { name in
                destination(session: name).map { Pane(name: name, destination: $0) }
            }
        }
        guard persistentSessions, let tmux = localTmuxPath else { return [] }
        return localExtraSessions.compactMap { name in
            SSHInvocation.tmuxSessionName(name).map {
                Pane(name: name, destination: .localSession(name: $0, tmux: tmux))
            }
        }
    }

    /// Адрес названной сессии на выбранном хосте. nil — смотреть не на что:
    /// хост не выбран или соединение к нему ещё не поднято.
    ///
    /// Адрес — он же ключ живой поверхности, поэтому он обязан быть одним и тем
    /// же при каждом обращении: иначе панель показывала бы новый шелл там, где
    /// человек оставил работающий.
    func destination(session name: String) -> TerminalHost.Destination? {
        guard let id = selectedHost,
            let host = book.hosts.first(where: { $0.id == id }),
            let socket = sessionSocketPath
        else { return nil }
        // Постоянные сессии (herdr-стиль): шелл живёт внутри tmux на сервере и
        // переживает закрытие приложения. Выключено — обычный одноразовый шелл.
        return .remote(
            host: host, route: book.route(for: host), controlPath: socket,
            session: persistentSessions ? name : nil)
    }
}
