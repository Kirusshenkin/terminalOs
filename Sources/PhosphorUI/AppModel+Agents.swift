import Foundation
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
        if let command = choice.command {
            let missing = installedHere.map { !$0.contains(command) } ?? false
            if missing, let install = choice.install {
                surface.send(txt: install)
            } else {
                surface.send(txt: command + "\r")
            }
        }
        surface.window?.makeFirstResponder(surface)
    }
}
