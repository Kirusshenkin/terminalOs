import Foundation

/// Подписи выбора нейронки в новой панели терминала (план §23).
extension Strings {
    static let agentTable: [String: [Language: String]] = [
        "term.launch": [.russian: "что запустить в этой панели", .english: "what to run in this pane"],
        "term.shell": [.russian: "шелл", .english: "shell"],
        "term.launchHint": [
            .russian: "Tab — дальше · Enter — запустить · Esc — просто шелл",
            .english: "Tab — next · Enter — run · Esc — just the shell",
        ],
        "term.launchMissing": [
            .russian: "На этой машине его нет: Enter вставит команду установки, запустить её — тебе.",
            .english: "Not installed here: Enter types the install command, running it is up to you.",
        ],
        "term.reply.accept": [.russian: "принять", .english: "accept"],
        "term.reply.text": [.russian: "ответить…", .english: "reply…"],
        "term.reply.placeholder": [.russian: "текст и Enter", .english: "text, then Enter"],
        "term.reply.failed": [
            .russian: "Не дошло: канала к серверу нет или tmux не ответил. Открой сессию и ответь в ней.",
            .english:
                "Did not go through: no channel to the server, or tmux did not answer. Open the session "
                + "and answer there.",
        ],
        "term.reply.decline": [.russian: "Esc — отказаться", .english: "Esc — decline"],
        "term.reply.acceptAction": [.russian: "Enter — принять", .english: "Enter — accept"],
        "term.reply.textAction": [.russian: "Ответить…", .english: "Reply…"],
        "term.reply.send": [.russian: "Отправить", .english: "Send"],
        "term.worktree.close": [
            .russian: "закрыть и убрать копию проекта", .english: "close and remove its project copy",
        ],
        "term.worktree.removed": [
            .russian: "Сессия закрыта, копия проекта убрана. Ветка agent/… осталась — слей или удали её сам.",
            .english:
                "Session closed, project copy removed. The agent/… branch stays — merge or delete it yourself.",
        ],
        "term.worktree.none": [
            .russian: "У этой сессии нет своей копии проекта: агент запущен в общей папке.",
            .english: "This session has no project copy of its own: the agent runs in the shared folder.",
        ],
        "term.worktree.dirty": [
            .russian:
                "В копии есть незакоммиченные правки — ничего не тронуто. Закоммить их или убери копию руками.",
            .english:
                "The copy has uncommitted changes — nothing was touched. Commit them or remove the copy by hand.",
        ],
        "term.worktree.failed": [
            .russian:
                "Не получилось: нет связи с машиной или git отказал. Убери копию руками: git worktree remove.",
            .english:
                "Did not work: no connection to the machine, or git refused. Remove it by hand: git worktree "
                + "remove.",
        ],
        "set.agentWorktrees": [
            .russian: "своя копия проекта для агента", .english: "own project copy per agent",
        ],
        "set.agentWorktreesNote": [
            .russian:
                "Агент из строки выбора в git-репозитории работает в своём git worktree на ветке agent/…, "
                + "рядом с проектом: два агента не мешают друг другу.",
            .english:
                "An agent started from the picker inside a git repository works in its own git worktree on an "
                + "agent/… branch next to the project: two agents do not get in each other's way.",
        ],
    ]
}
