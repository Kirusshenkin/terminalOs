import Foundation
import Network
import Testing

@testable import HostsKit
@testable import SSHKit

/// Слушатель, который отвечает на приветствие SOCKS5 — и второй, который молчит.
///
/// Нужен, чтобы проверить главное свойство: мы отличаем настоящий прокси от
/// чего угодно другого, занявшего тот же порт. Без этой проверки посторонний
/// сервис выглядит как рабочий прокси ровно до первого подключения.
private actor StubListener {
    enum Behaviour { case socks5, silent }

    private let listener: NWListener
    private var connections: [NWConnection] = []
    let port: Int

    init(behaviour: Behaviour) throws {
        let parameters = NWParameters.tcp
        listener = try NWListener(using: parameters, on: .any)
        let ready = DispatchSemaphore(value: 0)
        listener.stateUpdateHandler = { state in
            if case .ready = state { ready.signal() }
        }
        let box = Box()
        listener.newConnectionHandler = { connection in
            connection.start(queue: .global())
            guard behaviour == .socks5 else { return }
            connection.receive(minimumIncompleteLength: 3, maximumLength: 3) { _, _, _, _ in
                // версия 5, метод «без аутентификации»
                connection.send(content: Data([0x05, 0x00]), completion: .idempotent)
            }
            box.keep(connection)
        }
        listener.start(queue: .global())
        _ = ready.wait(timeout: .now() + 3)
        port = Int(listener.port?.rawValue ?? 0)
    }

    func stop() { listener.cancel() }

    /// Держит соединения живыми, пока идёт проверка.
    private final class Box: @unchecked Sendable {
        // Доступ только из одного обработчика listener'а, последовательного.
        private var kept: [NWConnection] = []
        func keep(_ connection: NWConnection) { kept.append(connection) }
    }
}

@Suite("Сеть: готовность и прокси", .serialized)
struct NetworkTests {
    @Test("закрытый порт честно определяется как закрытый")
    func closedPort() async throws {
        // 1 — привилегированный порт, на котором заведомо никто не слушает.
        let reachable = await Reachability.canConnect(host: "127.0.0.1", port: 1, timeout: .seconds(1))
        #expect(!reachable)
    }

    @Test("настоящий SOCKS5 отличается от просто открытого порта")
    func detectsRealSocks() async throws {
        let real = try StubListener(behaviour: .socks5)
        let silent = try StubListener(behaviour: .silent)
        defer {
            Task {
                await real.stop(); await silent.stop()
            }
        }
        let realPort = await real.port
        let silentPort = await silent.port
        try #require(realPort > 0 && silentPort > 0)

        // TCP открыт у обоих — этого мало.
        #expect(await Reachability.canConnect(host: "127.0.0.1", port: realPort))
        #expect(await Reachability.canConnect(host: "127.0.0.1", port: silentPort))

        // Рукопожатие проходит только у настоящего.
        #expect(await Reachability.isSocks5(host: "127.0.0.1", port: realPort))
        #expect(await !Reachability.isSocks5(host: "127.0.0.1", port: silentPort))
    }

    @Test("ожидание готовности не висит вечно, а укладывается в дедлайн")
    func waitRespectsDeadline() async throws {
        let started = ContinuousClock.now
        let ready = await Reachability.waitUntilReady(
            host: "127.0.0.1", port: 1,
            deadline: .milliseconds(900), interval: .milliseconds(200)
        )
        let elapsed = ContinuousClock.now - started
        #expect(!ready)
        #expect(elapsed < .seconds(4), "дедлайн должен соблюдаться, прошло \(elapsed)")
    }

    @Test("подключение к закрытому порту даёт причину, а не общую ошибку")
    func transportExplainsProxyDown() async throws {
        let host = ServerHost(name: "prod", address: "127.0.0.1", port: 1)
        // Прокси указан, но его нет — ошибка обязана назвать именно прокси.
        let transport = SystemSSHTransport(host: host, reach: .socks(host: "127.0.0.1", port: 1))
        await #expect(throws: TransportError.proxyUnreachable(host: "127.0.0.1", port: 1)) {
            _ = try await transport.run("true", timeout: .seconds(3))
        }
        await transport.close()
    }
}

@Suite("Аргументы ssh")
struct SSHInvocationTests {
    private let host = ServerHost(name: "prod", address: "10.0.0.1", port: 2222, user: "deploy")

    @Test("команды и интерактивный шелл идут по одному сокету")
    func sharesControlPath() {
        let socket = "/tmp/phosphor-test.sock"
        let forCommands = SSHInvocation.arguments(host: host, reach: .direct, controlPath: socket)
        let forShell = SSHInvocation.shellArguments(host: host, reach: .direct, controlPath: socket)
        // Иначе будет второй логин и второй Touch ID на ровном месте.
        #expect(forShell.starts(with: forCommands))
        #expect(forCommands.contains("ControlPath=\(socket)"))
        #expect(forShell.last == "deploy@10.0.0.1")
        #expect(forShell.contains("-t"), "интерактивному шеллу нужен PTY")
    }

    @Test("AES-GCM стоит впереди ChaCha20 — обход Terrapin")
    func prefersAESGCM() throws {
        let arguments = SSHInvocation.arguments(host: host, reach: .direct, controlPath: "/tmp/x")
        let index = try #require(
            arguments.firstIndex(
                of: "Ciphers=aes256-gcm@openssh.com,aes128-gcm@openssh.com,aes256-ctr,aes128-ctr"))
        #expect(index > 0)
        let ciphers = arguments[index]
        #expect(!ciphers.contains("chacha20"), "уязвимый к Terrapin шифр не предлагаем вовсе")
        #expect(!ciphers.contains("cbc"), "CBC с Encrypt-then-MAC тоже уязвим")
    }

    @Test("смена ключа хоста блокирует подключение, а не спрашивает")
    func strictHostKey() {
        let arguments = SSHInvocation.arguments(host: host, reach: .direct, controlPath: "/tmp/x")
        #expect(arguments.contains("StrictHostKeyChecking=yes"))
        #expect(arguments.contains("ForwardAgent=no"), "агент не пробрасываем")
    }

    @Test("порт берётся из хоста, а не из умолчания")
    func usesHostPort() {
        let arguments = SSHInvocation.arguments(host: host, reach: .direct, controlPath: "/tmp/x")
        #expect(arguments.contains("2222"))
    }

    @Test("через прокси имя хоста уходит целиком: DNS резолвит прокси")
    func proxyResolvesName() throws {
        let arguments = SSHInvocation.arguments(
            host: host, reach: .socks(host: "127.0.0.1", port: 10_808), controlPath: "/tmp/x")
        let command = try #require(arguments.first { $0.hasPrefix("ProxyCommand=") })
        #expect(command.contains("127.0.0.1:10808"))
        #expect(command.contains("%h"), "адрес подставляет ssh, а не мы")
        #expect(command.contains("-X 5"), "SOCKS5, а не SOCKS4")
    }

    @Test("без прокси лишнего ProxyCommand нет")
    func directHasNoProxy() {
        let arguments = SSHInvocation.arguments(host: host, reach: .direct, controlPath: "/tmp/x")
        #expect(!arguments.contains { $0.hasPrefix("ProxyCommand") })
    }
}
