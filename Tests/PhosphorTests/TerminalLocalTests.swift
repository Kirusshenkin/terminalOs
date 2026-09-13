import Foundation
import Testing

@testable import PhosphorUI

@Suite("Локальные постоянные сессии")
struct TerminalLocalTests {
    @Test("команда опроса спрашивает именно тот tmux, который нашли")
    @MainActor func pollCommand() {
        let command = AppModel.pollCommand(tmux: "/opt/homebrew/bin/tmux")
        #expect(command.contains("command -v /opt/homebrew/bin/tmux"))
        #expect(command.contains("/opt/homebrew/bin/tmux list-panes -a"))
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
}
