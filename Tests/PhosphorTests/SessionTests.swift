import Foundation
import Testing

@testable import DockerKit
@testable import HostsKit
@testable import MetricsKit
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
        // Дать задачам разбора добежать.
        try await Task.sleep(for: .milliseconds(120))

        let state = await session.current
        #expect(state.latest != nil)
        #expect(state.previous != nil)
        #expect(state.coreUsage.count == 1)
        #expect(state.coreUsage[0] > 0 && state.coreUsage[0] < 1)
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
