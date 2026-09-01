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
        timeout: Duration = .seconds(30)
    ) async throws -> CommandResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        let outPipe = Pipe(), errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe

        let collector = OutputCollector()
        outPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if !data.isEmpty { Task { await collector.appendOut(data) } }
        }
        errPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if !data.isEmpty { Task { await collector.appendErr(data) } }
        }

        try process.run()

        let deadline = Task {
            try await Task.sleep(for: timeout)
            if process.isRunning { process.terminate() }
        }
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            process.terminationHandler = { _ in continuation.resume() }
        }
        deadline.cancel()
        outPipe.fileHandleForReading.readabilityHandler = nil
        errPipe.fileHandleForReading.readabilityHandler = nil

        // Anything buffered between the last handler call and exit.
        let tailOut = try? outPipe.fileHandleForReading.readToEnd()
        let tailErr = try? errPipe.fileHandleForReading.readToEnd()
        if let tailOut, !tailOut.isEmpty { await collector.appendOut(tailOut) }
        if let tailErr, !tailErr.isEmpty { await collector.appendErr(tailErr) }

        return await CommandResult(
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
            Task { await splitter.feed(data) }
        }
        try process.run()
        await withTaskCancellationHandler {
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                process.terminationHandler = { _ in continuation.resume() }
            }
        } onCancel: {
            process.terminate()
        }
        pipe.fileHandleForReading.readabilityHandler = nil
    }
}

/// Accumulates process output off the main actor.
private actor OutputCollector {
    private var out = Data()
    private var err = Data()

    func appendOut(_ data: Data) { out.append(data) }
    func appendErr(_ data: Data) { err.append(data) }
    var outText: String { String(decoding: out, as: UTF8.self) }
    var errText: String { String(decoding: err, as: UTF8.self) }
}

/// Splits a byte stream into lines, holding partial ones until they complete.
private actor LineSplitter {
    private var buffer = Data()
    private let onLine: @Sendable (String) -> Void

    init(onLine: @escaping @Sendable (String) -> Void) { self.onLine = onLine }

    func feed(_ data: Data) {
        buffer.append(data)
        while let index = buffer.firstIndex(of: 0x0A) {
            let line = buffer[buffer.startIndex..<index]
            buffer = buffer[buffer.index(after: index)...]
            onLine(String(decoding: line, as: UTF8.self))
        }
        // A line that never ends must not grow without bound.
        if buffer.count > 1 << 20 { buffer.removeAll(keepingCapacity: false) }
    }
}
