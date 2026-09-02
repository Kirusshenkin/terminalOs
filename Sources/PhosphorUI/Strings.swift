public import Foundation

/// Interface language. Both are first class; the default follows the system.
public enum Language: String, CaseIterable, Sendable {
    case russian = "ru"
    case english = "en"

    public var title: String {
        switch self {
        case .russian: "Русский"
        case .english: "English"
        }
    }

    /// Best match for the user's system preference.
    public static var system: Language {
        let preferred = Locale.preferredLanguages.first ?? "en"
        return preferred.hasPrefix("ru") ? .russian : .english
    }
}

/// Every string the interface shows.
///
/// Keys are English; nothing is hard-coded in a view. Keeping the table in one
/// place also keeps the two languages honest — a missing translation is visible
/// here rather than at runtime.
public struct Strings: Sendable {
    public var language: Language

    public init(language: Language = .system) { self.language = language }

    public func callAsFunction(_ key: String) -> String {
        Self.table[key]?[language] ?? key
    }

    /// Имя встроенной темы на языке интерфейса.
    ///
    /// У импортированных тем имя своё — его придумал не мы, и переводить его
    /// нечем и незачем.
    public func themeName(id: String, fallback: String) -> String {
        Self.table["theme.\(id)"]?[language] ?? fallback
    }

}
