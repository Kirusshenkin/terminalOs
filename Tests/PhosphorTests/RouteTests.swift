import Foundation
import Testing

@testable import HostsKit
@testable import PhosphorCore
@testable import SSHKit

@Suite("Маршрут через бастионы")
struct RouteTests {
    private let bastion = ServerHost(
        name: "gate", address: "192.0.2.9", user: "jump", reach: .socks(host: "127.0.0.1", port: 10_808),
        identityFile: "~/.ssh/gate")

    private func target(through id: ServerHost.ID) -> ServerHost {
        ServerHost(name: "db", address: "10.0.0.1", user: "deploy", reach: .jump(hostID: id))
    }

    @Test("хост без бастиона идёт напрямую")
    func direct() {
        let host = ServerHost(name: "web", address: "198.51.100.4")
        let book = HostBook(hosts: [host])
        #expect(book.route(for: host) == .direct)
    }

    @Test("один бастион: вход — это способ дотянуться до самого бастиона")
    func oneHop() {
        let host = target(through: bastion.id)
        let route = HostBook(hosts: [bastion, host]).route(for: host)
        #expect(route.bastions == [bastion])
        #expect(route.entry == .socks(host: "127.0.0.1", port: 10_808))
        #expect(route.problem == nil)
    }

    @Test("два бастиона идут снаружи внутрь")
    func twoHops() {
        let outer = ServerHost(name: "outer", address: "203.0.113.1")
        let inner = ServerHost(name: "inner", address: "10.1.0.1", reach: .jump(hostID: outer.id))
        let host = target(through: inner.id)
        let route = HostBook(hosts: [outer, inner, host]).route(for: host)
        #expect(route.bastions.map(\.name) == ["outer", "inner"])
    }

    @Test("удалённый бастион — ошибка, а не тихий прямой вход")
    func missingBastion() {
        let host = target(through: UUID())
        let route = HostBook(hosts: [host]).route(for: host)
        #expect(route.problem == .missingBastion(host: "db"))
        #expect(route.bastions.isEmpty)
    }

    @Test("петля из бастионов распознаётся")
    func loop() {
        var first = ServerHost(name: "a", address: "10.0.0.2")
        let second = ServerHost(name: "b", address: "10.0.0.3", reach: .jump(hostID: first.id))
        first.reach = .jump(hostID: second.id)
        let route = HostBook(hosts: [first, second]).route(for: first)
        #expect(route.problem == .loop(host: "a"))
    }

    @Test("больше трёх прыжков подряд не принимаем")
    func tooDeep() {
        var hosts = [ServerHost(name: "h0", address: "10.0.0.10")]
        for index in 1...4 {
            hosts.append(
                ServerHost(
                    name: "h\(index)", address: "10.0.0.1\(index)", reach: .jump(hostID: hosts[index - 1].id))
            )
        }
        let route = HostBook(hosts: hosts).route(for: hosts[4])
        #expect(route.problem == .tooDeep(host: "h4"))
    }

    @Test("бастион группы сам ходит напрямую, остальные — через него")
    func groupBastion() {
        var group = HostGroup(name: "prod")
        var gate = ServerHost(name: "gate", address: "192.0.2.9", groupID: group.id)
        let host = ServerHost(name: "db", address: "10.0.0.1", groupID: group.id)
        group.reach = .jump(hostID: gate.id)
        gate.groupID = group.id
        let book = HostBook(groups: [group], hosts: [gate, host])
        #expect(book.route(for: gate) == .direct)
        #expect(book.route(for: host).bastions == [gate])
    }

    @Test("в бастионы не предлагаются сам хост и те, кто ходит через него")
    func candidates() {
        let host = ServerHost(name: "db", address: "10.0.0.1")
        let behind = target(through: host.id)
        let other = ServerHost(name: "web", address: "10.0.0.5")
        let names = HostBook(hosts: [host, behind, other]).bastionCandidates(for: host.id).map(\.name)
        #expect(names == ["web"])
    }
}

@Suite("Аргументы ssh через бастион")
struct JumpInvocationTests {
    private let bastion = ServerHost(
        name: "gate", address: "192.0.2.9", port: 2200, user: "jump", identityFile: "~/.ssh/gate")
    private let host = ServerHost(name: "db", address: "10.0.0.1", user: "deploy")

    private func proxyCommand(_ route: Route) throws -> String {
        let arguments = SSHInvocation.arguments(host: host, route: route, controlPath: "/tmp/x")
        let option = try #require(arguments.first { $0.hasPrefix("ProxyCommand=") })
        return String(option.dropFirst("ProxyCommand=".count))
    }

    @Test("бастион — вложенный ssh с его ключом, портом и сокетом")
    func nestedSSH() throws {
        let command = try proxyCommand(Route(bastions: [bastion]))
        #expect(
            command.hasPrefix("'/usr/bin/ssh' '-o' 'ControlMaster=no'"), "мастером вложенный не становится")
        #expect(command.contains("'-i' '~/.ssh/gate'"), "у бастиона свой ключ")
        #expect(command.contains("'2200'"))
        #expect(command.contains(SSHInvocation.controlPath(for: bastion)))
        #expect(command.hasSuffix("-W %h:%p 'jump@192.0.2.9'"))
    }

    @Test("прокси бастиона уходит во вложенный ssh с удвоенными %")
    func socksBehindBastion() throws {
        let command = try proxyCommand(
            Route(entry: .socks(host: "127.0.0.1", port: 10_808), bastions: [bastion]))
        #expect(command.contains("-x 127.0.0.1:10808 -X 5 %%h %%p"), "это токены вложенного ssh, не внешнего")
        #expect(command.contains("-W %h:%p"), "а это — внешнего")
    }

    @Test("два бастиона — ssh внутри ssh")
    func twoHops() throws {
        let outer = ServerHost(name: "outer", address: "203.0.113.1", user: "edge")
        let command = try proxyCommand(Route(bastions: [outer, bastion]))
        #expect(command.contains("-W %%h:%%p"))
        #expect(command.contains("edge@203.0.113.1"))
        #expect(command.hasSuffix("'jump@192.0.2.9'"))
    }

    @Test("сломанный маршрут закрывается, а не идёт напрямую")
    func brokenFailsClosed() throws {
        let command = try proxyCommand(Route(problem: .loop(host: "db")))
        #expect(command == "/usr/bin/false")
    }

    @Test("транспорт со сломанным маршрутом не запускает ssh")
    func transportRefuses() async {
        let transport = SystemSSHTransport(host: host, route: Route(problem: .missingBastion(host: "db")))
        await #expect(throws: TransportError.route(.missingBastion(host: "db"))) {
            _ = try await transport.run("true")
        }
    }
}

@Suite("Чья это ошибка: цели или бастиона")
struct SSHFailureTests {
    private let host = ServerHost(name: "db", address: "10.0.0.1")
    private let bastion = ServerHost(name: "gate", address: "10.0.0.12")

    private func classify(_ stderr: String) -> TransportError? {
        SSHFailure.classify(stderr, host: host, bastions: [bastion])
    }

    @Test("отказ цели остаётся отказом цели")
    func targetDenied() {
        #expect(classify("deploy@10.0.0.1: Permission denied (publickey).") == .authenticationFailed)
    }

    @Test("отказ бастиона помечается бастионом")
    func bastionDenied() {
        let stderr = "jump@10.0.0.12: Permission denied (publickey).\nConnection closed by UNKNOWN port 65535"
        #expect(classify(stderr) == .bastion(bastion, .authenticationFailed))
    }

    @Test("незнакомый ключ бастиона — вопрос про бастион")
    func bastionKeyUnknown() {
        let stderr = "No ED25519 host key is known for [10.0.0.12]:22 and you have requested strict checking."
        #expect(classify(stderr) == .bastion(bastion, .hostKeyUnknown))
    }

    @Test("недоступный бастион называет свой адрес")
    func bastionUnreachable() {
        let stderr = "ssh: connect to host 10.0.0.12 port 22: Operation timed out"
        #expect(classify(stderr) == .bastion(bastion, .hostUnreachable("10.0.0.12")))
    }

    @Test("адрес сравнивается целиком: 10.0.0.1 не находится в 10.0.0.12")
    func wholeToken() {
        #expect(!SSHFailure.mentions("connect to host 10.0.0.12 port 22", "10.0.0.1"))
        #expect(SSHFailure.mentions("deploy@10.0.0.1: permission denied", "10.0.0.1"))
    }

    @Test("строка без адреса — про цель, как и до бастионов")
    func noAddress() {
        let failure = SSHFailure.classify("Permission denied (publickey).", host: host)
        #expect(failure == .authenticationFailed)
    }
}
