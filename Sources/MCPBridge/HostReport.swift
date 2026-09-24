public import DockerKit
public import MetricsKit
public import PhosphorCore
public import SessionKit

/// Одна страница о состоянии хоста — то, ради чего иначе пришлось бы сделать
/// четыре вызова и самому знать пороги.
///
/// Смысл не в экономии вызовов, а в том, что порог — это знание о системе, а не
/// о числе. Модель, получив «диск / 91 %», должна откуда-то знать, что 91 — это
/// плохо, а 61 — нет; «steal 12 %» — что виноват не хост, а сосед по
/// гипервизору. Здесь это знание уже применено: сначала список того, что не в
/// порядке, потом факты, на которых он построен.
public enum HostReport {
    /// Порог, после которого место на диске перестаёт быть чужой заботой.
    static let diskWarning = 0.85
    static let memoryWarning = 0.90
    /// Нагрузка на ядро: 1.0 — очередь длиной в одно ядро.
    static let loadWarning = 1.5
    /// Украденное гипервизором время, после которого хост не виноват.
    static let stealWarning = 0.05

    /// Собирает отчёт из того, что сессия уже знает. Ничего не спрашивает у
    /// сервера: это чистая функция над снимком, и тестируется как функция.
    public static func text(_ state: SessionState) -> String {
        guard let snapshot = state.latest else {
            return "metrics not yet collected — session just opened"
        }

        var trouble: [String] = []

        for filesystem in snapshot.filesystems where filesystem.usage >= diskWarning {
            trouble.append(
                "disk \(filesystem.mount) used \(ByteFormat.percent(filesystem.usage))"
                    + ", free \(ByteFormat.size(filesystem.available, units: .english))")
        }
        if snapshot.memoryUsage >= memoryWarning {
            trouble.append("memory used \(ByteFormat.percent(snapshot.memoryUsage))")
        }
        if snapshot.swapTotal > 0 {
            let used = snapshot.swapTotal - snapshot.swapFree
            if Double(used) / Double(snapshot.swapTotal) >= 0.5 {
                trouble.append("swap used \(ByteFormat.size(used, units: .english))")
            }
        }
        let cores = max(snapshot.cores.count, 1)
        if snapshot.loadOne / Double(cores) >= loadWarning {
            trouble.append(
                "load \(snapshot.loadOne) on \(cores) cores — queue longer than cpu")
        }
        let steal = state.coreSteal.enumerated().filter { $0.element >= stealWarning }
        if !steal.isEmpty {
            let cpus = steal.map { "cpu\($0.offset)" }.joined(separator: ", ")
            trouble.append("hypervisor steals time from \(cpus) — not host fault")
        }

        let unhealthy = state.containers.filter { $0.health == "unhealthy" }
        if !unhealthy.isEmpty {
            trouble.append(
                "unhealthy: " + unhealthy.map(\.name).joined(separator: ", "))
        }
        let stopped = state.containers.filter { $0.state != .running }
        if !stopped.isEmpty {
            trouble.append("not running: " + stopped.map(\.name).joined(separator: ", "))
        }

        let verdict =
            trouble.isEmpty
            ? "all is ok"
            : "issues:\n" + trouble.map { "  · \($0)" }.joined(separator: "\n")

        let disks = snapshot.filesystems
            .map { "\($0.mount) \(ByteFormat.percent($0.usage))" }
            .joined(separator: ", ")
        let running = state.containers.filter { $0.state == .running }.count

        return """
            \(verdict)

            uptime: \(ByteFormat.duration(seconds: snapshot.uptime, units: .english))
            load: \(snapshot.loadOne) \(snapshot.loadFive) \(snapshot.loadFifteen) \
            on \(cores) cores
            memory: \(ByteFormat.size(snapshot.memoryUsed, units: .english)) of \
            \(ByteFormat.size(snapshot.memoryTotal, units: .english))
            disks: \(disks.isEmpty ? "—" : disks)
            processes: \(snapshot.runningProcesses) of \(snapshot.totalProcesses)
            containers: \(running) of \(state.containers.count) running
            """
    }
}
