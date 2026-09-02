public import Foundation
public import ThemeKit

/// То, что не является секретом и намеренно лежит открытым.
///
/// Темы, язык, питомец — это то, что приятно править руками, класть в git и
/// обменивать. Шифровать такое — вредная привычка, а не безопасность.
public struct Appearance: Codable, Sendable, Equatable {
    public var themeID: String
    public var language: String
    public var pet: String
    public var eggsEnabled: Bool
    /// Размер шрифта, лигатуры и межстрочный интервал.
    public var fontSize: Double
    public var ligatures: Bool
    public var lineHeight: Double
    /// Стекло: сила скан-линий, свечения и виньетки поверх темы.
    ///
    /// Хранится отдельно от темы: тема — общий пресет, который хочется
    /// обменивать, а насколько сильно рябит экран — дело вкуса и монитора.
    public var scanlines: Double?
    public var glow: Double?
    public var vignette: Double?
    /// Поведение: показывать ли питомца, как часто опрашивать сервер и сколько
    /// строк лога держать. Необязательные, чтобы профиль прошлой версии
    /// прочитался без миграции.
    public var petVisible: Bool?
    public var pollSeconds: Double?
    public var logLines: Int?

    public init(
        themeID: String = BuiltInThemes.phosphor.id,
        language: String = Language.system.rawValue,
        pet: String = Pet.cat.rawValue,
        eggsEnabled: Bool = true,
        fontSize: Double = 13,
        ligatures: Bool = true,
        lineHeight: Double = 1.4,
        scanlines: Double? = nil,
        glow: Double? = nil,
        vignette: Double? = nil,
        petVisible: Bool? = nil,
        pollSeconds: Double? = nil,
        logLines: Int? = nil
    ) {
        self.themeID = themeID
        self.language = language
        self.pet = pet
        self.eggsEnabled = eggsEnabled
        self.fontSize = fontSize
        self.ligatures = ligatures
        self.lineHeight = lineHeight
        self.scanlines = scanlines
        self.glow = glow
        self.vignette = vignette
        self.petVisible = petVisible
        self.pollSeconds = pollSeconds
        self.logLines = logLines
    }
}

/// Читает и пишет настройки внешнего вида.
public struct AppearanceStore: Sendable {
    private let url: URL

    public init(url: URL? = nil) {
        self.url = url ?? Self.defaultURL()
    }

    public static func defaultURL() -> URL {
        let base =
            FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first ?? URL(fileURLWithPath: NSHomeDirectory())
        return base.appendingPathComponent("Phosphor/settings.json")
    }

    /// Настройки с диска; при любой беде — значения по умолчанию.
    ///
    /// Испорченный файл настроек не должен мешать запуску: внешний вид не
    /// стоит того, чтобы из-за него не открылось окно.
    public func load() -> Appearance {
        guard let data = try? Data(contentsOf: url),
            let value = try? JSONDecoder().decode(Appearance.self, from: data)
        else { return Appearance() }
        return value
    }

    public func save(_ value: Appearance) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(value) else { return }
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: url, options: .atomic)
    }
}
