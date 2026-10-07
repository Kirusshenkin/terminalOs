import Foundation
import PhosphorCore
import Testing

@testable import PhosphorUI

@Suite("Нейронки в панелях: какие агенты есть на машине")
struct PaneLaunchTests {
    @Test("из вывода берутся только агенты каталога, шум профиля отбрасывается")
    func installedFromNoisyOutput() {
        let output = "Last login: Wed Oct  8\nclaude\n  codex  \nrm\nwelcome to the server\n"
        #expect(PaneLaunch.installed(in: output) == ["claude", "codex"])
        #expect(PaneLaunch.installed(in: "").isEmpty)
    }

    @Test("проверка спрашивает про каждого агента каталога и ни про что другое")
    func detectionCoversCatalog() {
        let command = PaneLaunch.detectionCommand()
        for choice in PaneLaunch.choices {
            guard let name = choice.command else { continue }
            #expect(command.contains(" \(name)"), "\(name)")
        }
        #expect(PaneLaunch.choices.first == .shell)
        #expect(Set(PaneLaunch.choices.map(\.id)).count == PaneLaunch.choices.count)
    }

    @Test("проверка в настоящем шелле находит то, что есть, и молчит про остальное")
    func detectionRunsInShell() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("phosphor-agents-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }  // временная папка теста
        let fake = directory.appendingPathComponent("codex")
        try Data("#!/bin/sh\n".utf8).write(to: fake)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: fake.path)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", PaneLaunch.detectionCommand()]
        process.environment = ["PATH": directory.path + ":/usr/bin:/bin", "HOME": directory.path]
        let pipe = Pipe()
        process.standardOutput = pipe
        try process.run()
        process.waitUntilExit()
        let output = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        #expect(PaneLaunch.installed(in: output).contains("codex"))
    }
}

@Suite("Нейронки в панелях: подписи")
struct PaneLaunchStringsTests {
    @Test("у каждой подписи есть русский и английский")
    func bothLanguages() {
        for (key, values) in Strings.agentTable {
            #expect(values[.russian]?.isEmpty == false, "\(key) ru")
            #expect(values[.english]?.isEmpty == false, "\(key) en")
        }
        #expect(Strings(language: .english)("term.shell") == "shell")
    }
}

@Suite("Файлы, брошенные в терминал")
struct DroppedPathsTests {
    @Test("путь экранируется, как в Terminal.app, и шелл читает его обратно как есть")
    func escaping() throws {
        #expect(Shell.droppedPaths(["/tmp/a.png"]) == "/tmp/a.png ")
        #expect(Shell.droppedPaths(["/Users/k/My Shot (1).png"]) == #"/Users/k/My\ Shot\ \(1\).png "#)
        #expect(Shell.droppedPaths(["/a b", "/c'd"]) == #"/a\ b /c\'d "#)
        // Кириллица не экранируется: агент должен узнать путь, а не мусор.
        #expect(Shell.droppedPaths(["/Снимок экрана.png"]) == #"/Снимок\ экрана.png "#)

        let tricky = "/tmp/x $(touch pwned) `y` \"q\" & ; | * ? [z] {w} ! # ~"
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", "printf '%s' " + Shell.droppedPaths([tricky])]
        let pipe = Pipe()
        process.standardOutput = pipe
        try process.run()
        process.waitUntilExit()
        #expect(String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self) == tricky)
    }
}
