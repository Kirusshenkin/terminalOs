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
    ]
}
