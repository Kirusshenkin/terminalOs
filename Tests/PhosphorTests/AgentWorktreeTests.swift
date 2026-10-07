import Foundation
import SSHKit
import Testing

@testable import PhosphorUI

/// Своя копия проекта для агента — на настоящих git и tmux этого Мака, во
/// временной папке. Сети нет.
@Suite("Копия проекта для агента")
struct AgentWorktreeTests {
    private static let tmux = ["/opt/homebrew/bin/tmux", "/usr/local/bin/tmux"].first {
        FileManager.default.isExecutableFile(atPath: $0)
    }

    private func sh(_ command: String) async throws -> CommandResultLike {
        let result = try await Subprocess.run(executable: "/bin/sh", arguments: ["-c", command])
        return CommandResultLike(status: result.status, out: result.stdout)
    }

    struct CommandResultLike {
        let status: Int32
        let out: String
    }

    /// Репозиторий с одним коммитом во временной папке.
    private func repo() async throws -> String {
        let path = NSTemporaryDirectory() + "phx-repo-\(UUID().uuidString.prefix(8))"
        let made = try await sh(
            "mkdir -p \(path) && cd \(path) && git init -q && git -c user.name=t -c user.email=t@t "
                + "commit -q --allow-empty -m init")
        #expect(made.status == 0)
        return (path as NSString).resolvingSymlinksInPath
    }

    @Test("строка запуска: в репозитории — своя копия на ветке agent/…, агент стартует в ней")
    func launchInRepo() async throws {
        let path = try await repo()
        let line = AgentWorktree.launchLine(
            command: "pwd", origin: path, worktree: true, stamp: "0101-000000")
        let run = try await sh(line)
        let copy = path + "-pwd-0101-000000"
        let landed = run.out.trimmingCharacters(in: .whitespacesAndNewlines)
        #expect((landed as NSString).resolvingSymlinksInPath == (copy as NSString).resolvingSymlinksInPath)
        let branches = try await sh("git -C \(path) branch --list 'agent/*'")
        #expect(branches.out.contains("agent/pwd-0101-000000"))
    }

    @Test("не репозиторий — агент просто стартует в папке панели")
    func launchOutsideRepo() async throws {
        let plain = (NSTemporaryDirectory() as NSString).resolvingSymlinksInPath
        let line = AgentWorktree.launchLine(
            command: "pwd", origin: plain, worktree: true, stamp: "0101-000000")
        let landed = try await sh(line).out.trimmingCharacters(in: .whitespacesAndNewlines)
        #expect((landed as NSString).resolvingSymlinksInPath == plain)
        #expect(
            AgentWorktree.launchLine(command: "claude", origin: nil, worktree: false, stamp: "x") == "claude")
    }

    @Test("метка времени для имени копии")
    func stamp() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!  // фиксированный пояс — ради предсказуемого ответа
        #expect(AgentWorktree.stamp(Date(timeIntervalSince1970: 0), calendar: calendar) == "0101-000000")
    }

    @Test(
        "убрать: чистая копия уходит вместе с сессией, ветка остаётся; с правками — ничего не трогается",
        .enabled(if: tmux != nil))
    func remove() async throws {
        let path = try await repo()
        let copy = path + "-claude-1"
        #expect(try await sh("git -C \(path) worktree add -q -b agent/claude-1 \(copy)").status == 0)
        let socket = NSTemporaryDirectory() + "phx-\(UUID().uuidString.prefix(8))"
        let base = "\(Self.tmux!) -S \(socket)"  // условие теста гарантирует tmux
        defer {
            // Сервер tmux для теста; если уже закрылся — тем лучше.
            _ = Task {
                _ = try? await Subprocess.run(
                    executable: "/bin/sh", arguments: ["-c", "\(base) kill-server"])
            }
        }
        #expect(
            try await sh("\(base) new-session -d -s plain && \(base) new-session -d -s agent").status == 0)
        #expect(try await sh("\(base) set-option -t agent: \(AgentWorktree.option) \(copy)").status == 0)

        let none = try await sh(AgentWorktree.removeCommand(session: "plain", tmux: base))
        #expect(none.status == AgentWorktree.Removal.missing.rawValue)

        #expect(try await sh("touch \(copy)/work.txt").status == 0)
        let dirty = try await sh(AgentWorktree.removeCommand(session: "agent", tmux: base))
        #expect(dirty.status == AgentWorktree.Removal.dirty.rawValue)
        #expect(FileManager.default.fileExists(atPath: copy))

        #expect(try await sh("rm \(copy)/work.txt").status == 0)
        let removed = try await sh(AgentWorktree.removeCommand(session: "agent", tmux: base))
        #expect(removed.status == AgentWorktree.Removal.removed.rawValue)
        #expect(!FileManager.default.fileExists(atPath: copy))
        #expect(try await sh("git -C \(path) branch --list agent/claude-1").out.contains("agent/claude-1"))
        #expect(try await sh("\(base) has-session -t agent").status != 0)
    }
}
