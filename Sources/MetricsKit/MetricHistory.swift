public import Foundation

/// Одна точка на графике: то, что осталось от снимка после свёртки.
///
/// Снимок целиком хранить незачем — в нём процессы, файловые системы и
/// счётчики, а графику нужны восемь чисел. Разница между хранением того и
/// другого за час — десятки мегабайт.
public struct MetricPoint: Sendable, Equatable {
    public var time: Date
    /// Средняя загрузка ядер за интервал между снимками, 0…1.
    public var cpu: Double
    /// Занятая память и swap, 0…1.
    public var memory: Double
    public var swap: Double
    /// Байты в секунду по всем интерфейсам и дискам разом: на графике за час
    /// интересна форма нагрузки, а разбор по устройствам есть на своих страницах.
    public var networkIn: Double
    public var networkOut: Double
    public var diskRead: Double
    public var diskWrite: Double

    public init(
        time: Date, cpu: Double, memory: Double, swap: Double,
        networkIn: Double, networkOut: Double, diskRead: Double, diskWrite: Double
    ) {
        self.time = time
        self.cpu = cpu
        self.memory = memory
        self.swap = swap
        self.networkIn = networkIn
        self.networkOut = networkOut
        self.diskRead = diskRead
        self.diskWrite = diskWrite
    }

    /// Точка из пары снимков. Одного снимка не хватает: загрузка процессора и
    /// скорости — это дельты, и по одному значению они не считаются.
    ///
    /// Локальный интерфейс пропускаем: трафик по `lo` — это разговор машины с
    /// самой собой, и на графике он заслоняет настоящую сеть.
    public static func between(_ previous: Snapshot, _ current: Snapshot) -> MetricPoint {
        let usage = SnapshotParser.usage(from: previous, to: current)
        let network = SnapshotParser.throughput(from: previous, to: current)
            .filter { $0.name != "lo" }
        let disk = SnapshotParser.diskThroughput(from: previous, to: current)
        let swapUsed = current.swapTotal - current.swapFree
        return MetricPoint(
            time: current.time,
            cpu: usage.isEmpty ? 0 : usage.reduce(0, +) / Double(usage.count),
            memory: current.memoryUsage,
            swap: current.swapTotal > 0 ? Double(swapUsed) / Double(current.swapTotal) : 0,
            networkIn: network.reduce(0) { $0 + $1.down },
            networkOut: network.reduce(0) { $0 + $1.up },
            diskRead: disk.reduce(0) { $0 + $1.down },
            diskWrite: disk.reduce(0) { $0 + $1.up }
        )
    }
}
