import Foundation
import Testing

@testable import HostsKit
@testable import PhosphorCore
@testable import ProvisionKit
@testable import SSHKit
@testable import SessionKit

private func profile(
    family: String = "Linux", manager: String? = "apt", root: Bool = true, sudo: Bool = true
) -> HostProfile {
    HostProfile(
        osName: "ubuntu", osVersion: "24.04", uptimeSeconds: 600,
        isRoot: root, canSudo: sudo, dockerPath: nil, dockerNeedsSudo: false,
        isPodman: false, hasNginx: false, hasCertbot: false, hasUFW: false,
        containerCount: 0, authorizedKeyCount: 1, packageManager: manager, kernelName: family)
}

private let nodeRecipe = #"""
    {
      "format": 1,
      "id": "node",
      "name": "Node.js 22",
      "requires": { "os": ["linux"], "packageManager": ["apt"] },
      "steps": [
        { "title": "Node.js", "check": "command -v node",
          "commands": ["curl -fsSL https://deb.nodesource.com/setup_22.x | bash -", "apt-get install -y nodejs"] },
        { "title": "pm2 для пользователя", "asUser": true, "commands": ["npm install -g pm2"] }
      ]
    }
    """#

@Suite("Рецепт из файла")
struct RecipeFileTests {
    @Test("правильный файл становится рецептом со всеми полями")
    func decodes() throws {
        let recipe = try RecipeFile.decode(Data(nodeRecipe.utf8))
        #expect(recipe.id == "node")
        #expect(recipe.origin == .file)
        #expect(recipe.steps.map(\.title) == ["Node.js", "pm2 для пользователя"])
        #expect(recipe.steps[0].check == "command -v node")
        #expect(recipe.steps[1].asUser)
        #expect(recipe.mustSucceed == Set(recipe.steps.map(\.id)), "чужой рецепт встаёт на первой ошибке")
        #expect(recipe.applies(to: profile()))
        #expect(!recipe.applies(to: profile(family: "Darwin", manager: "brew")))
    }

    private func refusal(_ json: String) -> RecipeFileError? {
        do {
            _ = try RecipeFile.decode(Data(json.utf8))
            return nil
        } catch {
            return error
        }
    }

    private func replacing(_ old: String, with new: String) -> String {
        nodeRecipe.replacingOccurrences(of: old, with: new)
    }

    @Test("каждый дефект файла называется своим именем")
    func refusals() {
        #expect(refusal(replacing(#""format": 1"#, with: #""format": 2"#)) == .unsupportedFormat(2))
        #expect(refusal(replacing(#""id": "node""#, with: #""id": "Node!""#)) == .badID("Node!"))
        #expect(refusal(replacing(#""id": "node""#, with: #""id": "base""#)) == .reservedID("base"))
        #expect(refusal(replacing(#"["linux"]"#, with: #"["windows"]"#)) == .unknownOS("windows"))
        #expect(refusal(replacing(#"["apt"]"#, with: #"["yum"]"#)) == .unknownPackageManager("yum"))
        #expect(refusal(replacing(#"["npm install -g pm2"]"#, with: #"["  "]"#)) == .badCommand(2))
        #expect(refusal(replacing(#""title": "Node.js""#, with: #""title": """#)) == .badStepTitle(1))
        if case .notJSON = refusal("{ not json") {} else { Issue.record("мусор должен называться мусором") }
        let empty = #"{"format": 1, "id": "x", "name": "x", "steps": []}"#
        #expect(refusal(empty) == .stepCount(0))
    }

    @Test("слишком большой файл не разбирается вовсе")
    func tooLarge() {
        let big = Data(repeating: 0x20, count: RecipeFile.maxFileSize + 1)
        #expect(throws: RecipeFileError.tooLarge) { try RecipeFile.decode(big) }
    }
}

@Suite("Папка своих рецептов")
struct RecipeStoreTests {
    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("phosphor-recipes-\(UUID().uuidString)")
    }

    private func write(_ text: String, named name: String, in directory: URL) throws -> URL {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent(name)
        try Data(text.utf8).write(to: url)
        return url
    }

    @Test("импорт кладёт файл под его id, повторный — отказ, удаление убирает")
    func importAndDelete() async throws {
        let library = temporaryDirectory()
        let source = try write(nodeRecipe, named: "anything.json", in: temporaryDirectory())
        let store = RecipeStore(directory: library)
        let recipe = try await store.importFile(at: source)
        #expect(FileManager.default.fileExists(atPath: library.appendingPathComponent("node.json").path))
        #expect(recipe.id == "node")
        await #expect(throws: RecipeFileError.exists("node")) { try await store.importFile(at: source) }
        #expect(await store.load().recipes.map(\.id) == ["node"])
        try await store.delete(id: recipe.id)
        #expect(await store.load().recipes.isEmpty)
    }

    @Test("сломанный файл не прячет остальные и сам назван")
    func brokenFileReported() async throws {
        let library = temporaryDirectory()
        _ = try write(nodeRecipe, named: "node.json", in: library)
        _ = try write("{ oops", named: "broken.json", in: library)
        let loaded = await RecipeStore(directory: library).load()
        #expect(loaded.recipes.map(\.id) == ["node"])
        #expect(loaded.problems.keys.sorted() == ["broken.json"])
    }

    @Test("удаление не идёт по пути из странного id")
    func deleteRefusesPaths() async {
        let store = RecipeStore(directory: temporaryDirectory())
        await #expect(throws: RecipeFileError.badID("../x")) { try await store.delete(id: "../x") }
    }

    @Test("папки ещё нет — своих рецептов просто нет")
    func missingFolder() async {
        let loaded = await RecipeStore(directory: temporaryDirectory()).load()
        #expect(loaded.recipes.isEmpty && loaded.problems.isEmpty)
    }
}

@Suite("Встроенные рецепты")
struct BuiltInRecipeTests {
    private let key = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIH1vN3Kk8lQ2mZ0pW7xR4tYs6uVbNcXdEfGh you@mac"

    @Test("только Docker — пакеты и Docker, для apt")
    func dockerOnly() {
        let recipe = BuiltInRecipe.dockerOnly()
        #expect(recipe.steps.map(\.id) == ["packages", "docker"])
        #expect(recipe.applies(to: profile()))
        #expect(!recipe.applies(to: profile(manager: "dnf")))
    }

    @Test("репозиторий Docker раскрывается на сервере и берёт дистрибутив оттуда")
    func dockerRepository() throws {
        let docker = try #require(BuiltInRecipe.dockerOnly().steps.first { $0.id == "docker" })
        let line = try #require(docker.commands.first { $0.contains("docker.list") })
        #expect(line.hasPrefix("echo \"deb"), "в одинарных кавычках $(…) ушло бы в файл буквально")
        #expect(line.contains("linux/$(. /etc/os-release && echo \"$ID\")"))
        #expect(!docker.commands.joined().contains("linux/ubuntu"), "у Debian свой репозиторий")
    }

    @Test("файрвол оставляет открытым порт, на котором слушает sshd")
    func firewallKeepsSSHPort() throws {
        let ufw = try #require(BuiltInRecipe.base(RecipeInputs(sshPort: 2222)).steps.first { $0.id == "ufw" })
        #expect(ufw.commands.contains("ufw allow 2222/tcp comment 'ssh'"))
        #expect(!ufw.commands.contains { $0.contains("allow 22/tcp") })
    }

    @Test("ключ добавляется, только если его ещё нет — с любым комментарием")
    func authorizeKeys() throws {
        let recipe = BuiltInRecipe.keys(RecipeInputs(keys: [key]))
        let add = try #require(recipe.steps.first)
        #expect(add.asUser, "ключи — в ~/.ssh пользователя, не root")
        let body = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIH1vN3Kk8lQ2mZ0pW7xR4tYs6uVbNcXdEfGh"
        #expect(add.commands.contains { $0.contains("grep -qF \(Shell.quote(body))") })
        #expect(recipe.steps.count == 1, "убирать остальные — только по просьбе")
        #expect(recipe.applies(to: profile(family: "Darwin", manager: "brew")), "на маке тоже работает")
    }

    @Test("без ключа подключения среди выбранных чужие не убираются")
    func pruneGuard() {
        let unsafe = BuiltInRecipe.keys(RecipeInputs(keys: [key], removeOtherKeys: true))
        #expect(unsafe.plan(for: profile()).last?.skip == .wouldLockOut)
        let safe = BuiltInRecipe.keys(
            RecipeInputs(keys: [key], removeOtherKeys: true, connectionKeyKept: true))
        let prune = safe.plan(for: profile()).last
        #expect(prune?.step.id == "keys.prune" && prune?.skip == nil)
        #expect(prune?.step.commands.first?.hasPrefix("cp ~/.ssh/authorized_keys") == true, "сначала копия")
        #expect(prune?.step.commands.last?.contains("test -s") == true, "пустой файл не записывается")
        #expect(BuiltInRecipe.needsKeyProof.contains("keys.prune"))
    }

    @Test("ни одного ключа не выбрано — шаг честно пропускается")
    func noKeys() {
        #expect(BuiltInRecipe.keys(RecipeInputs()).plan(for: profile()).first?.skip == .noKeysChosen)
    }

    @Test("без root и sudo без пароля системные шаги не идут, ключи — идут")
    func needsRoot() {
        let noRoot = profile(root: false, sudo: false)
        #expect(BuiltInRecipe.dockerOnly().plan(for: noRoot).allSatisfy { $0.skip == .needsRoot })
        #expect(BuiltInRecipe.keys(RecipeInputs(keys: [key])).plan(for: noRoot).first?.skip == nil)
    }
}

/// Транспорт, который запоминает команды и отвечает заданным кодом.
private actor ScriptedTransport: SSHTransport {
    nonisolated let host = ServerHost(name: "t", address: "10.0.0.9")
    private(set) var executed: [String] = []
    private let failing: [String]

    init(failing: [String] = []) { self.failing = failing }

    func run(_ command: String, timeout: Duration) async throws -> CommandResult {
        executed.append(command)
        let fails = failing.contains { command.contains($0) }
        return CommandResult(status: fails ? 1 : 0, stdout: "", stderr: fails ? "boom" : "")
    }

    func stream(_ command: String, onLine: @escaping @Sendable (String) -> Void) async throws {}
    func close() async {}
}

@Suite("Исполнитель: проверки, sudo, чужие рецепты")
struct RecipeRunnerTests {
    @Test("прошедшая проверка пропускает шаг, не трогая его команды")
    func checkSkips() async throws {
        let recipe = try RecipeFile.decode(Data(nodeRecipe.utf8))
        let transport = ScriptedTransport()
        let runner = ProvisionRunner(transport: transport, recipe: recipe, profile: profile())
        await runner.run()
        #expect(await runner.steps.first?.status == .skipped(.alreadyDone))
        #expect(await !transport.executed.contains { $0.contains("apt-get install -y nodejs") })
    }

    @Test("не root — системные команды через sudo -n, пользовательские как есть")
    func sudoWrapping() async throws {
        let recipe = try RecipeFile.decode(Data(nodeRecipe.utf8))
        let transport = ScriptedTransport(failing: ["command -v node"])
        let runner = ProvisionRunner(transport: transport, recipe: recipe, profile: profile(root: false))
        await runner.run()
        let executed = await transport.executed
        #expect(executed.contains("sudo -n sh -c 'apt-get install -y nodejs'"))
        #expect(executed.contains("npm install -g pm2"), "шаг от пользователя идёт без sudo")
    }

    @Test("чужой рецепт встаёт на первой ошибке")
    func fileRecipeStops() async throws {
        let recipe = try RecipeFile.decode(Data(nodeRecipe.utf8))
        let transport = ScriptedTransport(failing: ["command -v node", "nodejs"])
        let runner = ProvisionRunner(transport: transport, recipe: recipe, profile: profile())
        await runner.run()
        let steps = await runner.steps
        if case .failed = steps[0].status {} else { Issue.record("первый шаг должен упасть") }
        #expect(steps[1].status == .waiting, "второй шаг не запускается")
    }
}
