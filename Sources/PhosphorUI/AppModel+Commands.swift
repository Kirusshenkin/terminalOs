import AppKit
public import HostsKit
import SSHKit
import TerminalCore

/// Действия, за которыми стоят горячие клавиши (см. `PhosphorCommands`).
@MainActor
extension AppModel {
    /// Хост, к которому относятся ⌘E и ⌘⌫: тот, что сейчас открыт.
    public var currentHost: ServerHost? {
        book.hosts.first { $0.id == selectedHost }
    }

    /// Сплит есть только у сессий на сервере: каждая панель — своя tmux-сессия
    /// на том же хосте, а у этого Мака одна лента.
    public var canSplit: Bool {
        session != nil && !localFocused && extraSessions.count + 1 < Self.paneLimit
    }

    /// ⌘T: новая сессия без вопросов об имени — там же, где сейчас смотрим.
    func newSessionFromKeyboard() {
        let taken = Set((localFocused ? localSessions : liveSessions).map(\.name))
        newSessionName = Self.freshSessionName(taken: taken)
        if localFocused || session == nil {
            createLocalSession()
        } else {
            createSession()
        }
    }

    /// Первое свободное имя: `main`, `main2`, `main3`… Чистая функция.
    static func freshSessionName(taken: Set<String>) -> String {
        if !taken.contains("main") { return "main" }
        var index = 2
        while taken.contains("main\(index)") { index += 1 }
        return "main\(index)"
    }

    func split(sideBySide: Bool) {
        splitVertical = sideBySide
        splitTerminal()
    }

    /// Панели по порядку на экране: главная, затем добавленные.
    private var paneDestinations: [TerminalHost.Destination] {
        [terminalDestination] + extraPanes.map(\.destination)
    }

    /// Поверхность, в которой сейчас курсор.
    private var focusedSurface: TerminalSurface? {
        NSApp.keyWindow?.firstResponder as? TerminalSurface
    }

    /// ⌘W: закрывает панель под курсором, а если курсор в главной — последнюю.
    /// Главная не закрывается: без неё вкладке нечего показывать.
    func closeFocusedPane() {
        let focused = focusedSurface
        let pane = extraPanes.first { surfaces.existing($0.destination) === focused }
        closePane(pane?.name ?? extraSessions.last ?? "")
    }

    /// ⌥⌘→ / ⌥⌘←: курсор в соседнюю панель по кругу.
    func focusPane(step: Int) {
        let views = paneDestinations.compactMap { surfaces.existing($0) }
        guard views.count > 1 else { return }
        let current = views.firstIndex { $0 === focusedSurface } ?? 0
        let next = views[(current + step + views.count) % views.count]
        next.window?.makeFirstResponder(next)
    }

    /// ⌘K: как в Terminal.app — история стирается, а шелл по ⌃L сам
    /// перерисовывает приглашение наверху чистого экрана.
    func clearFocusedTerminal() {
        guard let surface = focusedSurface ?? surfaces.existing(terminalDestination) else { return }
        surface.clearScrollback()
        surface.send(txt: "\u{0C}")
    }

    /// Поиск по выводу — полоса поиска самого эмулятора, через цепочку
    /// ответчиков: первым её получает терминал под курсором.
    func terminalFind(_ action: NSTextFinder.Action) {
        let item = NSMenuItem()
        item.tag = action.rawValue
        NSApp.sendAction(#selector(NSResponder.performTextFinderAction(_:)), to: nil, from: item)
    }

    /// Те же пределы, что у ползунка в настройках.
    static let fontSizes = 10.0...20.0
    static let defaultFontSize = 13.0

    func stepFontSize(_ step: Double) {
        fontSize = min(max(fontSize + step, Self.fontSizes.lowerBound), Self.fontSizes.upperBound)
        saveAppearance()
    }

    func resetFontSize() {
        fontSize = Self.defaultFontSize
        saveAppearance()
    }

    /// ⇧⌘R: заново поднимает соединение и шеллы панелей, которые умерли вместе
    /// с ним. Живые не трогаются — в них может идти работа.
    func reconnect() {
        guard let host = currentHost else { return }
        Task {
            await connect(to: host)
            for destination in paneDestinations {
                surfaces.reviveIfDead(destination)
            }
        }
    }
}
