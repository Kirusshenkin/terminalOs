public import Foundation

/// Раскладка раздела «Терминал» — то, что было открыто, когда приложение
/// закрыли.
///
/// Смысл прямой: tmux на сервере переживает перезапуск приложения, а вид на
/// него — нет. Без этой записи после перезапуска человек видел пустой рейл и
/// должен был вручную вспоминать, какие спейсы и сессии у него были открыты,
/// хотя всё это продолжало работать на серверах.
///
/// Секретов здесь нет: идентификаторы хостов и имена tmux-сессий. Адреса,
/// логины и ключи живут в зашифрованном профиле и сюда не попадают.
public struct TerminalLayout: Codable, Sendable, Equatable {
    /// Спейсы — хосты в том порядке, в каком их открывали.
    public var spaces: [UUID]
    /// Какая сессия была открыта в каждом спейсе. Ключ — идентификатор хоста
    /// строкой: JSON не умеет ключей-объектов.
    public var spaceSessions: [String: String]
    /// На какой спейс смотрели последним — туда и возвращаемся.
    public var focused: UUID?
    /// Сессия основной панели.
    public var session: String?
    /// Вторая панель — как её писала прошлая версия. Оставлено ради файлов,
    /// записанных до того, как панелей стало больше двух: новое поле `panes`
    /// главнее, а это читается, когда его нет.
    public var secondSession: String?
    /// Дополнительные панели в порядке появления.
    public var panes: [String]?
    /// Панели рядом (true) или одна над другой.
    public var splitVertical: Bool
    /// Сессия на этом Маке и то, смотрел ли терминал на него, а не на сервер.
    /// Необязательные: раскладка прошлой версии должна читаться как есть, а не
    /// теряться целиком из-за нового поля.
    public var localSession: String?
    public var localFocused: Bool?
    /// Доля главной панели, если её двигали мышью.
    public var splitRatio: Double?

    public init(
        spaces: [UUID] = [],
        spaceSessions: [String: String] = [:],
        focused: UUID? = nil,
        session: String? = nil,
        secondSession: String? = nil,
        splitVertical: Bool = true,
        panes: [String]? = nil,
        localSession: String? = nil,
        localFocused: Bool? = nil,
        splitRatio: Double? = nil
    ) {
        self.spaces = spaces
        self.spaceSessions = spaceSessions
        self.focused = focused
        self.session = session
        self.secondSession = secondSession
        self.splitVertical = splitVertical
        self.panes = panes
        self.localSession = localSession
        self.localFocused = localFocused
        self.splitRatio = splitRatio
    }

    /// Та же раскладка, но без хостов, которых больше нет в списке.
    ///
    /// Хост удалили, пока приложение было закрыто, — и в рейле висел бы спейс,
    /// ведущий в никуда: клик по нему не мог бы ни подключиться, ни объяснить
    /// почему. Чистая функция, поэтому проверяется без диска.
    public func keeping(hosts known: Set<UUID>) -> TerminalLayout {
        var result = self
        result.spaces = spaces.filter { known.contains($0) }
        result.spaceSessions = spaceSessions.filter { rawID, _ in
            UUID(uuidString: rawID).map { known.contains($0) } ?? false
        }
        result.focused = focused.flatMap { known.contains($0) ? $0 : nil }
        return result
    }
}

/// Читает и пишет раскладку терминала.
///
/// Отдельно от `AppearanceStore` намеренно: внешний вид — это вкус, а
/// раскладка — рабочее состояние, и ломается оно по-разному. Испорченный файл
/// не должен мешать запуску, поэтому при любой беде — пустая раскладка.
public struct TerminalLayoutStore: Sendable {
    private let url: URL

    public init(url: URL? = nil) {
        self.url = url ?? Self.defaultURL()
    }

    public static func defaultURL() -> URL {
        let base =
            FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first ?? URL(fileURLWithPath: NSHomeDirectory())
        return base.appendingPathComponent("Phosphor/terminal.json")
    }

    public func load() -> TerminalLayout {
        guard let data = try? Data(contentsOf: url),
            let value = try? JSONDecoder().decode(TerminalLayout.self, from: data)
        else { return TerminalLayout() }
        return value
    }

    public func save(_ value: TerminalLayout) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(value) else { return }
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: url, options: .atomic)
    }
}
