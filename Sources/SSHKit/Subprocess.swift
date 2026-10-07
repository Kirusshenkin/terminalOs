public import Foundation
public import PhosphorCore

/// Thin async wrapper around `Process`.
///
/// Output is drained on a background queue while the process runs: reading only
/// after exit deadlocks as soon as a command produces more than a pipe buffer.
public enum Subprocess {
    public static func run(
        executable: String,
        arguments: [String],
        input: Data? = nil,
        timeout: Duration = .seconds(30)
    ) async throws -> CommandResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        let outPipe = Pipe(), errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe
        let inPipe = input.map { _ in Pipe() }
        if let inPipe { process.standardInput = inPipe }

        let collector = OutputCollector()
        // Пустой кусок — конец трубы: обработчик снимает себя сам, и только
        // после этого всё, что процесс написал, точно лежит в сборщике.
        outPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if data.isEmpty {
                handle.readabilityHandler = nil
                collector.finish()
            } else {
                collector.appendOut(data)
            }
        }
        errPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if data.isEmpty {
                handle.readabilityHandler = nil
                collector.finish()
            } else {
                collector.appendErr(data)
            }
        }

        try process.run()
        if let input, let inPipe { feed(input, to: inPipe.fileHandleForWriting) }

        let deadline = Task {
            try await Task.sleep(for: timeout)
            if process.isRunning { process.terminate() }
        }
        await waitForExit(process)
        deadline.cancel()
        // Выход процесса не значит, что его вывод дочитан: последний кусок
        // мог ещё лежать в трубе, и причина ошибки приходила пустой. Ждём
        // конца обеих труб; таймер — только верхняя граница, если трубу
        // держит фоновый потомок (мастер-соединение ssh).
        await collector.drained(within: .seconds(2))
        outPipe.fileHandleForReading.readabilityHandler = nil
        errPipe.fileHandleForReading.readabilityHandler = nil

        return CommandResult(
            status: process.terminationStatus,
            stdout: collector.outText,
            stderr: collector.errText
        )
    }

    /// Streams stdout line by line until the process exits.
    public static func stream(
        executable: String,
        arguments: [String],
        onLine: @escaping @Sendable (String) -> Void
    ) async throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()

        let splitter = LineSplitter(onLine: onLine)
        pipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            splitter.feed(data)
        }
        try process.run()
        await withTaskCancellationHandler {
            await waitForExit(process)
        } onCancel: {
            process.terminate()
        }
        pipe.fileHandleForReading.readabilityHandler = nil
    }
}

/// Пишет ввод процессу с отдельного потока и закрывает его.
///
/// Запись в трубу блокирует, пока процесс не прочтёт: с вызывающего потока
/// большой ввод подвесил бы его до выхода процесса, а тот ждал бы конца ввода.
private func feed(_ data: Data, to handle: FileHandle) {
    // Без этого запись в трубу вышедшего процесса шлёт SIGPIPE, и он убивает
    // всё приложение, а не одну команду.
    _ = fcntl(handle.fileDescriptor, F_SETNOSIGPIPE, 1)
    DispatchQueue.global(qos: .utility).async {
        // Процесс мог выйти, не дочитав, — тогда запись падает с EPIPE. Итог
        // решает его код выхода, а не то, сколько байт он успел взять.
        try? handle.write(contentsOf: data)
        try? handle.close()
    }
}

/// Ждёт завершения процесса, не полагаясь на то, что он ещё жив.
///
/// `terminationHandler`, установленный после фактического выхода, может не
/// сработать вовсе — и тогда быстрая команда подвешивает вызывающего навсегда.
/// Защёлка гарантирует ровно одно возобновление, кто бы ни успел первым.
private func waitForExit(_ process: Process) async {
    await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
        let latch = ExitLatch()
        process.terminationHandler = { _ in
            if latch.claim() { continuation.resume() }
        }
        // Процесс мог завершиться между запуском и установкой обработчика.
        if !process.isRunning, latch.claim() { continuation.resume() }
    }
}

/// Одноразовая защёлка: продолжение нельзя возобновить дважды.
private final class ExitLatch: @unchecked Sendable {
    // Ручная синхронизация намеренная: обе стороны гонки — обычные колбэки
    // Foundation, и единственное поле закрыто собственным замком.
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

/// Accumulates process output in the order it arrives.
///
/// Appends happen right in the pipe's handler, under a lock. Handing each
/// chunk to its own `Task` (as before) lets chunks of a large output land out
/// of order, or after the result was already read — a big JSON then comes
/// back shuffled.
private final class OutputCollector: @unchecked Sendable {
    // Ручная синхронизация намеренная: пишут обработчики Foundation на своих
    // очередях, читает вызывающий после выхода процесса; оба поля под замком.
    private let lock = NSLock()
    private var out = Data()
    private var err = Data()
    /// Сколько труб дошло до конца: их две, stdout и stderr.
    private var finished = 0
    private var timedOut = false
    private var waiter: CheckedContinuation<Void, Never>?

    func finish() {
        let resume: CheckedContinuation<Void, Never>? = lock.withLock {
            finished += 1
            guard finished == 2 else { return nil }
            defer { waiter = nil }
            return waiter
        }
        resume?.resume()
    }

    /// Returns when both pipes reached their end, or after `limit`.
    func drained(within limit: Duration) async {
        let timer = Task {
            // `try?`: сон прерывает только отмена — трубы закончились раньше.
            try? await Task.sleep(for: limit)
            guard !Task.isCancelled else { return }
            let resume: CheckedContinuation<Void, Never>? = lock.withLock {
                timedOut = true
                defer { waiter = nil }
                return waiter
            }
            resume?.resume()
        }
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let done: Bool = lock.withLock {
                if finished == 2 || timedOut { return true }
                waiter = continuation
                return false
            }
            if done { continuation.resume() }
        }
        timer.cancel()
    }

    func appendOut(_ data: Data) { lock.withLock { out.append(data) } }
    func appendErr(_ data: Data) { lock.withLock { err.append(data) } }
    var outText: String { lock.withLock { String(decoding: out, as: UTF8.self) } }
    var errText: String { lock.withLock { String(decoding: err, as: UTF8.self) } }
}

/// Splits a byte stream into lines, holding partial ones until they complete.
///
/// Fed synchronously from the pipe's handler, for the same reason as
/// `OutputCollector`: lines must come out in the order they were written.
private final class LineSplitter: @unchecked Sendable {
    // Ручная синхронизация: обработчик трубы вызывается последовательно, но
    // на чужой очереди; буфер под замком, `onLine` зовётся вне его.
    private let lock = NSLock()
    private var buffer = Data()
    private let onLine: @Sendable (String) -> Void

    init(onLine: @escaping @Sendable (String) -> Void) { self.onLine = onLine }

    func feed(_ data: Data) {
        let lines: [String] = lock.withLock {
            buffer.append(data)
            var lines: [String] = []
            while let index = buffer.firstIndex(of: 0x0A) {
                lines.append(String(decoding: buffer[buffer.startIndex..<index], as: UTF8.self))
                buffer = buffer[buffer.index(after: index)...]
            }
            // A line that never ends must not grow without bound.
            if buffer.count > 1 << 20 { buffer.removeAll(keepingCapacity: false) }
            return lines
        }
        lines.forEach(onLine)
    }
}
