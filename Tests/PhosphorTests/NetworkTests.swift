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
