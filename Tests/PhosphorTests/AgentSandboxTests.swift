import Foundation
import Testing

@testable import PhosphorUI

@Suite("Песочница для агентов на этом Маке")
struct AgentSandboxTests {
    /// Запускает строку под настоящим `sandbox-exec` и возвращает, что она напечатала.
    /// Фикстура лежит во временной папке, поэтому временные папки профилю не
    /// разрешаются — иначе «запись в дом» прошла бы через них.
    private func run(_ script: String, home: URL, project: URL) throws -> String {
        let profile = home.deletingLastPathComponent().appendingPathComponent("test.sb")
        try Data(AgentSandbox.profile(scratch: []).utf8).write(to: profile)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", AgentSandbox.wrap(script, profilePath: profile.path)]
        process.currentDirectoryURL = project
        process.environment = ["PATH": "/usr/bin:/bin", "HOME": home.path]
        let pipe = Pipe()
        process.standardOutput = pipe
        try process.run()
        process.waitUntilExit()
        return String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
    }

    @Test("агент пишет в проект и свои настройки, но не в дом и не видит ~/.ssh")
    func boundaries() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("phosphor-sandbox-\(UUID().uuidString)")
            .resolvingSymlinksInPath()
        let home = root.appendingPathComponent("home")
        let project = home.appendingPathComponent("code/app")
        for dir in [project, home.appendingPathComponent(".ssh"), home.appendingPathComponent(".claude")] {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        defer { try? FileManager.default.removeItem(at: root) }  // временная папка теста
        try Data("secret".utf8).write(to: home.appendingPathComponent(".ssh/id_ed25519"))

        let script = """
            touch made && echo project
            touch "$HOME/.claude/x" "$HOME/.claude.json" && echo settings
            touch "$HOME/.zshrc" 2>/dev/null && echo HOME
            cat "$HOME/.ssh/id_ed25519" 2>/dev/null && echo SSH
            ls "$HOME/.ssh" >/dev/null 2>&1 && echo LIST
            true
            """
        #expect(try run(script, home: home, project: project) == "project\nsettings\n")
    }

    @Test("проект в домашней папке не открывает ~/.ssh: запрет стоит последним")
    func homeAsProject() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("phosphor-sandbox-\(UUID().uuidString)")
            .resolvingSymlinksInPath()
        let home = root.appendingPathComponent("home")
        try FileManager.default.createDirectory(
            at: home.appendingPathComponent(".ssh"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }  // временная папка теста

        let script = """
            touch notes && echo home
            touch "$HOME/.ssh/authorized_keys" 2>/dev/null && echo SSH
            true
            """
        #expect(try run(script, home: home, project: home) == "home\n")
    }

    @Test("строка запуска экранирует команду агента целиком")
    func wrapQuotes() {
        let line = AgentSandbox.wrap("echo 'a b' && opencode", profilePath: "/x y/p.sb")
        #expect(line.contains("sandbox-exec -f '/x y/p.sb'"))
        #expect(line.hasSuffix(#"/bin/sh -c 'echo '\''a b'\'' && opencode'"#))
    }
}
