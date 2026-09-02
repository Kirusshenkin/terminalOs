public import Foundation

/// Приветствие, которое открывает развёртка экрана.
///
/// Сделано как `motd` на сервере — жанр, который тут к месту: короткая шапка,
/// обращение по имени и несколько строк по делу. До разблокировки профиль ещё
/// не прочитан, поэтому цифр из него здесь нет и быть не может.
public struct Welcome: Sendable {
    public var title: String
    public var greeting: String
    public var lines: [String]
    public var footer: String

    public init(language: Language, lastLogin: Date? = nil) {
        let version =
            Bundle.main
            .object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        let russian = language == .russian

        title = "Phosphor \(version) (darwin arm64)"

        let name =
            NSFullUserName().split(separator: " ").first.map(String.init)
            ?? NSUserName()
        greeting =
            russian
            ? "\(Self.timeOfDay(russian: true)), \(name)."
            : "\(Self.timeOfDay(russian: false)), \(name)."

        lines =
            russian
            ? [
                "Профиль расшифрован, ключи на месте.",
                "",
                "  хосты, ключи и пробросы — в разделе «Хосты»",
                "  терминал открывает шелл по тому же соединению",
                "  питомец в углу спит, пока ты работаешь",
            ]
            : [
                "Profile decrypted, keys in place.",
                "",
                "  hosts, keys and forwards live under “Hosts”",
                "  the terminal opens a shell over the same connection",
                "  the pet in the corner sleeps while you work",
            ]

        if let lastLogin {
            let formatted = lastLogin.formatted(date: .abbreviated, time: .shortened)
            footer = russian ? "Последний вход: \(formatted)" : "Last login: \(formatted)"
        } else {
            footer = russian ? "Первый вход на этой машине." : "First login on this Mac."
        }
    }

    /// Время суток по часам — мелочь, от которой приветствие перестаёт быть
    /// одинаковым каждый раз.
    private static func timeOfDay(russian: Bool) -> String {
        switch Calendar.current.component(.hour, from: Date()) {
        case 5..<12: russian ? "Доброе утро" : "Good morning"
        case 12..<18: russian ? "Добрый день" : "Good afternoon"
        case 18..<23: russian ? "Добрый вечер" : "Good evening"
        default: russian ? "Доброй ночи" : "Good night"
        }
    }
}
