import Foundation
import Testing

@testable import DockerKit
@testable import HostsKit
@testable import KeysKit
@testable import MetricsKit
@testable import PhosphorCore
@testable import ProvisionKit
@testable import SessionKit
@testable import ThemeKit

@Suite("Кольцевой буфер")
struct RingBufferTests {
    @Test("переполнение вытесняет старое, а не растёт")
    func overwrites() {
        var buffer = RingBuffer<Int>(capacity: 3)
        for value in 1...5 { buffer.append(value) }
        #expect(buffer.elements == [3, 4, 5])
        #expect(buffer.count == 3)
        #expect(buffer.last == 5)
    }

    @Test("пустой и частично заполненный ведут себя предсказуемо")
    func partial() {
        var buffer = RingBuffer<String>(capacity: 4)
        #expect(buffer.isEmpty)
        #expect(buffer.last == nil)
        buffer.append("a")
        buffer.append("b")
        #expect(buffer.elements == ["a", "b"])
        #expect(!buffer.isFull)
        buffer.removeAll()
        #expect(buffer.isEmpty)
    }
}

@Suite("Метрики /proc")
struct MetricsTests {
    private let first = """
        T 1756800000
        L 0.42 0.51 0.48 2/184 9111
        U 3542400.12 28000000.00
        C cpu  100 0 50 800 10 0 0 0
        C cpu0 50 0 25 400 5 0 0 0
        C cpu1 50 0 25 400 5 0 0 4
        M MemTotal: 32000000
        M MemAvailable: 20000000
        M SwapTotal: 2000000
        M SwapFree: 2000000
        D / 220000000000 188000000000 32000000000
        D /var/lib/docker 200000000000 61000000000 139000000000
        N eth0 1000 500
        N lo 999999 999999
        """

    private let second = """
        T 1756800002
        L 0.44 0.51 0.48 2/184 9111
        U 3542402.12 28000004.00
        C cpu  200 0 100 900 20 0 0 4
        C cpu0 100 0 50 450 10 0 0 0
        C cpu1 100 0 50 450 10 0 0 8
        M MemTotal: 32000000
        M MemAvailable: 19000000
        M SwapTotal: 2000000
        M SwapFree: 2000000
        D / 220000000000 189000000000 31000000000
        N eth0 3000 1500
        """

    @Test("снимок разбирается целиком")
    func parsesSnapshot() throws {
        let snapshot = try #require(SnapshotParser.parse(first))
        #expect(snapshot.cores.count == 2)  // строка cpu без номера не ядро
        #expect(snapshot.loadOne == 0.42)
        #expect(snapshot.uptime == 3_542_400)
        #expect(snapshot.memoryTotal == 32_000_000 * 1024)
        #expect(snapshot.filesystems.count == 2)
        #expect(snapshot.interfaces.map(\.name) == ["eth0"])  // lo не считаем
    }

    @Test("память считается по MemAvailable, а не MemFree")
    func memoryUsesAvailable() throws {
        let snapshot = try #require(SnapshotParser.parse(first))
        #expect(snapshot.memoryUsed == 12_000_000 * 1024)
        #expect(abs(snapshot.memoryUsage - 0.375) < 0.001)
    }

    @Test("загрузка ядер — это дельта между снимками")
    func usageFromDelta() throws {
        let a = try #require(SnapshotParser.parse(first))
        let b = try #require(SnapshotParser.parse(second))
        let usage = SnapshotParser.usage(from: a, to: b)
        #expect(usage.count == 2)
        // cpu0: total 480 → 610 (+130), idle 405 → 460 (+55) → занято 1 - 55/130
        #expect(abs(usage[0] - (1 - 55.0 / 130.0)) < 0.001)
    }

    @Test("steal виден отдельно: это сосед, а не твоя нагрузка")
    func stealIsSeparate() throws {
        let a = try #require(SnapshotParser.parse(first))
        let b = try #require(SnapshotParser.parse(second))
        let steal = SnapshotParser.steal(from: a, to: b)
        #expect(steal[0] == 0)
        #expect(steal[1] > 0)
    }

    @Test("скорость сети — байты, делённые на реальный интервал")
    func throughput() throws {
        let a = try #require(SnapshotParser.parse(first))
        let b = try #require(SnapshotParser.parse(second))
        let flow = SnapshotParser.throughput(from: a, to: b)
        #expect(flow.count == 1)
        #expect(flow[0].down == 1000)  // (3000-1000)/2 с
        #expect(flow[0].up == 500)
    }

    @Test("счётчик после перезагрузки не даёт отрицательных значений")
    func countersResetSafely() throws {
        let a = try #require(SnapshotParser.parse(second))
        let b = try #require(SnapshotParser.parse(first))
        #expect(SnapshotParser.usage(from: a, to: b).allSatisfy { $0 >= 0 && $0 <= 1 })
    }

    @Test("мусор не притворяется снимком")
    func rejectsGarbage() {
        #expect(SnapshotParser.parse("совершенно посторонний текст") == nil)
    }
}

@Suite("Docker")
struct DockerTests {
    /// Собираем строку так, как её печатает `--format '{{json .}}'`.
    private func json(_ pairs: KeyValuePairs<String, String>) -> String {
        let body = pairs.map { "\"\($0.key)\":\"\($0.value)\"" }.joined(separator: ",")
        return "{\(body)}"
    }

    @Test("разбор ps с реальными полями")
    func parsesList() {
        let running = json([
            "ID": "3f9a", "Names": "api-gateway", "Image": "api:2.14",
            "State": "running", "Status": "Up 6 days",
            "Ports": "127.0.0.1:8080->8080/tcp",
            "Labels": "com.docker.compose.project=acme,tier=web",
        ])
        let exited = json([
            "ID": "1c0d", "Names": "migrator", "Image": "api:2.14",
            "State": "exited", "Status": "Exited (0) 6 days ago",
            "Ports": "", "Labels": "",
        ])
        let output = [running, exited, "мусор, который не должен ронять список"]
            .joined(separator: "\n")

        let containers = DockerCLI.parseList(output)
        #expect(containers.count == 2)
        #expect(containers[0].project == "acme")
        #expect(containers[0].state == .running)
        #expect(containers[1].state == .exited)
    }

    @Test("unhealthy виден из статуса")
    func detectsUnhealthy() {
        let output = json([
            "ID": "77aa", "Names": "worker", "Image": "w:1",
            "State": "running", "Status": "Up 2 hours (unhealthy)",
            "Ports": "", "Labels": "",
        ])
        #expect(DockerCLI.parseList(output).first?.isUnhealthy == true)
    }

    @Test("stats: проценты и размеры в обеих системах суффиксов")
    func parsesStats() {
        let output = json([
            "ID": "3f9a", "Name": "api", "CPUPerc": "12.34%",
            "MemUsage": "412MiB / 1GiB", "PIDs": "14",
        ])
        let stats = DockerCLI.parseStats(output)
        #expect(stats.count == 1)
        #expect(abs(stats[0].cpu - 0.1234) < 0.0001)
        #expect(stats[0].memoryUsed == 412 * 1_048_576)
        #expect(stats[0].pids == 14)
    }

    @Test("идентификатор контейнера экранируется в командах")
    func quotesIdentifiers() {
        #expect(DockerCLI.action("rm", id: "evil; reboot") == "docker rm 'evil; reboot'")
    }
}

@Suite("authorized_keys")
struct KeysTests {
    private let sample = """
        ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIH1vN3Kk8lQ2mZ0pW7xR4tYs6uVbNcXdEfGh you@mac
        command="deploy.sh",no-pty ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIKlMnOpQrStUvWxYz012345 deploy@ci
        #phosphor-disabled ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIP0oQrStUvWxYz0123456 temp
        # обычный комментарий, не ключ

        """

    @Test("разбираем опции, ключ и комментарий")
    func parses() {
        let keys = AuthorizedKeysFile.parse(sample)
        #expect(keys.count == 3)
        #expect(keys[0].comment == "you@mac")
        #expect(keys[0].options == nil)
        #expect(keys[1].options == #"command="deploy.sh",no-pty"#)
        #expect(keys[2].isEnabled == false)
    }

    @Test("отпечаток считается локально и выглядит как у OpenSSH")
    func fingerprint() {
        let key = AuthorizedKeysFile.parse(sample)[0]
        #expect(key.fingerprint.hasPrefix("SHA256:"))
        #expect(!key.fingerprint.contains("="))  // без padding
        #expect(key.fingerprint.count == 7 + 43)
    }

    @Test("запись и чтение переживают круг")
    func roundTrip() {
        let keys = AuthorizedKeysFile.parse(sample)
        let reparsed = AuthorizedKeysFile.parse(AuthorizedKeysFile.render(keys))
        #expect(reparsed.map(\.base64) == keys.map(\.base64))
        #expect(reparsed.map(\.isEnabled) == keys.map(\.isEnabled))
    }

    @Test("самоблокировка распознаётся до записи, а не после")
    func lockoutDetected() {
        let keys = AuthorizedKeysFile.parse(sample)
        let mine = keys[0]
        #expect(
            AuthorizedKeysFile.wouldLockOut(
                keys: keys, removing: [mine.id], currentFingerprint: mine.fingerprint))
        #expect(
            !AuthorizedKeysFile.wouldLockOut(
                keys: keys, removing: [keys[1].id], currentFingerprint: mine.fingerprint))
        #expect(
            AuthorizedKeysFile.wouldLockOut(
                keys: keys, removing: Set(keys.map(\.id)), currentFingerprint: nil))
    }

    @Test("слабые ключи помечаются")
    func weakness() {
        let dsa = AuthorizedKeysFile.parse("ssh-dss AAAAB3NzaC1kc3MAAACBAK old@laptop")
        #expect(dsa.first?.weakness != nil)
        let ed = AuthorizedKeysFile.parse(sample)[0]
        #expect(ed.weakness == nil)
        #expect(ed.bits == 256)
    }
}

@Suite("Импорт ~/.ssh/config")
struct SSHConfigTests {
    @Test("разбираем понятное, остальное показываем как пропущенное")
    func parses() {
        let text = """
            Host bastion
                HostName 10.0.0.1
                User admin
                Port 2222

            Host prod
                HostName 10.0.0.2
                ProxyJump bastion
                ControlMaster auto

            Host *.internal
                User root

            Match host prod
                ForwardAgent yes
            """
        let result = SSHConfigImport.parse(text)
        #expect(result.entries.count == 2)
        #expect(result.entries[0].port == 2222)
        #expect(result.entries[1].proxyJump == "bastion")
        // Шаблон и незнакомые директивы попадают в «пропущено», а не тихо теряются.
        let skipped = result.skipped.map(\.directive)
        #expect(skipped.contains { $0.contains("*.internal") })
        #expect(skipped.contains { $0.lowercased().contains("controlmaster") })
        #expect(skipped.contains { $0.lowercased().contains("match") })
    }

    @Test("ProxyJump превращается в бастион")
    func resolvesJump() {
        let result = SSHConfigImport.parse(
            """
            Host bastion
                HostName 10.0.0.1
            Host prod
                HostName 10.0.0.2
                ProxyJump bastion
            """)
        let hosts = SSHConfigImport.hosts(from: result)
        #expect(hosts.count == 2)
        if case .jump(let id) = hosts[1].reach {
            #expect(id == hosts[0].id)
        } else {
            Issue.record("ожидали переход через бастион, получили \(hosts[1].reach)")
        }
    }
}

@Suite("Хосты, группы и сниппеты")
struct HostBookTests {
    private func book() -> HostBook {
        let prod = HostGroup(name: "prod", themeID: "ruby", guardLevel: .always, mcpMode: .readOnly)
        let web = HostGroup(name: "web")
        return HostBook(
            groups: [prod, web],
            hosts: [
                ServerHost(name: "prod-1", address: "10.0.0.1", groupID: prod.id, tags: ["appTag"]),
                ServerHost(name: "prod-2", address: "10.0.0.2", groupID: prod.id, tags: ["appTag"]),
                ServerHost(name: "web-dev", address: "10.1.0.1", groupID: web.id, tags: ["dev"]),
                ServerHost(name: "loose", address: "10.2.0.1"),
            ]
        )
    }

    @Test("поиск идёт по имени, тегу и названию группы")
    func search() {
        let book = book()
        #expect(book.search("appTag").count == 2)
        #expect(book.search("web").count == 1)  // по имени группы
        #expect(book.search("").count == 4)
        #expect(book.search("нет такого").isEmpty)
    }

    @Test("фильтр по группе сужает список")
    func groupFilter() {
        let book = book()
        let prod = book.groups[0]
        #expect(book.search("", groupID: prod.id).count == 2)
    }

    @Test("настройки наследуются от группы, хост важнее")
    func inheritance() {
        var book = book()
        #expect(book.guardLevel(for: book.hosts[0]) == .always)
        #expect(book.mcpMode(for: book.hosts[0]) == .readOnly)
        // Хост без группы — самый строгий вариант по умолчанию.
        #expect(book.mcpMode(for: book.hosts[3]) == .disabled)
        book.hosts[0].guardLevel = .never
        #expect(book.guardLevel(for: book.hosts[0]) == .never)
    }

    @Test("подстановка в сниппет экранируется")
    func snippetExpansion() {
        let snippet = Snippet(name: "логи", command: "docker logs --tail 200 {{container}}")
        #expect(snippet.placeholders == ["container"])
        #expect(snippet.expand(["container": "api; rm -rf /"]) == "docker logs --tail 200 'api; rm -rf /'")
    }
}

@Suite("Профиль хоста и рецепт")
struct ProvisionTests {
    private let freshOutput = """
        OS ubuntu 24.04
        UP 640
        ID 0
        SUDO yes
        DOCKER -
        PODMAN -
        DOCKEROK no
        NGINX -
        CERTBOT -
        UFW -
        PKG apt
        CONTAINERS 0
        KEYS 1
        """

    private let livedInOutput = """
        OS ubuntu 22.04
        UP 3600000
        ID 0
        SUDO yes
        DOCKER /usr/bin/docker
        PODMAN -
        DOCKEROK yes
        NGINX /usr/sbin/nginx
        CERTBOT /usr/bin/certbot
        UFW /usr/sbin/ufw
        PKG apt
        CONTAINERS 6
        KEYS 4
        """

    @Test("свежий сервер узнаётся по молодости и пустоте сразу")
    func freshVerdict() {
        let profile = HostProbe.parse(freshOutput)
        #expect(profile.isFresh)
        #expect(profile.osName == "ubuntu")
        #expect(profile.isProvisionable)
    }

    @Test("обжитой сервер не предлагаем настраивать")
    func livedInVerdict() {
        let profile = HostProbe.parse(livedInOutput)
        #expect(!profile.isFresh)
        #expect(profile.containerCount == 6)
        #expect(profile.dockerPrefix == "/usr/bin/docker")
    }

    @Test("docker есть, но info не работает — значит нужен sudo")
    func dockerNeedsSudo() {
        let output = livedInOutput.replacingOccurrences(of: "DOCKEROK yes", with: "DOCKEROK no")
        let profile = HostProbe.parse(output)
        #expect(profile.dockerNeedsSudo)
        #expect(profile.dockerPrefix == "sudo /usr/bin/docker")
    }

    @Test("не-apt дистрибутив честно объявляется неподдерживаемым")
    func refusesUnknownDistro() {
        let output = freshOutput.replacingOccurrences(of: "PKG apt", with: "PKG -")
        let profile = HostProbe.parse(output)
        #expect(!profile.isProvisionable)
        let recipe = BuiltInRecipe.base(RecipeInputs())
        let plan = recipe.plan(for: profile)
        #expect(
            plan.allSatisfy { step, skip in
                step.id == "passwords"
                    || { if case .unsupported = skip { return true } else { return false } }()
            })
    }

    @Test("уже установленное пропускается, а не ставится заново")
    func skipsWhatExists() {
        let profile = HostProbe.parse(livedInOutput)
        let plan = BuiltInRecipe.base(RecipeInputs()).plan(for: profile)
        let docker = try? #require(plan.first { $0.step.id == "docker" })
        if case .alreadyDone = docker?.skip {} else { Issue.record("docker должен пропускаться") }
    }

    @Test("пароли закрываются последними и только когда есть ключ")
    func passwordsLast() {
        let recipe = BuiltInRecipe.base(RecipeInputs(domain: "a.example.com", email: "k@example.com"))
        #expect(recipe.steps.last?.id == "passwords")
        var noKeys = HostProbe.parse(freshOutput)
        noKeys.authorizedKeyCount = 0
        let plan = recipe.plan(for: noKeys)
        if case .unsupported = plan.last?.skip {} else { Issue.record("без ключей пароли закрывать нельзя") }
    }

    @Test("certbot появляется только с валидным доменом и почтой")
    func certbotNeedsValidInput() {
        #expect(!BuiltInRecipe.base(RecipeInputs()).steps.contains { $0.id == "certbot" })
        #expect(
            !BuiltInRecipe.base(RecipeInputs(domain: "bad domain", email: "k@example.com"))
                .steps.contains { $0.id == "certbot" })
        let good = BuiltInRecipe.base(RecipeInputs(domain: "a.example.com", email: "k@example.com"))
        #expect(good.steps.contains { $0.id == "certbot" })
    }

    @Test("параметры рецепта экранированы, инъекция не проходит")
    func recipeQuotesInputs() {
        let recipe = BuiltInRecipe.base(RecipeInputs(domain: "a.example.com", email: "k@example.com"))
        let certbot = recipe.steps.first { $0.id == "certbot" }
        let joined = certbot?.commands.joined(separator: "\n") ?? ""
        #expect(joined.contains("'a.example.com'"))
        #expect(joined.contains("getent hosts"), "проверка DNS обязана быть до выпуска сертификата")
    }
}

@Suite("Темы")
struct ThemeTests {
    @Test("во всех встроенных темах ровно 16 цветов ANSI")
    func builtInsAreComplete() {
        for theme in BuiltInThemes.all {
            #expect(theme.isValid, "\(theme.name): \(theme.ansi.count) цветов")
        }
    }

    @Test("hex разбирается с альфой и без")
    func hexParsing() {
        #expect(RGBA(hex: "#5BE87F")?.hex == "#5BE87F")
        #expect(RGBA(hex: "5BE87F")?.hex == "#5BE87F")
        #expect(RGBA(hex: "#5BE87F80")?.alpha ?? 1 < 0.6)
        #expect(RGBA(hex: "нет") == nil)
    }

    @Test("неизвестная тема откатывается на фосфор, а не падает")
    func unknownFallsBack() {
        #expect(BuiltInThemes.theme(id: "нет такой").id == "phosphor")
    }
}

@Suite("Форматирование")
struct FormatTests {
    @Test("размеры читаются по-человечески")
    func sizes() {
        #expect(ByteFormat.size(0) == "0 Б")
        #expect(ByteFormat.size(1024) == "1,0 КБ" || ByteFormat.size(1024) == "1.0 КБ")
        #expect(ByteFormat.size(1_073_741_824).hasSuffix("ГБ"))
    }

    @Test("длительность сжимается до значимого")
    func durations() {
        #expect(ByteFormat.duration(seconds: 48) == "48с")
        #expect(ByteFormat.duration(seconds: 3_600 * 2 + 840) == "2ч 14м")
        #expect(ByteFormat.duration(seconds: 41 * 86_400 + 6 * 3_600) == "41д 6ч")
    }

    @Test("процент не выходит за границы")
    func percents() {
        #expect(ByteFormat.percent(-1) == "0 %")
        #expect(ByteFormat.percent(2) == "100 %")
        #expect(ByteFormat.percent(0.855) == "86 %")
    }
}

@Suite("Быстрое подключение и импорт")
struct QuickConnectTests {
    /// Разбор `user@host:port` — то, что набирают в строке поиска.
    ///
    /// Проверяется отдельно от интерфейса, потому что ошибка здесь ведёт не к
    /// кривой вёрстке, а к подключению не туда.
    private func parse(_ text: String) -> ServerHost? {
        let value = text.trimmingCharacters(in: .whitespaces)
        guard value.contains("@") else { return nil }
        let parts = value.split(separator: "@", maxSplits: 1)
        guard parts.count == 2, !parts[0].isEmpty else { return nil }
        let target = parts[1].split(separator: ":", maxSplits: 1)
        guard let address = target.first, !address.isEmpty else { return nil }
        let port = target.count > 1 ? Int(target[1]) ?? 22 : 22
        return ServerHost(
            name: String(parts[1]), address: String(address),
            port: port, user: String(parts[0])
        )
    }

    @Test("обычная форма разбирается")
    func plain() throws {
        let host = try #require(parse("root@10.0.0.1"))
        #expect(host.user == "root")
        #expect(host.address == "10.0.0.1")
        #expect(host.port == 22)
    }

    @Test("порт учитывается")
    func withPort() throws {
        let host = try #require(parse("deploy@example.com:2222"))
        #expect(host.port == 2222)
        #expect(host.user == "deploy")
    }

    @Test("мусор не превращается в хост")
    func rejectsGarbage() {
        #expect(parse("") == nil)
        #expect(parse("просто текст") == nil)
        #expect(parse("@10.0.0.1") == nil, "пустой пользователь — не хост")
        #expect(parse("root@") == nil, "пустой адрес — не хост")
    }

    @Test("нечисловой порт не роняет разбор, а откатывается к 22")
    func badPortFallsBack() throws {
        let host = try #require(parse("root@10.0.0.1:абв"))
        #expect(host.port == 22)
    }
}

@Suite("Расширенные метрики")
struct ExtendedMetricsTests {
    private let first = """
        T 1756800000
        L 0.42 0.51 0.48 3/184 9111
        U 3542400.12 28000000.00
        C cpu0 50 0 25 400 5 0 0 0
        M MemTotal: 32000000
        M MemAvailable: 20000000
        M SwapTotal: 2000000
        M SwapFree: 1500000
        B nvme0n1 200000 400000
        F 4096
        S 912 45.5 12.3 node
        S 41 2.0 0.5 postgres
        K 6.8.0-45-generic
        P AMD EPYC 7763 64-Core Processor
        """

    private let second = """
        T 1756800002
        L 0.44 0.51 0.48 5/186 9111
        U 3542402.12 28000004.00
        C cpu0 100 0 50 450 10 0 0 0
        M MemTotal: 32000000
        M MemAvailable: 19000000
        M SwapTotal: 2000000
        M SwapFree: 1500000
        B nvme0n1 204000 408000
        F 4200
        """

    @Test("процессы, дескрипторы, ядро и модель процессора разбираются")
    func parsesExtras() throws {
        let snapshot = try #require(SnapshotParser.parse(first))
        #expect(snapshot.runningProcesses == 3)
        #expect(snapshot.totalProcesses == 184)
        #expect(snapshot.openFiles == 4096)
        #expect(snapshot.kernel == "6.8.0-45-generic")
        #expect(snapshot.cpuModel.contains("EPYC"))
    }

    @Test("самые тяжёлые процессы приходят в долях, а не в процентах")
    func parsesProcesses() throws {
        let snapshot = try #require(SnapshotParser.parse(first))
        #expect(snapshot.processes.count == 2)
        #expect(snapshot.processes[0].pid == 912)
        #expect(snapshot.processes[0].command == "node")
        #expect(abs(snapshot.processes[0].cpu - 0.455) < 0.001)
    }

    @Test("swap считается использованным, а не свободным")
    func swapAccounting() throws {
        let snapshot = try #require(SnapshotParser.parse(first))
        #expect(snapshot.swapTotal == 2_000_000 * 1024)
        #expect(snapshot.swapFree == 1_500_000 * 1024)
    }

    @Test("скорость диска переводится из секторов в байты")
    func diskThroughput() throws {
        let a = try #require(SnapshotParser.parse(first))
        let b = try #require(SnapshotParser.parse(second))
        let flow = try #require(SnapshotParser.diskThroughput(from: a, to: b).first)
        #expect(flow.name == "nvme0n1")
        // (204000-200000) секторов × 512 байт ÷ 2 с
        #expect(flow.down == 4_000.0 * 512 / 2)
        #expect(flow.up == 8_000.0 * 512 / 2)
    }

    @Test("счётчики диска после перезагрузки не дают отрицательной скорости")
    func diskCountersResetSafely() throws {
        let a = try #require(SnapshotParser.parse(second))
        let b = try #require(SnapshotParser.parse(first))
        #expect(
            SnapshotParser.diskThroughput(from: a, to: b).allSatisfy {
                $0.down >= 0 && $0.up >= 0
            })
    }

    @Test("команда сбора спрашивает всё нужное одним каналом")
    func probeCoversEverything() {
        let loop = ProcProbe.loop()
        for needle in [
            "/proc/loadavg", "/proc/stat", "/proc/meminfo", "df -PB1",
            "/proc/net/dev", "/proc/diskstats", "file-nr", "ps -eo",
        ] {
            #expect(loop.contains(needle), "в цикле нет \(needle)")
        }
        // Неизменное спрашивается отдельно и один раз.
        #expect(ProcProbe.once.contains("uname -r"))
        #expect(ProcProbe.once.contains("cpuinfo"))
        #expect(
            !loop.contains("cpuinfo"), "модель процессора не меняется — не спрашиваем её каждые две секунды")
    }
}

@Suite("Переменные окружения контейнера")
struct DockerEnvironmentTests {
    @Test("значение со знаком равенства не обрезается")
    func keepsValueWithEquals() {
        let json = """
            [{"Config":{"Env":["NODE_ENV=production","DSN=postgres://u:p@h/db?x=1","EMPTY="]}}]
            """
        let parsed = DockerCLI.parseEnvironment(json)
        #expect(parsed.count == 3)
        #expect(parsed[0] == ("NODE_ENV", "production"))
        #expect(parsed[1].value == "postgres://u:p@h/db?x=1")
        #expect(parsed[2].value == "")
    }

    @Test("строка без имени и мусор вместо json дают пустой список")
    func survivesJunk() {
        #expect(DockerCLI.parseEnvironment("не json").isEmpty)
        #expect(DockerCLI.parseEnvironment("[]").isEmpty)
        #expect(DockerCLI.parseEnvironment("""
            [{"Config":{"Env":["=нет имени","без знака равенства"]}}]
            """).isEmpty)
    }
}
