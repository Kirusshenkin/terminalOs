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
