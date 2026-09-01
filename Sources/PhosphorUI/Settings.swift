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

    public init(
        themeID: String = BuiltInThemes.phosphor.id,
        language: String = Language.system.rawValue,
        pet: String = Pet.cat.rawValue,
        eggsEnabled: Bool = true
    ) {
        self.themeID = themeID
        self.language = language
        self.pet = pet
        self.eggsEnabled = eggsEnabled
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
