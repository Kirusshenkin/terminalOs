import Foundation
import PhosphorCore

/// Песочница для агента, запущенного из строки выбора на этом Маке (план §16.9).
///
/// Так же, как Claude Code держит свои команды под Seatbelt: агент читает
/// почти всё, а пишет только в свой проект, во временные папки и в папки
/// своих настроек. Обманутый строкой из лога агент не прочитает `~/.ssh` и
/// не перепишет `~/.zshrc`. Всё здесь — чистые функции: профиль и строка
/// запуска проверяются тестом на настоящем `sandbox-exec`.
enum AgentSandbox {
    /// Куда в домашней папке агентам нужно писать: их настройки, вход, кэш,
    /// автообновление. Сравнение по началу пути: `.claude` покрывает и
    /// `~/.claude/`, и `~/.claude.json` рядом.
    static let writableInHome = [
        ".claude", ".codex", ".gemini", ".cursor", ".opencode", ".config", ".local", ".cache", ".npm",
        ".bun", "Library/Caches", "Library/Logs",
    ]

    /// Что агенту не нужно и что дороже всего отдать: ключи SSH и прочие
    /// ключи доступа. Закрыто и на чтение, и на запись — даже если проект
    /// лежит выше по дереву.
    static let hiddenInHome = [".ssh", ".gnupg", ".aws"]

    /// Временные папки macOS; `/tmp` и `$TMPDIR` — ссылки сюда.
    static let scratch = ["/private/tmp", "/private/var/folders"]

    /// Профиль Seatbelt. Пути проекта и дома приходят параметрами при запуске,
    /// поэтому профиль один на всех агентов. Порядок важен: в Seatbelt
    /// побеждает последнее подходящее правило, и запрет на ключи стоит в
    /// конце, чтобы проект в домашней папке не открыл `~/.ssh`.
    ///
    /// - Parameter scratch: временные папки; тест подставляет пустой список,
    ///   потому что его фикстуры сами лежат во временной папке.
    static func profile(scratch: [String] = scratch) -> String {
        let home = { (path: String) in "(string-append (param \"HOME\") \"/\(path)\")" }
        var writable = ["(subpath (param \"ROOT\"))", "(subpath (param \"GIT\"))", "(subpath \"/dev\")"]
        writable += scratch.map { "(subpath \"\($0)\")" }
        writable += writableInHome.map { "(prefix \(home($0)))" }
        let hidden = hiddenInHome.map { "(subpath \(home($0)))" }
        return """
            (version 1)
            (allow default)
            (deny file-write*)
            (allow file-write*
              \(writable.joined(separator: "\n  ")))
            (deny file-read* file-write*
              \(hidden.joined(separator: "\n  ")))

            """
    }

    /// Строка, которая запускает агента под профилем. Проект — текущая папка
    /// (панель уже переехала в копию проекта), плюс общая `.git` репозитория:
    /// коммит из копии пишет туда. Пути — настоящие, без ссылок: Seatbelt
    /// сравнивает именно их, а `/tmp` — это `/private/tmp`. Чистая функция.
    ///
    /// - Parameters:
    ///   - start: чем агент запускается без песочницы.
    ///   - profilePath: где лежит профиль.
    static func wrap(_ start: String, profilePath: String) -> String {
        "_pg=$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null) && _pg=$(realpath \"$_pg\") "
            + "|| _pg=$(pwd -P); sandbox-exec -f \(Shell.quote(profilePath)) -D HOME=\"$(realpath \"$HOME\")\" "
            + "-D ROOT=\"$(pwd -P)\" -D GIT=\"$_pg\" /bin/sh -c \(Shell.quote(start))"
    }

    /// Где лежит профиль: рядом с остальными файлами приложения.
    static var profileURL: URL {
        let base =
            FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory() + "/Library/Application Support")
        return base.appendingPathComponent("Phosphor/agent-sandbox.sb")
    }

    /// Кладёт профиль на диск. Пишется при каждом запуске: так файл всегда
    /// совпадает с тем, что в этой версии приложения.
    static func installProfile(at url: URL = profileURL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(profile().utf8).write(to: url, options: .atomic)
    }
}
