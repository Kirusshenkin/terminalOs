public import DockerKit
public import PhosphorCore
public import MetricsKit
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
            return "метрики ещё не собраны — сессия только что открылась"
        }

        var trouble: [String] = []

        for filesystem in snapshot.filesystems where filesystem.usage >= diskWarning {
            trouble.append(
                "диск \(filesystem.mount) занят на \(ByteFormat.percent(filesystem.usage))"
                    + ", свободно \(ByteFormat.size(filesystem.available))")
        }
        if snapshot.memoryUsage >= memoryWarning {
            trouble.append("память занята на \(ByteFormat.percent(snapshot.memoryUsage))")
        }
        if snapshot.swapTotal > 0 {
            let used = snapshot.swapTotal - snapshot.swapFree
            if Double(used) / Double(snapshot.swapTotal) >= 0.5 {
                trouble.append("swap занят на \(ByteFormat.size(used))")
            }
        }
        let cores = max(snapshot.cores.count, 1)
        if snapshot.loadOne / Double(cores) >= loadWarning {
            trouble.append(
                "нагрузка \(snapshot.loadOne) на \(cores) ядер — очередь длиннее, чем железо")
        }
        let steal = state.coreSteal.enumerated().filter { $0.element >= stealWarning }
        if !steal.isEmpty {
            let cpus = steal.map { "cpu\($0.offset)" }.joined(separator: ", ")
            trouble.append("гипервизор отнимает время у \(cpus) — это не вина хоста")
        }

        let unhealthy = state.containers.filter { $0.health == "unhealthy" }
        if !unhealthy.isEmpty {
            trouble.append(
                "нездоровы: " + unhealthy.map(\.name).joined(separator: ", "))
        }
        let stopped = state.containers.filter { $0.state != .running }
        if !stopped.isEmpty {
            trouble.append("не работают: " + stopped.map(\.name).joined(separator: ", "))
        }

        let verdict =
            trouble.isEmpty
            ? "всё в порядке"
            : "не в порядке:\n" + trouble.map { "  · \($0)" }.joined(separator: "\n")

        let disks = snapshot.filesystems
            .map { "\($0.mount) \(ByteFormat.percent($0.usage))" }
            .joined(separator: ", ")
        let running = state.containers.filter { $0.state == .running }.count

        return """
            \(verdict)

            аптайм: \(ByteFormat.duration(seconds: snapshot.uptime))
            загрузка: \(snapshot.loadOne) \(snapshot.loadFive) \(snapshot.loadFifteen) \
            на \(cores) ядер
            память: \(ByteFormat.size(snapshot.memoryUsed)) из \
            \(ByteFormat.size(snapshot.memoryTotal))
            диски: \(disks.isEmpty ? "—" : disks)
            процессы: \(snapshot.runningProcesses) из \(snapshot.totalProcesses)
            контейнеры: \(running) из \(state.containers.count) работают
            """
    }
}
