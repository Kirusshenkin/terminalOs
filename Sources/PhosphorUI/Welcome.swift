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
    /// Строфа дня: две строки, которые меняются от запуска к запуску.
    public var verse: [String]
    public var footer: String

    /// Сколько всего строф — по нему выбирается индекс снаружи, чтобы
    /// приветствие не тасовалось на каждой перерисовке.
    public static let verseCount = 10

    public init(language: Language, lastLogin: Date? = nil, verseIndex: Int? = nil) {
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

        let index = (verseIndex ?? Int.random(in: 0..<Self.verseCount)) % Self.verseCount
        verse = Self.verses(russian: russian)[index]

        if let lastLogin {
            let formatted = lastLogin.formatted(date: .abbreviated, time: .shortened)
            footer = russian ? "Последний вход: \(formatted)" : "Last login: \(formatted)"
        } else {
            footer = russian ? "Первый вход на этой машине." : "First login on this Mac."
        }
    }

    /// Строфы. Своё, короткое и без пафоса: `motd` на настоящих серверах
    /// всегда был местом, где кто-то оставлял пару строк для следующего.
    ///
    /// Оба языка — самостоятельные наборы, а не перевод друг друга: рифма
    /// не переводится, а смысл строфы держится на ней.
    static func verses(russian: Bool) -> [[String]] {
        russian
            ? [
                ["Ночь на исходе, а лог всё длиннее.", "Кто-то же должен смотреть, как он дышит."],
                ["Зелёный по чёрному — старая вера:", "что видно глазами, то и правда."],
                ["Пароль забывается, ключ остаётся.", "Палец помнит быстрее, чем память."],
                ["Двадцать хостов спят, один не спит.", "Обычно он и есть самый честный."],
                ["Не бойся продакшена — бойся привычки.", "Красная тема придумана ровно для этого."],
                ["Кот в углу знает про сервер больше дашборда:", "там тихо — значит, живой."],
                ["Соединение одно, а окон могло быть пять.", "Четыре из них были про то же самое."],
                ["Пока тянется compose up, остывает чай", "и передумывает человек."],
                ["Скроллбэк не ложится на диск.", "Кое-что должно кончаться вместе с окном."],
                ["Утро проверяется не будильником,", "а тем, что аптайм всё ещё растёт."],
            ]
            : [
                ["The night runs out before the log does.", "Someone has to watch it breathe."],
                ["Green on black is an old faith:", "what the eye can read is what is true."],
                ["Passwords are forgotten, keys remain —", "a finger remembers faster than a mind."],
                ["Twenty hosts asleep, one awake.", "The one awake is usually the honest one."],
                ["Do not fear production. Fear the habit.", "That is what the red theme is for."],
                ["The cat in the corner reads the server better", "than a dashboard: quiet means alive."],
                ["One connection, and five windows were possible.", "Four of them said the same thing."],
                ["While compose is pulling, the tea goes cold", "and a person changes their mind."],
                ["The scrollback never touches the disk.", "Some things should end with the window."],
                ["Morning is not proved by an alarm,", "but by an uptime that still goes up."],
            ]
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
