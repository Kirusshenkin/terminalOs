import Foundation
import Testing

@testable import PhosphorUI
@testable import HostsKit
@testable import SSHKit

@Suite("Постоянные сессии (tmux)")
struct SessionRailTests {
    @Test("список tmux разбирается в имя, окна и признак подключения")
    @MainActor func parse() {
        let output = "main\t3\t1\nbuild\t1\t0\n"
        let sessions = AppModel.parseSessions(output)
        #expect(sessions.count == 2)
        #expect(sessions[0].name == "main")
        #expect(sessions[0].windows == 3)
        #expect(sessions[0].attached == true)
        #expect(sessions[1].attached == false)
    }

    @Test("пустой вывод — пустой список, а не падение")
    @MainActor func empty() {
        #expect(AppModel.parseSessions("").isEmpty)
        #expect(AppModel.parseSessions("\n\n").isEmpty)
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
        // Без имени сессии — никакого tmux, обычный шелл.
        let plain = SSHInvocation.shellArguments(
            host: host, reach: .direct, controlPath: "/tmp/s")
        #expect(!plain.joined(separator: " ").contains("tmux"))
    }
}
