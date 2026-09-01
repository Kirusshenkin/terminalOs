public import Foundation
public import Network

/// Checks whether something is actually listening, rather than trusting a timer.
///
/// A proxy client reports "connected" well before routes and DNS are in place,
/// so readiness is proven by opening a real TCP connection, with retries and one
/// overall deadline.
public enum Reachability {
    /// Single attempt: can we open TCP to this endpoint?
    public static func canConnect(host: String, port: Int, timeout: Duration = .seconds(3)) async -> Bool {
        guard let portValue = NWEndpoint.Port(rawValue: UInt16(clamping: port)) else { return false }
        let endpoint = NWEndpoint.hostPort(host: NWEndpoint.Host(host), port: portValue)
        let connection = NWConnection(to: endpoint, using: .tcp)

        return await withTaskGroup(of: Bool.self) { group in
            group.addTask {
                await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
                    let resumed = Resumed()
                    connection.stateUpdateHandler = { state in
                        switch state {
                        case .ready:
                            if resumed.claim() { continuation.resume(returning: true) }
                        case .failed, .cancelled:
                            if resumed.claim() { continuation.resume(returning: false) }
                        default:
                            break
                        }
                    }
                    connection.start(queue: .global(qos: .userInitiated))
                }
            }
            group.addTask {
                try? await Task.sleep(for: timeout)
                return false
            }
            let result = await group.next() ?? false
            group.cancelAll()
            connection.cancel()
            return result
        }
    }

    /// Waits until the endpoint answers or the deadline passes.
    ///
    /// Used after starting a tunnel: readiness is a fact we verify, never a
    /// three-second sleep and hope.
    public static func waitUntilReady(
        host: String,
        port: Int,
        deadline: Duration = .seconds(20),
        interval: Duration = .milliseconds(600)
    ) async -> Bool {
        let started = ContinuousClock.now
        while ContinuousClock.now - started < deadline {
            if await canConnect(host: host, port: port, timeout: .seconds(2)) { return true }
            try? await Task.sleep(for: interval)
            if Task.isCancelled { return false }
        }
        return false
    }

    /// Verifies a SOCKS5 endpoint really speaks SOCKS, not just accepts TCP.
    ///
    /// Something else listening on the port would otherwise look like a working
    /// proxy right until the first connection silently fails.
    public static func isSocks5(host: String, port: Int) async -> Bool {
        guard let portValue = NWEndpoint.Port(rawValue: UInt16(clamping: port)) else { return false }
        let connection = NWConnection(
            to: .hostPort(host: NWEndpoint.Host(host), port: portValue),
            using: .tcp
        )
        return await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            let latch = Resumed()
            @Sendable func finish(_ value: Bool) {
                if latch.claim() {
                    connection.cancel()
                    continuation.resume(returning: value)
                }
            }
            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    // version 5, one method, "no authentication"
                    connection.send(
                        content: Data([0x05, 0x01, 0x00]),
                        completion: .contentProcessed { error in
                            guard error == nil else { return finish(false) }
                            connection.receive(minimumIncompleteLength: 2, maximumLength: 2) {
                                data, _, _, _ in
                                guard let data, data.count == 2, data[0] == 0x05 else { return finish(false) }
                                finish(true)
                            }
                        })
                case .failed, .cancelled:
                    finish(false)
                default:
                    break
                }
            }
            connection.start(queue: .global(qos: .userInitiated))
            Task {
                try? await Task.sleep(for: .seconds(3))
                finish(false)
            }
        }
    }
}

/// Одноразовая защёлка: продолжение нельзя возобновить дважды.
private final class Resumed: @unchecked Sendable {
    // Безопасность ручная и намеренная: единственное изменяемое поле закрыто
    // собственным замком, а класс существует ровно затем, чтобы защёлку можно
    // было захватить в нескольких колбэках Network.
    // Guarded by its own lock; the class exists only to make the latch safe to
    // capture in the several callbacks Network hands us.
    private let lock = NSLock()
    private var done = false

    func claim() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if done { return false }
        done = true
        return true
    }
}
