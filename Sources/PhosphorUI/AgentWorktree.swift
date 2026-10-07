import Foundation
import PhosphorCore

/// Своя копия проекта для каждого агента (план §23).
///
/// Два агента в одной папке ломают друг другу сборку и затирают правки —
/// проверено на себе. Поэтому агент, запущенный из строки выбора в
/// git-репозитории, получает свой `git worktree` на новой ветке рядом с
/// репозиторием. Всё делает видимая команда в самой панели: человек видит,
/// куда агента посадили, и может повторить это руками.
enum AgentWorktree {
    /// Опция tmux-сессии, в которой лежит путь копии: по ней «закрыть и
    /// убрать» находит, что убирать, без своего учёта на стороне приложения.
    static let option = "@phosphor_worktree"

    /// Строка, которую панель получает вместо голого имени агента. Чистая функция.
    ///
    /// - Parameters:
    ///   - origin: папка панели, из которой открыли новую; nil — не знаем,
    ///     агент стартует там, где открылась панель.
    ///   - worktree: заводить ли копию, если папка в git-репозитории.
    static func launchLine(command: String, origin: String?, worktree: Bool, stamp: String) -> String {
        var parts: [String] = []
        if let origin { parts.append("cd \(Shell.quote(origin))") }
        if worktree {
            let suffix = "\(command)-\(stamp)"
            // Не репозиторий или git не смог — агент просто стартует здесь:
            // копия — удобство, а не условие запуска.
            parts.append(
                "r=$(git rev-parse --show-toplevel 2>/dev/null) && w=\"$r-\(suffix)\" "
                    + "&& git -C \"$r\" worktree add -q -b \(Shell.quote("agent/" + suffix)) \"$w\" && cd \"$w\" "
                    + "&& { tmux set-option \(option) \"$w\" 2>/dev/null; true; }")
        }
        parts.append(command)
        return parts.joined(separator: "; ")
    }

    /// Метка времени для имени копии и ветки: `0408-153012`. Чистая функция.
    static func stamp(_ date: Date, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.month, .day, .hour, .minute, .second], from: date)
        return String(
            format: "%02d%02d-%02d%02d%02d", parts.month ?? 0, parts.day ?? 0, parts.hour ?? 0,
            parts.minute ?? 0,
            parts.second ?? 0)
    }

    /// Чем кончилась попытка убрать копию.
    enum Removal: Int32, Equatable {
        case removed = 0
        /// У сессии нет своей копии — запускали без неё.
        case missing = 3
        /// В копии есть незакоммиченное: убирать нельзя, иначе потеряется работа.
        case dirty = 4
        /// git отказался по своей причине.
        case failed = 5
    }

    /// Закрывает сессию и убирает её копию — только если в копии нет
    /// незакоммиченного. Ветка остаётся: слить или выбросить её — решение
    /// человека. Чистая функция.
    static func removeCommand(session: String, tmux: String = "tmux") -> String {
        let target = Shell.quote(session + ":")
        return "w=$(\(tmux) show-options -qv -t \(target) \(option)); [ -n \"$w\" ] || exit 3; "
            + "[ -z \"$(git -C \"$w\" status --porcelain 2>/dev/null)\" ] || exit 4; "
            + "\(tmux) kill-session -t \(target) 2>/dev/null; "
            // Убирает основной репозиторий, а не сама копия: изнутри себя git
            // рабочее дерево не удаляет.
            + "m=$(git -C \"$w\" rev-parse --path-format=absolute --git-common-dir) || exit 5; "
            + "git --git-dir=\"$m\" worktree remove \"$w\" || exit 5"
    }
}
