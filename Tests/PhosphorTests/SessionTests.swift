import Foundation
import Testing

@testable import DockerKit
@testable import HostsKit
@testable import MetricsKit
@testable import PhosphorCore
@testable import ProvisionKit
@testable import SSHKit
@testable import SessionKit

/// Транспорт, который отвечает заранее заданными результатами.
///
/// Позволяет проверить всю цепочку — опрос, разбор, состояние — не трогая сеть.
private actor FakeTransport: SSHTransport {
    nonisolated let host: ServerHost
    private var answers: [(match: String, result: CommandResult)]
    private(set) var executed: [String] = []
    private let streamLines: [String]

    init(host: ServerHost, answers: [(String, CommandResult)], streamLines: [String] = []) {
        self.host = host
        self.answers = answers.map { (match: $0.0, result: $0.1) }
        self.streamLines = streamLines
    }

    func run(_ command: String, timeout: Duration) async throws -> CommandResult {
        executed.append(command)
        for answer in answers where command.contains(answer.match) { return answer.result }
        return CommandResult(status: 127, stdout: "", stderr: "command not found")
    }

    func stream(_ command: String, onLine: @escaping @Sendable (String) -> Void) async throws {
        for line in streamLines { onLine(line) }
    }

    func close() async {}
}

private func ok(_ stdout: String) -> CommandResult {
    CommandResult(status: 0, stdout: stdout, stderr: "")
}

/// Ждёт наступления условия, опрашивая его, а не засыпая на глазок.
///
/// Пауза «на всякий случай» делает тест плавающим ровно тогда, когда машина
/// занята, — то есть в CI.
private func waitUntil(
    _ condition: @Sendable () async -> Bool,
    deadline: Duration = .seconds(3),
    interval: Duration = .milliseconds(20)
) async -> Bool {
    let started = ContinuousClock.now
    while ContinuousClock.now - started < deadline {
        if await condition() { return true }
        try? await Task.sleep(for: interval)
    }
    return await condition()
}

@Suite("Сессия хоста")
struct HostSessionTests {
    private let probeOutput = """
        OS ubuntu 24.04
        UP 3600000
        ID 0
        SUDO yes
        DOCKER /usr/bin/docker
        PODMAN -
        DOCKEROK yes
        NGINX /usr/sbin/nginx
        CERTBOT -
        UFW -
        PKG apt
        CONTAINERS 2
        KEYS 2
        """

    private var statsJSON: String {
        #"{"ID":"3f9a","Name":"api","CPUPerc":"12%","#
            + #""MemUsage":"100MiB / 1GiB","PIDs":"3"}"#
    }

    private var containerJSON: String {
        let api =
            #"{"ID":"3f9a","Names":"api","Image":"api:1","State":"running","#
            + #""Status":"Up 6 days","Ports":"","Labels":"com.docker.compose.project=prod"}"#
        let old =
            #"{"ID":"1c0d","Names":"migrator","Image":"api:1","State":"exited","#
            + #""Status":"Exited (0)","Ports":"","Labels":""}"#
        return api + "\n" + old
    }

    @Test("подключение собирает профиль и список контейнеров")
    func startsAndPolls() async throws {
        let host = ServerHost(name: "prod-01", address: "10.0.0.1")
        let transport = FakeTransport(
            host: host,
            answers: [
                ("os-release", ok(probeOutput)),
                ("docker ps", ok(containerJSON)),
                ("docker stats", ok(statsJSON)),
            ]
        )
        let session = HostSession(host: host, transport: transport)
        await session.start()
        await session.refreshContainers()

        let state = await session.current
        #expect(state.phase == .ready)
        #expect(state.profile?.osName == "ubuntu")
        #expect(state.containers.count == 2)
        #expect(state.stats["api"]?.pids == 3)
    }

    @Test("метрики появляются только со второго снимка: загрузка — это дельта")
    func metricsNeedTwoSnapshots() async throws {
        let host = ServerHost(name: "prod-01", address: "10.0.0.1")
        let first = ["T 1756800000", "C cpu0 50 0 25 400 5 0 0 0", "M MemTotal: 1000", "---"]
        let second = ["T 1756800002", "C cpu0 100 0 50 450 10 0 0 0", "M MemTotal: 1000", "---"]
        let transport = FakeTransport(
            host: host,
            answers: [("os-release", ok(probeOutput))],
            streamLines: first + second
        )
        let session = HostSession(host: host, transport: transport)
        await session.start()

        // Загрузка существует только как разница, поэтому ждём именно второго
        // снимка, а не «немножко».
        let ready = await waitUntil { await session.current.previous != nil }
        #expect(ready, "второй снимок так и не пришёл")

        let state = await session.current
        #expect(state.latest != nil)
        let usage = state.coreUsage
        #expect(usage.count == 1)
        #expect(usage.first.map { $0 > 0 && $0 < 1 } == true)
    }

    @Test("докер не опрашивается, если его на хосте нет")
    func skipsDockerWhenAbsent() async throws {
        let host = ServerHost(name: "bare", address: "10.0.0.2")
        let bare = probeOutput.replacingOccurrences(of: "DOCKER /usr/bin/docker", with: "DOCKER -")
        let transport = FakeTransport(host: host, answers: [("os-release", ok(bare))])
        let session = HostSession(host: host, transport: transport)
        await session.start()
        await session.refreshContainers()
        let executed = await transport.executed
        // Команда профилирования сама содержит «docker ps» внутри подстановки,
        // поэтому сравниваем с точной командой списка, а не с подстрокой.
        #expect(!executed.contains(DockerCLI.list()))
        #expect(!executed.contains(DockerCLI.stats()))
        #expect(executed.count == 1, "к пустому хосту должен уйти только зонд")
    }

    @Test("ошибки объясняют, что делать, а не просто «не удалось»")
    func errorsAreActionable() {
        let host = ServerHost(name: "prod-01", address: "10.0.0.1")
        let proxy = HostSession.explain(
            TransportError.proxyUnreachable(host: "127.0.0.1", port: 10_808), host: host)
        #expect(proxy.contains("10808"))
        #expect(proxy.lowercased().contains("v2box"))

        let auth = HostSession.explain(TransportError.authenticationFailed, host: host)
        #expect(auth.contains("authorized_keys"))

        let changed = HostSession.explain(TransportError.hostKeyChanged, host: host)
        #expect(changed.contains("изменился"))

        // Разные причины дают разные подсказки — в этом весь смысл.
        #expect(Set([proxy, auth, changed]).count == 3)
    }
}

@Suite("Действия над контейнерами")
struct ContainerActionTests {
    private let running = Container(
        id: "3f9a", name: "api", image: "api:1", state: .running, status: "Up 6 days")
    private let exited = Container(
        id: "1c0d", name: "migrator", image: "api:1", state: .exited, status: "Exited (0)")

    @Test("предлагаем только то, что имеет смысл в этом состоянии")
    func availabilityMatchesState() {
        let forRunning = ContainerAction.available(for: .running)
        #expect(forRunning.contains(.stop))
        #expect(!forRunning.contains(.start), "запускать уже запущенный нечего")

        let forExited = ContainerAction.available(for: .exited)
        #expect(forExited.contains(.start))
        #expect(!forExited.contains(.stop))
        #expect(!forExited.contains(.kill), "убивать остановленный бессмысленно")
    }

    @Test("разрушающие действия помечены как разрушающие")
    func destructiveIsMarked() {
        #expect(ContainerAction.remove.isDestructive)
        #expect(ContainerAction.kill.isDestructive)
        #expect(!ContainerAction.restart.isDestructive)
        #expect(!ContainerAction.stop.isDestructive)
    }

    @Test("идентификатор экранируется в любой команде")
    func quotesIdentifier() {
        for action in ContainerAction.allCases {
            let command = action.command(id: "evil; reboot")
            #expect(command.contains("'evil; reboot'"), "\(action) не экранирует")
            #expect(!command.hasSuffix("; reboot"))
        }
    }

    @Test("ошибки докера превращаются в подсказку, а не в дамп stderr")
    func explainsFailures() {
        func outcome(_ stderr: String, _ action: ContainerAction = .remove) -> String {
            ActionOutcome.from(
                result: CommandResult(status: 1, stdout: "", stderr: stderr),
                action: action, container: "api"
            ).message
        }
        #expect(
            outcome("Got permission denied while trying to connect to the Docker daemon socket")
                .contains("sudo"))
        #expect(outcome("Error: No such container: api").contains("уже нет"))
        #expect(outcome("cannot remove container: container is running").contains("остановить"))
    }

    @Test("успех сообщает о себе тем же типом, что и ошибка")
    func successIsUniform() {
        let good = ActionOutcome.from(
            result: CommandResult(status: 0, stdout: "3f9a", stderr: ""),
            action: .restart, container: "api"
        )
        #expect(good.succeeded)
        #expect(good.containerName == "api")
    }

    @Test("действие уходит на сервер и список обновляется")
    func performsAndRefreshes() async throws {
        let host = ServerHost(name: "prod", address: "10.0.0.1")
        let probe = """
            OS ubuntu 24.04
            UP 1000
            ID 0
            SUDO yes
            DOCKER /usr/bin/docker
            PODMAN -
            DOCKEROK yes
            NGINX -
            CERTBOT -
            UFW -
            PKG apt
            CONTAINERS 1
            KEYS 1
            """
        let transport = FakeTransport(
            host: host,
            answers: [
                ("os-release", ok(probe)),
                ("docker restart", ok("3f9a")),
                (
                    "docker ps",
                    ok(
                        #"{"ID":"3f9a","Names":"api","Image":"api:1","State":"running","Status":"Up 1 second","Ports":"","Labels":""}"#
                    )
                ),
                ("docker stats", ok("")),
            ]
        )
        let session = HostSession(host: host, transport: transport)
        await session.start()
        let outcome = await session.perform(.restart, on: running)
        #expect(outcome.succeeded)

        let executed = await transport.executed
        #expect(executed.contains { $0 == "/usr/bin/docker restart '3f9a'" })
        // После действия список обязан обновиться сам: иначе панель врёт.
        #expect(executed.contains(DockerCLI.list(prefix: "/usr/bin/docker")))
    }
}
