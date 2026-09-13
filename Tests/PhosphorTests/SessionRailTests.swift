import Foundation
import Testing

@testable import HostsKit
@testable import PhosphorUI
@testable import SSHKit

@Suite("Постоянные сессии (tmux)")
struct SessionRailTests {
    // Формат строки: session \t paneActive \t command \t windows \t attached \t activity
    private func line(_ n: String, _ a: String, _ c: String, _ w: String, _ at: String, _ act: String)
        -> String
    { "\(n)\t\(a)\t\(c)\t\(w)\t\(at)\t\(act)" }

    @Test("активная панель определяет статус: шелл — покой, чужой процесс — работа")
    @MainActor func status() {
        let out = [
            "NOW 1000",
            line("main", "1", "zsh", "3", "1", "995"),
            line("build", "1", "node", "1", "0", "998"),
        ].joined(separator: "\n")
        let s = AppModel.parseSessions(out)
        #expect(s.count == 2)
        #expect(s[0].name == "main" && s[0].status == .idle && s[0].windows == 3 && s[0].attached)
        #expect(s[1].name == "build" && s[1].status == .working && !s[1].attached)
    }

    @Test("чужой процесс, давно молчащий, — вероятно, ждёт ввода")
    @MainActor func blocked() {
        let out = ["NOW 1000", line("wait", "1", "ssh", "1", "0", "900")].joined(separator: "\n")
        let s = AppModel.parseSessions(out)
        #expect(s.first?.status == .blocked)
    }

    @Test("статус берётся с активной панели, не с первой попавшейся")
    @MainActor func activePane() {
        let out = [
            "NOW 1000",
            line("dev", "0", "zsh", "2", "1", "999"),
            line("dev", "1", "vim", "2", "1", "999"),
        ].joined(separator: "\n")
        let s = AppModel.parseSessions(out)
        #expect(s.count == 1)
        #expect(s.first?.status == .working)  // активна панель с vim
    }

    @Test("пустой вывод — пустой список, а не падение")
    @MainActor func empty() {
        #expect(AppModel.parseSessions("").isEmpty)
        #expect(AppModel.parseSessions("NOW 1000\n").isEmpty)
    }

    @Test("маркер отсутствия tmux не превращается в сессию")
    @MainActor func noTmuxMarker() {
        #expect(AppModel.parseSessions(AppModel.noTmuxMarker).isEmpty)
    }

    @Test("агент находится по полной командной строке с терминала панели")
    @MainActor func agentFromProcesses() {
        let out = [
            "NOW 1000",
            "PANES",
            line("api", "1", "node", "1", "1", "999") + "\t/dev/pts/4",
            "PROCS",
            "pts/4 S+ node /usr/lib/node_modules/@anthropic-ai/claude-code/cli.js",
        ].joined(separator: "\n")
        let s = AppModel.parseSessions(out)
        #expect(s.count == 1)
        #expect(s[0].agent?.id == "claude")
        #expect(s[0].status == .working)
    }

    @Test("агент в неактивной панели всё равно виден")
    @MainActor func agentInBackgroundPane() {
        let out = [
            "NOW 1000",
            "PANES",
            line("dev", "1", "zsh", "2", "1", "999") + "\t/dev/pts/1",
            line("dev", "0", "codex", "2", "1", "999") + "\t/dev/pts/2",
            "PROCS",
            "pts/2 S+ codex",
        ].joined(separator: "\n")
        let s = AppModel.parseSessions(out)
        #expect(s.count == 1)
        // Статус — с активной панели (шелл, покой), имя агента — с той, где он.
        #expect(s[0].status == .idle)
        #expect(s[0].agent?.id == "codex")
    }

    @Test("сессия без агента остаётся без имени агента")
    @MainActor func noAgent() {
        let out = [
            "NOW 1000",
            "PANES",
            line("build", "1", "make", "1", "0", "999") + "\t/dev/pts/9",
            "PROCS",
            "pts/9 S+ make -j8",
        ].joined(separator: "\n")
        #expect(AppModel.parseSessions(out).first?.agent == nil)
    }

    @Test("передние процессы разбираются с обоими написаниями терминала")
    @MainActor func ttyForms() {
        let table = AppModel.foreground([
            "pts/3 Ss+ -zsh",
            "ttys004 S+ claude --resume",
            "? Ss /usr/sbin/sshd",
            "мусор",
        ])
        #expect(table["pts/3"] == ["-zsh"])
        #expect(table["ttys004"] == ["claude --resume"])
        #expect(table["?"] == nil)
        #expect(AppModel.normalisedTTY("/dev/pts/3") == "pts/3")
    }

    @Test("имя сессии очищается от запретных для tmux символов")
    func sanitise() {
        #expect(SSHInvocation.tmuxSessionName("prod.web:1") == "prod-web-1")
        #expect(SSHInvocation.tmuxSessionName("main") == "main")
        #expect(SSHInvocation.tmuxSessionName("") == nil)
        #expect(SSHInvocation.tmuxSessionName("...") == nil)
    }

    @Test("шелл с сессией оборачивается в tmux с откатом на обычный шелл")
    func shellArgs() {
        let host = ServerHost(name: "h", address: "10.0.0.1", user: "root")
        let args = SSHInvocation.shellArguments(
            host: host, reach: .direct, controlPath: "/tmp/s", tmuxSession: "main")
        let joined = args.joined(separator: " ")
        #expect(joined.contains("tmux new-session -A -s main"))
        #expect(joined.contains("exec \"${SHELL:-/bin/sh}\" -l"))
        let plain = SSHInvocation.shellArguments(
            host: host, reach: .direct, controlPath: "/tmp/s")
        #expect(!plain.joined(separator: " ").contains("tmux"))
    }
}
