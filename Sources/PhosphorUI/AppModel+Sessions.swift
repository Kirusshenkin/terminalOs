public import Foundation
public import PhosphorCore
public import SSHKit

/// Постоянные tmux-сессии на сервере: список, подключение, создание, снятие.
///
/// tmux — это и есть «сервер, который всё время работает»: шелл живёт внутри
/// него на хосте, а приложение лишь подключается к живой сессии и отключается,
/// ничего не убивая. Закрыл ноутбук, потерял сеть — сессия и всё, что в ней
/// запущено (сборка, агент, лог), продолжают идти.
@MainActor
extension AppModel {
    /// Читает живые сессии выбранного хоста. Пустой список — не ошибка: значит
    /// сессий ещё нет либо tmux на сервере не установлен.
    public func loadSessions() async {
        guard let session else {
            liveSessions = []
            return
        }
        // Формат разбирается однозначно: имя, число окон, признак подключения.
        let command =
            "command -v tmux >/dev/null 2>&1 && "
            + "tmux list-sessions -F '#{session_name}\t#{session_windows}\t#{session_attached}' "
            + "2>/dev/null || true"
        let result = try? await session.run(command)
        liveSessions = Self.parseSessions(result?.stdout ?? "")
    }

    /// Разбирает вывод `tmux list-sessions` в объекты. Чистая функция —
    /// проверяется на фикстуре, без сервера.
    public static func parseSessions(_ output: String) -> [TmuxSession] {
        output.split(separator: "\n").compactMap { line in
            let parts = line.split(separator: "\t", omittingEmptySubsequences: false)
            guard parts.count >= 3, !parts[0].isEmpty else { return nil }
            return TmuxSession(
                name: String(parts[0]),
                windows: Int(parts[1]) ?? 1,
                attached: parts[2] == "1"
            )
        }
    }

    /// Подключается к выбранной сессии: терминал перезапускается уже внутри неё.
    public func attachSession(_ name: String) {
        guard terminalSession != name else { return }
        terminalSession = name
        screen = .terminal
    }

    /// Заводит новую сессию с введённым именем и сразу подключается.
    public func createSession() {
        let name = SSHInvocation.tmuxSessionName(newSessionName) ?? "main"
        newSessionName = ""
        terminalSession = name
        screen = .terminal
        // Список обновится по факту подключения; но покажем её сразу, чтобы рейл
        // не выглядел пустым, пока идёт attach.
        if !liveSessions.contains(where: { $0.name == name }) {
            liveSessions.append(TmuxSession(name: name, windows: 1, attached: true))
        }
    }

    /// Снимает сессию на сервере целиком — вместе со всем, что в ней запущено.
    /// Поэтому это делают явной кнопкой, а не мимоходом.
    public func killSession(_ name: String) async {
        guard let session else { return }
        _ = try? await session.run("tmux kill-session -t \(Shell.quote(name)) 2>/dev/null || true")
        if terminalSession == name { terminalSession = nil }
        await loadSessions()
    }
}
