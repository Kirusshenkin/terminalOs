import AppKit
import SSHKit

/// Проект на этом Маке: в какой папке открываются локальные сессии (план §23).
///
/// Без него шелл открывался в `/` — там macOS запускает приложение, — и агент
/// из строки выбора сидел там же, хотя его песочница даёт писать именно в
/// текущую папку.
extension AppModel {
    /// Папка проекта, в которой сейчас работают на этом Маке. nil — не выбрана:
    /// шелл в домашней папке.
    public var localProject: String? {
        guard let name = localSession, persistentSessions, localTmuxPath != nil else {
            return plainShellDirectory
        }
        return localDirectories[name]
    }

    /// Обычный шелл этого Мака в его папке.
    var plainShellDestination: TerminalHost.Destination {
        .local(directory: plainShellDirectory)
    }

    /// Переводит работу на этом Маке в проект.
    ///
    /// С постоянными сессиями — открывает сессию проекта (её имя — имя папки),
    /// заводя её при надобности. Без них перезапускает обычный шелл в этой
    /// папке: он одноразовый и ничего не обещает.
    public func openProject(_ path: String) {
        recentProjects = LocalProjects.remember(path, in: recentProjects)
        guard persistentSessions, localTmuxPath != nil else {
            if plainShellDirectory != path {
                surfaces.discard(plainShellDestination)
                plainShellDirectory = path
            }
            focusLocal(nil)
            return
        }
        let live = Set(localSessions.map(\.name))
        let name = LocalProjects.sessionName(for: path, directories: localDirectories, live: live)
        localDirectories[name] = path
        if !live.contains(name) {
            localSessions.append(TmuxSession(name: name, windows: 1, attached: true))
        }
        focusLocal(name)
    }

    /// Спрашивает папку системным окном и открывает её как проект.
    public func chooseProjectFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = strings("term.project.open")
        if let current = localProject { panel.directoryURL = URL(fileURLWithPath: current) }
        guard panel.runModal() == .OK, let url = panel.url else { return }
        openProject(url.path)
    }
}

/// Чистые правила проектов этого Мака — проверяются тестами без окна и tmux.
enum LocalProjects {
    /// Сколько последних проектов помнить.
    static let recentLimit = 8

    /// Список последних проектов с этим наверху: без повторов, не длиннее
    /// `limit`.
    static func remember(_ path: String, in recent: [String], limit: Int = recentLimit) -> [String] {
        Array(([path] + recent.filter { $0 != path }).prefix(limit))
    }

    /// Имя tmux-сессии для проекта: имя папки. Уже есть сессия с этим именем
    /// в этой же папке — она и есть сессия проекта. Имя занято живой сессией
    /// из другой папки (или из неизвестной) — `имя-2`, `имя-3`… Папка
    /// снятой сессии имя не держит.
    static func sessionName(for path: String, directories: [String: String], live: Set<String>) -> String {
        let base = SSHInvocation.tmuxSessionName((path as NSString).lastPathComponent) ?? "project"
        var index = 1
        while true {
            let name = index == 1 ? base : "\(base)-\(index)"
            if directories[name] == path || !live.contains(name) { return name }
            index += 1
        }
    }

    /// Путь для глаз: домашняя папка — `~`. Чистая функция.
    static func display(_ path: String, home: String = NSHomeDirectory()) -> String {
        if path == home { return "~" }
        if path.hasPrefix(home + "/") { return "~" + path.dropFirst(home.count) }
        return path
    }
}
