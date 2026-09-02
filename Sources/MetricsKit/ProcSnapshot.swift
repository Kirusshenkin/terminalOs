public import Foundation
public import PhosphorCore

/// One reading of a server's vital signs.
///
/// Collected by a single long-lived channel printing prefixed records every two
/// seconds, rather than a storm of exec calls.
public struct Snapshot: Sendable, Equatable {
    public struct Core: Sendable, Equatable {
        public var index: Int
        /// Raw jiffy counters; usage is a delta between two snapshots.
        public var total: UInt64
        public var idle: UInt64
        public var steal: UInt64
    }

    public struct Filesystem: Sendable, Equatable {
        public var mount: String
        public var total: Int64
        public var used: Int64
        public var available: Int64
        public var usage: Double { total > 0 ? Double(used) / Double(total) : 0 }
    }

    public struct Interface: Sendable, Equatable {
        public var name: String
        public var received: UInt64
        public var sent: UInt64
    }

    /// Счётчики блочного устройства из `/proc/diskstats`.
    public struct Disk: Sendable, Equatable {
        public var name: String
        /// Секторы по 512 байт — так их печатает ядро.
        public var sectorsRead: UInt64
        public var sectorsWritten: UInt64
    }

    /// Самый заметный процесс: имя и доля процессора.
    public struct Process: Sendable, Equatable {
        public var pid: Int
        public var command: String
        public var cpu: Double
        public var memory: Double
    }

    public var time: Date
    public var loadOne: Double
    public var loadFive: Double
    public var loadFifteen: Double
    public var uptime: Int
    public var cores: [Core]
    public var memoryTotal: Int64
    public var memoryAvailable: Int64
    public var swapTotal: Int64
    public var swapFree: Int64
    public var filesystems: [Filesystem]
    public var interfaces: [Interface]
    public var disks: [Disk]
    public var processes: [Process]
    /// Работающих и всего — четвёртое поле `/proc/loadavg`.
    public var runningProcesses: Int
    public var totalProcesses: Int
    /// Открытых файловых дескрипторов в системе.
    public var openFiles: Int
    public var kernel: String
    public var cpuModel: String

    /// Memory actually in use, from `MemAvailable` — the honest figure, unlike
    /// `MemFree`, which counts cache as gone.
    public var memoryUsed: Int64 { max(0, memoryTotal - memoryAvailable) }
    public var memoryUsage: Double { memoryTotal > 0 ? Double(memoryUsed) / Double(memoryTotal) : 0 }
}

/// The command whose output `SnapshotParser` reads.
public enum ProcProbe {
    /// Неизменная часть: спрашивается один раз, потому что за жизнь сессии
    /// модель процессора и версия ядра не меняются.
    public static let once = """
        echo "K $(uname -r)"; \
        echo "P $(sed -n 's/^model name[[:space:]]*: //p' /proc/cpuinfo | head -1 \
            || echo unknown)"
        """

    public static func loop(interval: Int = 2) -> String {
        """
        while :; do \
        echo "T $(date +%s)"; \
        echo "L $(cat /proc/loadavg)"; \
        echo "U $(cat /proc/uptime)"; \
        sed -n 's/^cpu/C cpu/p' /proc/stat; \
        awk '/^(MemTotal|MemAvailable|SwapTotal|SwapFree):/{print "M",$1,$2}' /proc/meminfo; \
        df -PB1 -x tmpfs -x devtmpfs 2>/dev/null | awk 'NR>1{print "D",$6,$2,$3,$4}'; \
        awk 'NR>2{gsub(":","",$1); print "N",$1,$2,$10}' /proc/net/dev; \
        awk '$3 ~ /^(sd[a-z]|nvme[0-9]+n[0-9]+|vd[a-z]|xvd[a-z])$/ \
            {print "B",$3,$6,$10}' /proc/diskstats; \
        echo "F $(cat /proc/sys/fs/file-nr 2>/dev/null | awk '{print $1}' || echo 0)"; \
        ps -eo pid=,pcpu=,pmem=,comm= --sort=-pcpu 2>/dev/null | head -6 \
            | awk '{print "S",$1,$2,$3,$4}'; \
        echo "---"; sleep \(interval); done
        """
    }
}

/// Turns one record block into a `Snapshot`.
public enum SnapshotParser {
    /// Values accumulated while walking the block.
    private struct Builder {
        var time = Date()
        var load = (one: 0.0, five: 0.0, fifteen: 0.0)
        var uptime = 0
        var cores: [Snapshot.Core] = []
        var memoryTotal: Int64 = 0
        var memoryAvailable: Int64 = 0
        var swapTotal: Int64 = 0
        var swapFree: Int64 = 0
        var filesystems: [Snapshot.Filesystem] = []
        var interfaces: [Snapshot.Interface] = []
        var disks: [Snapshot.Disk] = []
        var processes: [Snapshot.Process] = []
        var running = 0
        var total = 0
        var openFiles = 0
        var kernel = ""
        var cpuModel = ""
        var sawCore = false
    }

    /// Parses the lines between two `---` markers. Unknown prefixes are ignored
    /// so a server printing extra noise does not break collection.
    public static func parse(_ block: String) -> Snapshot? {
        var builder = Builder()
        for line in block.components(separatedBy: .newlines) {
            let fields = line.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
            guard let tag = fields.first else { continue }
            apply(tag: tag, fields: fields, to: &builder)
        }
        guard builder.sawCore || builder.memoryTotal > 0 else { return nil }
        return Snapshot(
            time: builder.time,
            loadOne: builder.load.one, loadFive: builder.load.five, loadFifteen: builder.load.fifteen,
            uptime: builder.uptime,
            cores: builder.cores.sorted { $0.index < $1.index },
            memoryTotal: builder.memoryTotal, memoryAvailable: builder.memoryAvailable,
            swapTotal: builder.swapTotal, swapFree: builder.swapFree,
            filesystems: builder.filesystems, interfaces: builder.interfaces,
            disks: builder.disks, processes: builder.processes,
            runningProcesses: builder.running, totalProcesses: builder.total,
            openFiles: builder.openFiles, kernel: builder.kernel, cpuModel: builder.cpuModel
        )
    }

    /// Записи снимка, по одной букве на вид данных.
    private enum Record: String {
        case time = "T"
        case load = "L"
        case uptime = "U"
        case core = "C"
        case memory = "M"
        case disk = "D"
        case network = "N"
        case block = "B"
        case files = "F"
        case process = "S"
        case kernel = "K"
        case cpu = "P"
    }

    private static func apply(tag: String, fields: [String], to builder: inout Builder) {
        switch Record(rawValue: tag) {
        case .time: builder.time = time(from: fields) ?? builder.time
        case .load:
            builder.load = load(from: fields) ?? builder.load
            if let counts = processCounts(from: fields) {
                builder.running = counts.running
                builder.total = counts.total
            }
        case .uptime: builder.uptime = uptime(from: fields) ?? builder.uptime
        case .core: appendCore(fields, to: &builder)
        case .memory: memory(from: fields, into: &builder)
        case .disk: filesystem(from: fields).map { builder.filesystems.append($0) }
        case .network, .block, .files, .process, .kernel, .cpu:
            applyExtras(tag: tag, fields: fields, to: &builder)
        case nil: break
        }
    }

    /// Записи, добавленные позже основных: диски, процессы, неизменное.
    private static func applyExtras(tag: String, fields: [String], to builder: inout Builder) {
        switch Record(rawValue: tag) {
        case .network: interface(from: fields).map { builder.interfaces.append($0) }
        case .block: disk(from: fields).map { builder.disks.append($0) }
        case .files: builder.openFiles = Int(fields.count > 1 ? fields[1] : "0") ?? 0
        case .process: process(from: fields).map { builder.processes.append($0) }
        case .kernel: builder.kernel = fields.dropFirst().joined(separator: " ")
        case .cpu: builder.cpuModel = fields.dropFirst().joined(separator: " ")
        default: break
        }
    }

    private static func time(from fields: [String]) -> Date? {
        guard fields.count > 1, let seconds = Double(fields[1]) else { return nil }
        return Date(timeIntervalSince1970: seconds)
    }

    private static func load(from fields: [String]) -> (one: Double, five: Double, fifteen: Double)? {
        guard fields.count > 3 else { return nil }
        return (Double(fields[1]) ?? 0, Double(fields[2]) ?? 0, Double(fields[3]) ?? 0)
    }

    /// Четвёртое поле `/proc/loadavg` — `работающих/всего`.
    private static func processCounts(from fields: [String]) -> (running: Int, total: Int)? {
        guard fields.count > 4 else { return nil }
        let parts = fields[4].split(separator: "/")
        guard parts.count == 2, let running = Int(parts[0]), let total = Int(parts[1]) else {
            return nil
        }
        return (running, total)
    }

    private static func disk(from fields: [String]) -> Snapshot.Disk? {
        guard fields.count >= 4,
            let read = UInt64(fields[2]), let written = UInt64(fields[3])
        else { return nil }
        return Snapshot.Disk(name: fields[1], sectorsRead: read, sectorsWritten: written)
    }

    private static func process(from fields: [String]) -> Snapshot.Process? {
        guard fields.count >= 5, let pid = Int(fields[1]) else { return nil }
        return Snapshot.Process(
            pid: pid,
            command: fields[4...].joined(separator: " "),
            cpu: (Double(fields[2]) ?? 0) / 100,
            memory: (Double(fields[3]) ?? 0) / 100
        )
    }

    private static func uptime(from fields: [String]) -> Int? {
        guard fields.count > 1, let value = Double(fields[1]) else { return nil }
        return Int(value)
    }

    private static func appendCore(_ fields: [String], to builder: inout Builder) {
        guard fields.count > 1, fields[1].hasPrefix("cpu") else { return }
        builder.sawCore = true
        if let core = core(from: fields) { builder.cores.append(core) }
    }

    /// `C cpuN user nice system idle iowait irq softirq steal …`
    private static func core(from fields: [String]) -> Snapshot.Core? {
        guard fields.count >= 10, fields[1].hasPrefix("cpu"), fields[1] != "cpu",
            let index = Int(fields[1].dropFirst(3))
        else { return nil }
        let numbers = fields[2...].compactMap(UInt64.init)
        guard numbers.count >= 8 else { return nil }
        return Snapshot.Core(
            index: index,
            total: numbers.reduce(0, &+),
            idle: numbers[3] &+ numbers[4],
            steal: numbers[7]
        )
    }

    private static func memory(from fields: [String], into builder: inout Builder) {
        guard fields.count >= 3, let kilobytes = Int64(fields[2]) else { return }
        let bytes = kilobytes * 1024
        switch fields[1] {
        case "MemTotal:": builder.memoryTotal = bytes
        case "MemAvailable:": builder.memoryAvailable = bytes
        case "SwapTotal:": builder.swapTotal = bytes
        case "SwapFree:": builder.swapFree = bytes
        default: break
        }
    }

    private static func filesystem(from fields: [String]) -> Snapshot.Filesystem? {
        guard fields.count >= 5,
            let total = Int64(fields[2]), let used = Int64(fields[3]), let available = Int64(fields[4])
        else { return nil }
        return Snapshot.Filesystem(mount: fields[1], total: total, used: used, available: available)
    }

    private static func interface(from fields: [String]) -> Snapshot.Interface? {
        guard fields.count >= 4, fields[1] != "lo",
            let received = UInt64(fields[2]), let sent = UInt64(fields[3])
        else { return nil }
        return Snapshot.Interface(name: fields[1], received: received, sent: sent)
    }

    /// Per-core usage between two snapshots, as fractions of 1.
    ///
    /// `/proc/stat` counts jiffies since boot, so a single reading says nothing;
    /// usage only exists as a difference.
    public static func usage(from previous: Snapshot, to current: Snapshot) -> [Double] {
        zip(previous.cores, current.cores).map { old, new in
            let total = new.total >= old.total ? new.total - old.total : 0
            let idle = new.idle >= old.idle ? new.idle - old.idle : 0
            guard total > 0 else { return 0 }
            return min(1, max(0, 1 - Double(idle) / Double(total)))
        }
    }

    /// Steal time between two snapshots — on a VPS this is a neighbour eating
    /// your CPU, and nothing you do on the server will fix it.
    public static func steal(from previous: Snapshot, to current: Snapshot) -> [Double] {
        zip(previous.cores, current.cores).map { old, new in
            let total = new.total >= old.total ? new.total - old.total : 0
            let steal = new.steal >= old.steal ? new.steal - old.steal : 0
            guard total > 0 else { return 0 }
            return min(1, Double(steal) / Double(total))
        }
    }

    /// Скорость на интерфейсе между двумя снимками.
    public struct Throughput: Sendable, Equatable {
        public var name: String
        public var down: Double
        public var up: Double
    }

    /// Bytes per second per interface between two snapshots.
    /// Скорость чтения и записи на диск между снимками, в байтах в секунду.
    ///
    /// Ядро считает секторами по 512 байт — переводим сразу, чтобы дальше никто
    /// не гадал, в чём измеряется число.
    public static func diskThroughput(from previous: Snapshot, to current: Snapshot) -> [Throughput] {
        let seconds = max(0.5, current.time.timeIntervalSince(previous.time))
        var byName: [String: Snapshot.Disk] = [:]
        for item in previous.disks { byName[item.name] = item }
        return current.disks.compactMap { new in
            guard let old = byName[new.name] else { return nil }
            let read =
                new.sectorsRead >= old.sectorsRead
                ? Double(new.sectorsRead - old.sectorsRead) * 512 / seconds : 0
            let written =
                new.sectorsWritten >= old.sectorsWritten
                ? Double(new.sectorsWritten - old.sectorsWritten) * 512 / seconds : 0
            return Throughput(name: new.name, down: read, up: written)
        }
    }

    public static func throughput(from previous: Snapshot, to current: Snapshot) -> [Throughput] {
        let seconds = max(0.5, current.time.timeIntervalSince(previous.time))
        var byName: [String: Snapshot.Interface] = [:]
        for item in previous.interfaces { byName[item.name] = item }
        return current.interfaces.compactMap { new in
            guard let old = byName[new.name] else { return nil }
            let down = new.received >= old.received ? Double(new.received - old.received) / seconds : 0
            let up = new.sent >= old.sent ? Double(new.sent - old.sent) / seconds : 0
            return Throughput(name: new.name, down: down, up: up)
        }
    }
}
