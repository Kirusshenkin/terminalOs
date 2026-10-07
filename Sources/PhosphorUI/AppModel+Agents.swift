import Foundation
import PhosphorCore
import SSHKit

/// Выбор нейронки в новой панели (план §23, «Нейронки в панелях»).
@MainActor
extension AppModel {
    /// Ключ `installedAgents` для того, на что смотрит терминал.
    var agentsKey: String? {
        localFocused ? "local" : selectedHost?.uuidString
    }

    /// Какие агенты есть там, куда смотрит терминал. nil — ещё не знаем.
    public var installedHere: Set<String>? {
        agentsKey.flatMap { installedAgents[$0] }
    }

    /// Проверяет, какие агенты стоят на машине. Один раз на машину за запуск:
    /// поставил новый — он появится после перезапуска, а до того его можно
    /// набрать в шелле руками.
    func loadInstalledAgents() async {
        guard let key = agentsKey, installedAgents[key] == nil else { return }
        let command = PaneLaunch.detectionCommand()
        let output: String
        do {
            if localFocused {
                // Интерактивный логин-шелл: npm, nvm и bun прописывают свои пути
                // в `.zshrc`, и без `-i` их агенты были бы «не найдены».
                let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
                output = try await Subprocess.run(
                    executable: shell, arguments: ["-ilc", command], timeout: .seconds(5)
                ).stdout
            } else if let session {
                output = try await session.run(command, timeout: .seconds(10)).stdout
            } else {
                return
            }
        } catch {
            // Не узнали — список остаётся «неизвестно», и все пункты выглядят
            // доступными: незнание не должно прятать агентов. Не найденный
            // шелл честно скажет `command not found` в самой панели.
            return
        }
        installedAgents[key] = PaneLaunch.installed(in: output)
    }

    /// Запускает выбранное в панели. Шелл уже там — его просто показываем.
    /// Агента нет на машине — в шелл вставляется команда установки без Enter.
    public func launch(_ choice: PaneLaunch, in destination: TerminalHost.Destination) {
        pendingLaunch.remove(destination)
        guard let surface = surfaces.existing(destination) else { return }
        surface.window?.makeFirstResponder(surface)
        guard let command = choice.command else { return }
        let missing = installedHere.map { !$0.contains(command) } ?? false
        if missing, let install = choice.install {
            surface.send(txt: install)
            return
        }
        let worktree = agentWorktrees
        Task {
            // Агент стартует в папке панели, из которой открыли новую, — там
            // проект, а не в домашней папке, где открывается свежая панель.
            let origin = await originPath()
            let line = AgentWorktree.launchLine(
                command: command, origin: origin, worktree: worktree, stamp: AgentWorktree.stamp(Date()),
                notice: strings("term.worktree.notice"))
            surface.send(txt: line + "\r")
        }
    }

    /// Папка, в которой стоит основная панель спейса. nil — не узнали:
    /// панель обычного шелла без tmux, или сервер не ответил.
    func originPath() async -> String? {
        let format = Shell.quote("#{pane_current_path}")
        let output: String?
        if localFocused {
            guard let name = localSession, let tmux = localTmuxPath else { return nil }
            output = await LocalTmux.run(
                "\(Shell.quote(tmux)) display-message -p -t \(Shell.quote(name + ":")) \(format) 2>/dev/null")
        } else {
            guard let session else { return nil }
            let name = terminalSession ?? "main"
            // Не узнали — агент стартует там, где открылась панель; это не ошибка.
            output = try? await session.run(
                Shell.withPackagePaths
                    + "tmux display-message -p -t \(Shell.quote(name + ":")) \(format) 2>/dev/null"
            ).stdout
        }
        let path = output?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return path.hasPrefix("/") ? path : nil
    }

    /// Закрывает сессию агента и убирает его копию проекта (план §23).
    public func closeAgentWorktree(_ place: AgentPlace) async {
        let result: Int32?
        switch place {
        case .local(nil):
            result = nil
        case .local(let name?):
            guard let tmux = localTmuxPath else { return }
            let command = AgentWorktree.removeCommand(session: name, tmux: Shell.quote(tmux))
            // Не запустилось — nil, и человек видит «не получилось», а не тишину.
            result = try? await Subprocess.run(executable: "/bin/sh", arguments: ["-c", command]).status
        case .remote(let id, let name):
            let command = Shell.withPackagePaths + AgentWorktree.removeCommand(session: name)
            if id == selectedHost, let session {
                // Обрыв — nil: «не получилось» с советом сделать руками.
                result = try? await session.run(command).status
            } else {
                result = await spaceTransport(for: id)?.runIfConnected(command)?.status
            }
        }
        agentNote =
            switch result.flatMap(AgentWorktree.Removal.init(rawValue:)) {
            case .removed: strings("term.worktree.removed")
            case .missing: strings("term.worktree.none")
            case .dirty: strings("term.worktree.dirty")
            case .failed, nil: strings("term.worktree.failed")
            }
        guard result == AgentWorktree.Removal.removed.rawValue else { return }
        // Сессия уже закрыта; это убирает её панель и строку в рейле тем же
        // путём, что и обычное «снять сессию».
        switch place {
        case .local(let name?): await killLocalSession(name)
        case .remote(let id, let name) where id == selectedHost: await killSession(name)
        case .remote: await loadSpaces()
        case .local(nil): break
        }
    }
}
