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

    @Test("у каждого агента каталога есть установка, у шелла — нет")
    func everyAgentInstallable() {
        for choice in PaneLaunch.choices where choice.command != nil {
            #expect(choice.installLine(then: "x") != nil, "\(choice.id)")
        }
        #expect(PaneLaunch.shell.installLine(then: "x") == nil)
    }

    @Test("установка, вход и запуск идут по порядку; упавшая установка ничего не запускает")
    func installLineRunsInOrder() throws {
        func run(install: String) throws -> String {
            let choice = PaneLaunch(
                id: "fake", title: "fake", command: "fake", install: install, login: "echo login")
            let line = try #require(choice.installLine(then: "echo start"))
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/sh")
            process.arguments = ["-c", line]
            process.environment = ["PATH": "/usr/bin:/bin", "HOME": "/nonexistent"]
            let pipe = Pipe()
            process.standardOutput = pipe
            try process.run()
            process.waitUntilExit()
            return String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        }
        #expect(try run(install: "echo install") == "install\nlogin\nstart\n")
        #expect(try run(install: "echo install; false") == "install\n")
    }

    @Test("удалённая панель берёт headless-вход, локальная — обычный")
    func remoteLoginOnlyOnRemote() throws {
        let choice = PaneLaunch(
            id: "fake", title: "fake", command: "fake", install: "echo i",
            login: "echo browser", remoteLogin: "echo device")
        let local = try #require(choice.installLine(then: "echo go", remote: false))
        let remote = try #require(choice.installLine(then: "echo go", remote: true))
        #expect(local.contains("echo browser"))
        #expect(!local.contains("echo device"))
        #expect(remote.contains("echo device"))
        #expect(!remote.contains("echo browser"))
        // Нет remoteLogin — удалённая падает обратно на обычный вход.
        let onlyLocal = PaneLaunch(
            id: "f2", title: "f2", command: "f2", install: "echo i", login: "echo browser")
        #expect(try #require(onlyLocal.installLine(then: "echo go", remote: true)).contains("echo browser"))
    }

    @Test("codex на сервере входит по коду устройства, не через браузер")
    func codexRemoteUsesDeviceAuth() throws {
        let codex = try #require(PaneLaunch.choices.first { $0.id == "codex" })
        #expect(codex.remoteLogin == "codex login --device-auth")
        #expect(codex.login == nil)  // локально codex сам откроет браузер
    }

    @Test("npm-установка не зависит от brew/sudo: домашний префикс и Node в ~/.local")
    func npmInstallNeedsNoRootOrBrew() {
        let line = PaneLaunch.npmInstall("@scope/pkg")
        // Пакет — в домашний префикс, а не в системный каталог (EACCES).
        #expect(line.contains("npm install -g --prefix \"$HOME/.npm-global\" @scope/pkg"))
        // Нет npm и нет brew (Linux) — Node приезжает tar.xz в ~/.local, а не
        // прежним `brew install node`, который на сервере не существует.
        #expect(line.contains("nodejs.org/dist/latest-v22.x/"))
        #expect(line.contains("tar -xJ -C \"$HOME/.local\""))
    }

    @Test("GLM спрашивает ключ z.ai, только когда у opencode его ещё нет")
    func glmAsksKeyOnce() throws {
        let home = FileManager.default.temporaryDirectory
            .appendingPathComponent("phosphor-glm-\(UUID().uuidString)")
        let bin = home.appendingPathComponent("bin")
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: home) }  // временная папка теста
        // Подставной opencode печатает, с чем его позвали.
        let fake = bin.appendingPathComponent("opencode")
        try Data("#!/bin/sh\necho \"$@\"\n".utf8).write(to: fake)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: fake.path)
        let glm = try #require(PaneLaunch.choices.first { $0.id == "glm" })
        let start = try #require(glm.start)

        func run(_ extra: [String: String] = [:]) throws -> String {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/sh")
            process.arguments = ["-c", start]
            process.environment = ["PATH": bin.path + ":/usr/bin:/bin", "HOME": home.path]
                .merging(extra) { $1 }
            let pipe = Pipe()
            process.standardOutput = pipe
            try process.run()
            process.waitUntilExit()
            return String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        }
        let model = "-m zai-coding-plan/glm-5.3\n"
        #expect(try run() == "auth login -p zai-coding-plan\n" + model)
        #expect(try run(["ZHIPU_API_KEY": "k"]) == model)
        let store = home.appendingPathComponent(".local/share/opencode")
        try FileManager.default.createDirectory(at: store, withIntermediateDirectories: true)
        try Data(#"{"zai-coding-plan":{"type":"api"}}"#.utf8).write(to: store.appendingPathComponent("auth.json"))
        #expect(try run() == model)
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
