public import Foundation
public import PhosphorCore
public import HostsKit
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
        // Одним заходом: время сервера (чтобы «свежесть» считать по его часам,
        // а не по нашим) и панели каждой сессии с передним процессом.
        let command =
            "command -v tmux >/dev/null 2>&1 && { echo \"NOW $(date +%s)\"; "
            + "tmux list-panes -a -F "
            + "'#{session_name}\t#{pane_active}\t#{pane_current_command}\t"
            + "#{session_windows}\t#{session_attached}\t#{session_activity}' 2>/dev/null; } "
            + "|| true"
        let result = try? await session.run(command)
        liveSessions = Self.parseSessions(result?.stdout ?? "")
    }

    /// Шеллы, при которых сессия считается покоящейся (idle).
    static let shellCommands: Set<String> = [
        "zsh", "-zsh", "bash", "-bash", "sh", "-sh", "fish", "-fish", "dash",
        "tmux", "login", "ksh", "csh", "tcsh",
    ]
    /// Насколько недавней должна быть активность, чтобы сессия считалась рабочей.
    static let workingWindowSeconds = 15

    /// Разбирает вывод `tmux list-sessions` в объекты. Чистая функция —
    /// проверяется на фикстуре, без сервера.
    public static func parseSessions(_ output: String) -> [TmuxSession] {
        var now = 0
        // Строки: `session \t paneActive \t command \t windows \t attached \t activity`.
        // Для каждой сессии берём активную панель — её передний процесс и решает
        // статус. Порядок первого появления сохраняем.
        var order: [String] = []
        var byName: [String: TmuxSession] = [:]
        var activePicked: Set<String> = []

        for rawLine in output.split(separator: "\n") {
            let line = String(rawLine)
            if line.hasPrefix("NOW ") {
                now = Int(line.dropFirst(4).trimmingCharacters(in: .whitespaces)) ?? 0
                continue
            }
            let parts = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
            guard parts.count >= 6, !parts[0].isEmpty else { continue }
            let name = parts[0]
            let isActivePane = parts[1] == "1"
            let command = parts[2]
            let windows = Int(parts[3]) ?? 1
            let attached = parts[4] == "1"
            let activity = Int(parts[5]) ?? 0

            if byName[name] == nil {
                order.append(name)
                byName[name] = TmuxSession(
                    name: name, windows: windows, attached: attached, status: .idle)
            }
            // Статус берём с активной панели; если её не встретили — с первой.
            if isActivePane || !activePicked.contains(name) {
                byName[name]?.status = status(command: command, activity: activity, now: now)
                if isActivePane { activePicked.insert(name) }
            }
        }
        return order.compactMap { byName[$0] }
    }

    /// Эвристика статуса: шелл — покой; чужой процесс с недавней активностью —
    /// работа; он же, но давно молчащий, — вероятно, ждёт ввода.
    static func status(command: String, activity: Int, now: Int) -> AppModel.SessionStatus {
        if shellCommands.contains(command) { return .idle }
        if now > 0, activity > 0, now - activity > workingWindowSeconds { return .blocked }
        return .working
    }

    /// Подключается к выбранной сессии: терминал перезапускается уже внутри неё.
    public func attachSession(_ name: String) {
        guard terminalSession != name else { return }
        terminalSession = name
        if let host = selectedHost { spaceSessions[host] = name }
        screen = .terminal
    }

    /// Делит терминал на две живые панели. Вторая садится в отдельную сессию
    /// на том же хосте (не в ту же, что первая, — иначе это одна и та же лента).
    public func splitTerminal() {
        guard secondSession == nil else { return }
        let primary = terminalSession ?? "main"
        secondSession = primary == "side" ? "side2" : "side"
        screen = .terminal
    }

    /// Убирает вторую панель. tmux-сессия за ней остаётся жить на сервере.
    public func closeSplit() {
        secondSession = nil
    }

    /// Меняет ориентацию сплита: рядом ↔ одна над другой.
    public func flipSplit() {
        splitVertical.toggle()
    }

    /// Переключает фокус на другой спейс (хост). tmux на прежнем хосте
    /// продолжает работать — мы просто отводим от него взгляд.
    public func switchSpace(_ id: ServerHost.ID) {
        guard id != selectedHost, let host = book.hosts.first(where: { $0.id == id }) else { return }
        screen = .terminal
        Task { await connect(to: host) }
    }

    /// Убирает спейс из рейла. Если это текущий — отключаемся от него и
    /// переводим фокус на соседний. Сессии на сервере при этом не трогаются.
    public func closeSpace(_ id: ServerHost.ID) {
        spaces.removeAll { $0 == id }
        spaceSessions[id] = nil
        guard id == selectedHost else { return }
        if let next = spaces.first, let host = book.hosts.first(where: { $0.id == next }) {
            Task { await connect(to: host) }
        } else {
            Task { await disconnect() }
        }
    }

    /// Заводит новую сессию с введённым именем и сразу подключается.
    public func createSession() {
        let name = SSHInvocation.tmuxSessionName(newSessionName) ?? "main"
        newSessionName = ""
        terminalSession = name
        if let host = selectedHost { spaceSessions[host] = name }
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
