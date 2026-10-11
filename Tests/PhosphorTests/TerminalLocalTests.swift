import Foundation
import Testing

@testable import PhosphorUI

@Suite("Локальные постоянные сессии")
struct TerminalLocalTests {
    @Test("команда опроса спрашивает именно тот tmux, который нашли")
    @MainActor func pollCommand() {
        let command = AppModel.pollCommand(tmux: "/opt/homebrew/bin/tmux")
        #expect(command.contains("command -v /opt/homebrew/bin/tmux"))
        #expect(command.contains("/opt/homebrew/bin/tmux -u list-panes -a"))
        // Разделы и маркер отсутствия tmux — договор с разборщиком.
        #expect(command.contains("echo \(AppModel.panesMarker)"))
        #expect(command.contains("echo \(AppModel.procsMarker)"))
        #expect(command.contains("echo \(AppModel.noTmuxMarker)"))
        // Список передних процессов ограничен сверху.
        #expect(command.contains("head -\(AppModel.foregroundLimit)"))
    }

    @Test("окружение локального шелла годится для эмулятора")
    func environment() {
        let values = LocalTmux.environment()
        #expect(values.contains("TERM=xterm-256color"))
        #expect(values.contains { $0.hasPrefix("LANG=") })
        // Переменные службы из бандла в шелле означали бы не то, что означают.
        #expect(!values.contains { $0.hasPrefix("XPC_SERVICE_NAME=") })
    }

    @Test("ответ, снятый с настоящего Мака, разбирается целиком")
    @MainActor func macOSShapedOutput() {
        // Фикстура в том виде, в каком её печатает /bin/sh на macOS: терминалы
        // зовутся ttysNNN, поля `ps` разделены несколькими пробелами.
        let output = """
            NOW 1700000000
            PANES
            agent\t1\tnode\t1\t1\t1700000000\t/dev/ttys004
            shell\t1\tzsh\t2\t0\t1699999000\t/dev/ttys005
            PROCS
            ttys004  S+   node /opt/agents/@anthropic-ai/claude-code/cli.js
            ttys004  S+   rg --json pattern
            ttys005  Ss+  -zsh
            """
        let sessions = AppModel.parseSessions(output)
        #expect(sessions.count == 2)
        #expect(sessions[0].name == "agent" && sessions[0].agent?.id == "claude")
        #expect(sessions[0].status == .working)
        #expect(sessions[1].name == "shell" && sessions[1].agent == nil)
        #expect(sessions[1].status == .idle)
    }

    @Test("tmux ищется фактом: нашли — значит файл есть и он исполняемый")
    func find() {
        guard let path = LocalTmux.find() else { return }
        #expect(FileManager.default.isExecutableFile(atPath: path))
    }

    @Test("пустой вывод даёт пустой список сессий")
    @MainActor func emptyOutput() {
        let sessions = AppModel.parseSessions("")
        #expect(sessions.isEmpty)
    }

    @Test("вывод с только NOW маркером")
    @MainActor func onlyNowMarker() {
        let output = "NOW 1700000000"
        let sessions = AppModel.parseSessions(output)
        #expect(sessions.isEmpty)
    }

    @Test("сессия с кириллицей в имени разбирается")
    @MainActor func cyrilicSessionName() {
        let output = """
            NOW 1700000000
            PANES
            тест\t1\tzsh\t1\t1\t1700000000\t/dev/ttys004
            PROCS
            """
        let sessions = AppModel.parseSessions(output)
        #expect(sessions.count == 1)
        #expect(sessions[0].name == "тест")
    }

    @Test("очень длинное имя сессии")
    @MainActor func veryLongSessionName() {
        let longName = String(repeating: "a", count: 500)
        let output = """
            NOW 1700000000
            PANES
            \(longName)\t1\tzsh\t1\t1\t1700000000\t/dev/ttys004
            PROCS
            """
        let sessions = AppModel.parseSessions(output)
        #expect(sessions.count == 1)
        #expect(sessions[0].name == longName)
    }

    @Test("пане без TTY разбирается (поле TTY отсутствует)")
    @MainActor func panWithoutTTY() {
        let output = """
            NOW 1700000000
            PANES
            work\t1\tzsh\t1\t1\t1700000000
            PROCS
            """
        let sessions = AppModel.parseSessions(output)
        #expect(sessions.count == 1)
    }

    @Test("активная и неактивная панели в одной сессии")
    @MainActor func activeAndInactivePanes() {
        let output = """
            NOW 1700000000
            PANES
            multi\t1\tzsh\t2\t1\t1700000000\t/dev/ttys004
            multi\t0\tzsh\t2\t1\t1699999000\t/dev/ttys005
            PROCS
            """
        let sessions = AppModel.parseSessions(output)
        #expect(sessions.count == 1)
        #expect(sessions[0].name == "multi")
    }

    @Test("команда с кириллицей")
    @MainActor func cyrillicCommand() {
        let output = """
            NOW 1700000000
            PANES
            тест\t1\tпредложение\t1\t1\t1700000000\t/dev/ttys004
            PROCS
            """
        let sessions = AppModel.parseSessions(output)
        #expect(sessions.count == 1)
    }

    @Test("строка PROCS без данных слева")
    @MainActor func procsMarkerWithoutData() {
        let output = """
            NOW 1700000000
            PANES
            work\t1\tzsh\t1\t1\t1700000000\t/dev/ttys004
            PROCS
            """
        let sessions = AppModel.parseSessions(output)
        #expect(sessions.count == 1)
    }

    @Test("большой timestamp не переполняет")
    @MainActor func largeTimestamp() {
        let output = """
            NOW 9999999999
            PANES
            work\t1\tzsh\t1\t1\t9999999999\t/dev/ttys004
            PROCS
            """
        let sessions = AppModel.parseSessions(output)
        #expect(sessions.count == 1)
    }
}
