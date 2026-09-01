import Foundation
import Testing

@testable import HostsKit
@testable import KeysKit
@testable import PhosphorCore
@testable import ProvisionKit
@testable import SSHKit
@testable import SessionKit

/// Транспорт, который записывает всё, что ушло на сервер, и умеет валить
/// заданные команды.
private actor RecordingTransport: SSHTransport {
    nonisolated let host: ServerHost
    private(set) var executed: [String] = []
    private let failing: Set<String>

    init(host: ServerHost, failing: Set<String> = []) {
        self.host = host
        self.failing = failing
    }

    func run(_ command: String, timeout: Duration) async throws -> CommandResult {
        executed.append(command)
        if failing.contains(where: { command.contains($0) }) {
            return CommandResult(status: 1, stdout: "", stderr: "E: не удалось")
        }
        return CommandResult(status: 0, stdout: "ok", stderr: "")
    }

    func stream(_ command: String, onLine: @escaping @Sendable (String) -> Void) async throws {}
    func close() async {}
}

private func freshProfile(keys: Int = 1) -> HostProfile {
    HostProfile(
        osName: "ubuntu", osVersion: "24.04", uptimeSeconds: 600,
        isRoot: true, canSudo: true, dockerPath: nil, dockerNeedsSudo: false,
        isPodman: false, hasNginx: false, hasCertbot: false, hasUFW: false,
        containerCount: 0, authorizedKeyCount: keys, packageManager: "apt"
    )
}

@Suite("Исполнитель рецептов")
struct ProvisionRunnerTests {
    private let host = ServerHost(name: "prod-02", address: "10.0.0.2")

    @Test("все команды видны до запуска — скрытых действий нет")
    func commandsAreVisibleUpFront() async {
        let runner = ProvisionRunner(
            transport: RecordingTransport(host: host),
            recipe: BuiltInRecipe.base(RecipeInputs()),
            profile: freshProfile()
        )
        let planned = await runner.plannedCommands()
        #expect(!planned.isEmpty)
        let all = planned.flatMap(\.commands)
        #expect(all.contains { $0.contains("apt-get") })
        #expect(all.contains { $0.contains("ufw") })
    }

    @Test("пароли закрываются последними и только с подтверждённым ключом")
    func passwordsNeedProvenKey() async {
        let transport = RecordingTransport(host: host)
        let runner = ProvisionRunner(
            transport: transport,
            recipe: BuiltInRecipe.base(RecipeInputs()),
            profile: freshProfile(),
            proveKeyAccess: { false }  // ключ не подтверждён
        )
        await runner.run()
        let steps = await runner.steps
        let passwords = try? #require(steps.first { $0.id == "passwords" })
        if case .failed(let reason) = passwords?.status {
            #expect(reason.contains("ключ"))
        } else {
            Issue.record("шаг паролей должен отказаться, а не выполниться")
        }
        let executed = await transport.executed
        #expect(
            !executed.contains { $0.contains("PasswordAuthentication no") },
            "конфиг sshd не должен быть тронут без подтверждённого ключа")
    }

    @Test("с подтверждённым ключом пароли закрываются, и именно в конце")
    func passwordsRunLast() async {
        let transport = RecordingTransport(host: host)
        let runner = ProvisionRunner(
            transport: transport,
            recipe: BuiltInRecipe.base(RecipeInputs()),
            profile: freshProfile(),
            proveKeyAccess: { true }
        )
        await runner.run()
        let executed = await transport.executed
        let sshdIndex = try? #require(executed.firstIndex { $0.contains("PasswordAuthentication no") })
        let ufwIndex = try? #require(executed.firstIndex { $0.contains("ufw --force enable") })
        #expect((sshdIndex ?? 0) > (ufwIndex ?? 0), "пароли обязаны закрываться после всего")
    }

    @Test("уже установленное пропускается, а не ставится заново")
    func skipsWhatExists() async {
        var profile = freshProfile()
        profile.dockerPath = "/usr/bin/docker"
        profile.hasNginx = true
        let transport = RecordingTransport(host: host)
        let runner = ProvisionRunner(
            transport: transport,
            recipe: BuiltInRecipe.base(RecipeInputs()),
            profile: profile
        )
        await runner.run()
        let steps = await runner.steps
        if case .skipped = steps.first(where: { $0.id == "docker" })?.status {
        } else {
            Issue.record("docker должен быть пропущен")
        }
        let executed = await transport.executed
        #expect(!executed.contains { $0.contains("docker-ce") })
    }

    @Test("падение обязательного шага останавливает прогон")
    func criticalFailureStops() async {
        let transport = RecordingTransport(host: host, failing: ["apt-get -y -qq upgrade"])
        let runner = ProvisionRunner(
            transport: transport,
            recipe: BuiltInRecipe.base(RecipeInputs()),
            profile: freshProfile()
        )
        await runner.run()
        let steps = await runner.steps
        if case .failed = steps[0].status {} else { Issue.record("первый шаг должен упасть") }
        // Дальше идти нельзя: ставить nginx поверх неустановленных пакетов
        // бессмысленно.
        #expect(steps.dropFirst().allSatisfy { $0.status == .waiting })
        let executed = await transport.executed
        #expect(!executed.contains { $0.contains("nginx") })
    }

    @Test("остановка прекращает прогон между шагами")
    func stopHalts() async {
        let transport = RecordingTransport(host: host)
        let runner = ProvisionRunner(
            transport: transport,
            recipe: BuiltInRecipe.base(RecipeInputs()),
            profile: freshProfile()
        )
        await runner.stop()
        await runner.run()
        let executed = await transport.executed
        #expect(executed.isEmpty, "после остановки не должно уйти ни одной команды")
    }

    @Test("на неподдерживаемом дистрибутиве ничего не выполняется")
    func refusesUnknownDistro() async {
        var profile = freshProfile()
        profile.packageManager = nil
        let transport = RecordingTransport(host: host)
        let runner = ProvisionRunner(
            transport: transport,
            recipe: BuiltInRecipe.base(RecipeInputs()),
            profile: profile,
            proveKeyAccess: { true }
        )
        await runner.run()
        let executed = await transport.executed
        // Шаг паролей от пакетного менеджера не зависит, всё остальное — да.
        #expect(!executed.contains { $0.contains("apt-get") })
    }
}

@Suite("Ключи на сервере")
struct KeyManagerTests {
    private let host = ServerHost(name: "prod", address: "10.0.0.1")

    private var sample: String {
        """
        ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIH1vN3Kk8lQ2mZ0pW7xR4tYs6uVbNcXdEfGh you@mac
        ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIKlMnOpQrStUvWxYz012345 deploy@ci
        """
    }

    /// Транспорт, отдающий содержимое файла и запоминающий, что в него писали.
    private actor KeyTransport: SSHTransport {
        nonisolated let host: ServerHost
        private let contents: String
        private(set) var written: [String] = []

        init(host: ServerHost, contents: String) {
            self.host = host
            self.contents = contents
        }

        func run(_ command: String, timeout: Duration) async throws -> CommandResult {
            if command.hasPrefix("cat ") { return CommandResult(status: 0, stdout: contents, stderr: "") }
            written.append(command)
            return CommandResult(status: 0, stdout: "", stderr: "")
        }

        func stream(_ command: String, onLine: @escaping @Sendable (String) -> Void) async throws {}
        func close() async {}
    }

    @Test("чтение разбирает файл с сервера")
    func reads() async throws {
        let manager = KeyManager(transport: KeyTransport(host: host, contents: sample))
        let keys = try await manager.load()
        #expect(keys.count == 2)
        #expect(keys[0].comment == "you@mac")
    }

    @Test("удалить свой ключ нельзя без явного согласия")
    func refusesSelfLockout() async throws {
        let transport = KeyTransport(host: host, contents: sample)
        let manager = KeyManager(transport: transport)
        let keys = try await manager.load()
        let mine = keys[0]

        await #expect(throws: KeyManager.KeyError.wouldLockOut) {
            _ = try await manager.remove(
                ids: [mine.id], from: keys, currentFingerprint: mine.fingerprint)
        }
        // Главное: файл не тронут.
        #expect(await transport.written.isEmpty)
    }

    @Test("удалить чужой ключ можно, и запись атомарна с бэкапом")
    func removesOther() async throws {
        let transport = KeyTransport(host: host, contents: sample)
        let manager = KeyManager(transport: transport)
        let keys = try await manager.load()
        let remaining = try await manager.remove(
            ids: [keys[1].id], from: keys, currentFingerprint: keys[0].fingerprint)

        #expect(remaining.count == 1)
        let command = try #require(await transport.written.first)
        #expect(command.contains(".phosphor.bak"), "бэкап обязателен")
        #expect(command.contains(".phosphor.tmp"), "запись через временный файл")
        #expect(command.contains("chmod 600"))
        #expect(command.contains("mv "), "подмена одним движением, а не дозапись")
    }

    @Test("выключение своего ключа приравнивается к удалению")
    func disablingSelfIsBlocked() async throws {
        let transport = KeyTransport(host: host, contents: sample)
        let manager = KeyManager(transport: transport)
        let keys = try await manager.load()
        await #expect(throws: KeyManager.KeyError.wouldLockOut) {
            _ = try await manager.setEnabled(
                false, id: keys[0].id, in: keys, currentFingerprint: keys[0].fingerprint)
        }
        #expect(await transport.written.isEmpty)
    }

    @Test("повторное добавление того же ключа ничего не меняет")
    func addIsIdempotent() async throws {
        let transport = KeyTransport(host: host, contents: sample)
        let manager = KeyManager(transport: transport)
        let keys = try await manager.load()
        let again = try await manager.add(
            line: sample.components(separatedBy: "\n")[0],
            to: keys, currentFingerprint: keys[0].fingerprint)
        #expect(again.count == keys.count)
        #expect(await transport.written.isEmpty, "дублирующая запись не нужна")
    }

    @Test("мусор вместо ключа отвергается")
    func rejectsGarbage() async throws {
        let manager = KeyManager(transport: KeyTransport(host: host, contents: sample))
        let keys = try await manager.load()
        await #expect(throws: KeyManager.KeyError.self) {
            _ = try await manager.add(line: "это не ключ", to: keys, currentFingerprint: nil)
        }
    }
}

@Suite("Листинг файлов")
struct ListingParserTests {
    /// Вывод GNU `ls -la --time-style=+%s` — то, что мы просим у сервера.
    private let epochListing = """
        total 48
        drwxr-xr-x  6 root root  4096 1756800000 .
        drwxr-xr-x 22 root root  4096 1756700000 ..
        drwxr-xr-x  2 root root  4096 1756790000 app
        -rw-r--r--  1 root root  2148 1756795000 docker-compose.yml
        -rw-------  1 root root   640 1756000000 .env.prod
        lrwxrwxrwx  1 root root    11 1756795500 current -> app/release
        -rw-r--r--  1 deploy web 50593792 1756799000 deploy.tar.gz
        """

    @Test("разбираем права, владельца, размер и время")
    func parsesFields() throws {
        let files = ListingParser.parse(epochListing)
        let compose = try #require(files.first { $0.name == "docker-compose.yml" })
        #expect(compose.permissions == "-rw-r--r--")
        #expect(compose.size == 2148)
        #expect(compose.owner == "root root")
        #expect(!compose.isDirectory)
        #expect(compose.modified != nil)
    }

    @Test("папки, ссылки и обычные файлы различаются")
    func detectsKinds() throws {
        let files = ListingParser.parse(epochListing)
        #expect(files.first { $0.name == "app" }?.isDirectory == true)
        let link = try #require(files.first { $0.name == "current" })
        #expect(link.isSymlink)
        #expect(link.linkTarget == "app/release")
        #expect(files.first { $0.name == "deploy.tar.gz" }?.isDirectory == false)
    }

    @Test("строка total и мусор пропускаются")
    func ignoresNoise() {
        let files = ListingParser.parse("total 48\n\nсовсем не листинг\n" + epochListing)
        #expect(files.allSatisfy { !$0.name.isEmpty })
        #expect(files.contains { $0.name == "app" })
    }

    @Test("имя с пробелами собирается целиком")
    func nameWithSpaces() throws {
        let listing = "-rw-r--r--  1 root root  10 1756795000 отчёт за январь.txt"
        let file = try #require(ListingParser.parse(listing).first)
        #expect(file.name == "отчёт за январь.txt")
    }

    @Test("листинг без эпохи не роняет разбор, просто без времени")
    func classicListing() throws {
        let listing = "-rw-r--r--  1 root root  2148 Sep  2 01:12 docker-compose.yml"
        let file = try #require(ListingParser.parse(listing).first)
        #expect(file.name == "docker-compose.yml")
        #expect(file.size == 2148)
        #expect(file.modified == nil)
    }

    @Test("путь экранируется — пробелы и кавычки не ломают команду")
    func quotesPath() {
        let command = ListingParser.command(path: "/srv/мой проект'; rm -rf /")
        #expect(command.contains("'/srv/мой проект'\\''; rm -rf /'"))
    }

    @Test("переход вверх не уводит выше корня")
    func resolveStaysInsideRoot() {
        let browser = FileBrowser(
            transport: RecordingTransport(host: ServerHost(name: "x", address: "1")),
            host: ServerHost(name: "x", address: "1"), reach: .direct, controlPath: "/tmp/x")
        #expect(browser.resolve("/srv/app", entering: "..") == "/srv")
        #expect(browser.resolve("/srv", entering: "..") == "/")
        #expect(browser.resolve("/", entering: "..") == "/")
        #expect(browser.resolve("/srv", entering: "app") == "/srv/app")
    }
}
