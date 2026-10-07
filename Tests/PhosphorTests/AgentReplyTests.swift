import Foundation
import SSHKit
import Testing

@testable import PhosphorUI

@Suite("Ответ ждущему агенту")
@MainActor
struct AgentReplyTests {
    @Test("Enter и Esc — клавишами в сессию")
    func keys() {
        #expect(AppModel.replyCommand(.accept, session: "work") == "tmux send-keys -t 'work:' Enter")
        #expect(AppModel.replyCommand(.decline, session: "work") == "tmux send-keys -t 'work:' Escape")
    }

    @Test("текст без управляющих символов, пустой не отправляется")
    func text() throws {
        let command = try #require(AppModel.replyCommand(.text("да\nи\u{1B}[2J ещё"), session: "w"))
        #expect(command.contains("'даи[2J ещё'"))
        #expect(AppModel.replyCommand(.text(" \n\t "), session: "w") == nil)
    }

    /// Настоящий tmux этого Мака: текст с `;` и кавычками доходит до программы
    /// в сессии как есть, а Enter отправляет строку.
    @Test(
        "через локальный tmux строка доходит целиком",
        .enabled(
            if: ["/opt/homebrew/bin/tmux", "/usr/local/bin/tmux"].contains {
                FileManager.default.isExecutableFile(atPath: $0)
            }))
    func throughTmux() async throws {
        let tmux = ["/opt/homebrew/bin/tmux", "/usr/local/bin/tmux"].first {
            FileManager.default.isExecutableFile(atPath: $0)
        }!  // условие теста выше гарантирует, что один из путей есть
        let socket = NSTemporaryDirectory() + "phx-\(UUID().uuidString.prefix(8))"
        let base = "\(tmux) -S \(socket)"
        let output = NSTemporaryDirectory() + "phx-reply-\(UUID().uuidString)"
        _ = try await Subprocess.run(
            executable: "/bin/sh",
            arguments: [
                "-c",
                "\(base) new-session -d -s agent \"sh -c 'read line; printf %s \\\"\\$line\\\" > \(output); "
                    + "\(base) wait-for -S written'\"",
            ])
        defer {
            // Временный файл ответа; не удалился — его подберёт система.
            _ = try? FileManager.default.removeItem(atPath: output)
        }
        let text = "go; rm 'x' && echo \"done\";"
        let command = try #require(AppModel.replyCommand(.text(text), session: "agent", tmux: base))
        let result = try await Subprocess.run(executable: "/bin/sh", arguments: ["-c", command])
        #expect(result.succeeded)
        // Готовность — по событию из сессии; таймаут Subprocess — только верхняя граница.
        _ = try await Subprocess.run(
            executable: "/bin/sh", arguments: ["-c", "\(base) wait-for written"], timeout: .seconds(5))
        let written = try String(contentsOfFile: output, encoding: .utf8)
        _ = try? await Subprocess.run(executable: "/bin/sh", arguments: ["-c", "\(base) kill-server"])
        #expect(written == text)
    }
}
