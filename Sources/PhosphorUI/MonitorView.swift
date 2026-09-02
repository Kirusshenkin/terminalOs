public import MetricsKit
public import PhosphorCore
public import SessionKit
public import SwiftUI

/// Всё, что известно о состоянии сервера, на одном экране.
public struct MonitorView: View {
    @Environment(\.style) private var style
    let model: AppModel

    public init(model: AppModel) { self.model = model }

    private var strings: Strings { model.strings }
    private var snapshot: Snapshot? { model.sessionState.latest }
    private var isLive: Bool { snapshot != nil }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            summary
            Rule()
            HStack(alignment: .top, spacing: 20) {
                cores
                Rectangle().fill(style.rule).frame(width: 1)
                middle
                Rectangle().fill(style.rule).frame(width: 1)
                right
            }
            Spacer(minLength: 0)
        }
    }

    /// Верхняя строка: то, что хочется знать, не читая ничего дальше.
    private var summary: some View {
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            stat("аптайм", snapshot.map { ByteFormat.duration(seconds: $0.uptime) } ?? "—")
            stat(
                "load",
                snapshot.map {
                    String(format: "%.2f %.2f %.2f", $0.loadOne, $0.loadFive, $0.loadFifteen)
                } ?? "—")
            stat("процессы", snapshot.map { "\($0.runningProcesses) из \($0.totalProcesses)" } ?? "—")
            stat("память", snapshot.map { ByteFormat.percent($0.memoryUsage) } ?? "—")
            stat("дескрипторы", snapshot.map { "\($0.openFiles)" } ?? "—")
            stat("контейнеры", containersSummary)
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(snapshot?.cpuModel.isEmpty == false ? snapshot?.cpuModel ?? "" : "—")
                    .font(style.font(11)).foregroundStyle(style.muted).lineLimit(1)
                Text(snapshot.map { "ядро \($0.kernel)" } ?? "нет соединения")
                    .font(style.font(11)).foregroundStyle(style.muted)
            }
        }
    }

    private var containersSummary: String {
        let all = model.sessionState.containers
        guard !all.isEmpty else { return "—" }
        let running = all.filter { $0.state == .running }.count
        let sick = all.filter(\.isUnhealthy).count
        return sick > 0 ? "\(running)/\(all.count) · \(sick) больных" : "\(running) из \(all.count)"
    }

    private func stat(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Label2(title)
            Text(value).font(style.font(14)).foregroundStyle(style.bright)
        }
        .frame(minWidth: 118, alignment: .leading)
    }

    // MARK: - Ядра

    private var cores: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label2("\(strings("monitor.cores")) · \(usage.count)")
            ForEach(Array(usage.enumerated()), id: \.offset) { index, value in
                HStack(spacing: 8) {
                    Text("\(index)")
                        .font(style.font(11)).foregroundStyle(style.muted)
                        .frame(width: 16, alignment: .trailing)
                    Bar(fraction: value, colour: value > 0.7 ? style.warning : style.accent)
                    Text(ByteFormat.percent(value))
                        .font(style.font(11))
                        .foregroundStyle(value > 0.7 ? style.warning : style.text)
                        .frame(width: 44, alignment: .trailing)
                    // Steal — это сосед по гипервизору. Ничего, что ты сделаешь
                    // на сервере, его не уменьшит, поэтому он отдельной цифрой.
                    Text(
                        steal.indices.contains(index) && steal[index] > 0.005
                            ? "steal \(ByteFormat.percent(steal[index]))" : " "
                    )
                    .font(style.font(10)).foregroundStyle(style.warning.opacity(0.8))
                    .frame(width: 78, alignment: .leading)
                }
            }
            if usage.isEmpty {
                Text("ждём второго снимка: загрузка — это разница")
                    .font(style.font(11)).foregroundStyle(style.muted)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var usage: [Double] {
        let live = model.sessionState.coreUsage
        return live.isEmpty ? (isLive ? [] : Self.demoCores) : live
    }

    private var steal: [Double] { model.sessionState.coreSteal }

    // MARK: - Память, диски

    private var middle: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Label2("\(strings("monitor.memory")) · MemAvailable")
                Bar(fraction: snapshot?.memoryUsage ?? 0.36, colour: style.accent)
                HStack {
                    Text(
                        snapshot.map {
                            "\(ByteFormat.size($0.memoryUsed)) из \(ByteFormat.size($0.memoryTotal))"
                        } ?? "—")
                    Spacer()
                    Text(swapLine).foregroundStyle(swapUsed > 0.01 ? style.warning : style.muted)
                }
                .font(style.font(11.5))
                .foregroundStyle(style.bright)
            }

            VStack(alignment: .leading, spacing: 6) {
                Label2(strings("monitor.disks"))
                ForEach(disks, id: \.0) { disk in
                    VStack(alignment: .leading, spacing: 3) {
                        HStack {
                            Text(disk.0).font(style.font(11.5)).foregroundStyle(style.text)
                            Spacer()
                            Text(disk.2).font(style.font(10.5)).foregroundStyle(style.muted)
                            Text(ByteFormat.percent(disk.1))
                                .font(style.font(11.5))
                                .foregroundStyle(disk.1 > 0.8 ? style.warning : style.text)
                                .frame(width: 44, alignment: .trailing)
                        }
                        Bar(fraction: disk.1, colour: disk.1 > 0.8 ? style.warning : style.accent)
                    }
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Label2("диск: чтение и запись")
                if model.sessionState.diskThroughput.isEmpty {
                    Text("—").font(style.font(11.5)).foregroundStyle(style.muted)
                }
                ForEach(model.sessionState.diskThroughput, id: \.name) { flow in
                    HStack {
                        Text(flow.name).foregroundStyle(style.muted)
                        Spacer()
                        Text("↓ \(ByteFormat.size(Int64(flow.down)))/с")
                        Text("↑ \(ByteFormat.size(Int64(flow.up)))/с")
                    }
                    .font(style.font(11.5))
                    .foregroundStyle(style.text)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var swapUsed: Double {
        guard let snapshot, snapshot.swapTotal > 0 else { return 0 }
        return Double(snapshot.swapTotal - snapshot.swapFree) / Double(snapshot.swapTotal)
    }

    private var swapLine: String {
        guard let snapshot else { return "swap —" }
        guard snapshot.swapTotal > 0 else { return "swap отсутствует" }
        return "swap \(ByteFormat.size(snapshot.swapTotal - snapshot.swapFree))"
            + " из \(ByteFormat.size(snapshot.swapTotal))"
    }

    private var disks: [(String, Double, String)] {
        guard let snapshot, !snapshot.filesystems.isEmpty else {
            return Self.demoDisks.map { ($0.0, $0.1, "—") }
        }
        return snapshot.filesystems.map {
            ($0.mount, $0.usage, "свободно \(ByteFormat.size($0.available))")
        }
    }

    // MARK: - Сеть, процессы, контейнеры

    private var right: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Label2(strings("monitor.network"))
                if model.sessionState.throughput.isEmpty {
                    Text("—").font(style.font(11.5)).foregroundStyle(style.muted)
                }
                ForEach(model.sessionState.throughput, id: \.name) { flow in
                    HStack {
                        Text(flow.name).foregroundStyle(style.muted)
                        Spacer()
                        Text("↓ \(ByteFormat.size(Int64(flow.down)))/с")
                        Text("↑ \(ByteFormat.size(Int64(flow.up)))/с")
                    }
                    .font(style.font(11.5))
                    .foregroundStyle(style.text)
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Label2("самые тяжёлые процессы")
                if snapshot?.processes.isEmpty ?? true {
                    Text("—").font(style.font(11.5)).foregroundStyle(style.muted)
                }
                ForEach(snapshot?.processes ?? [], id: \.pid) { process in
                    HStack(spacing: 8) {
                        Text("\(process.pid)")
                            .foregroundStyle(style.muted).frame(width: 52, alignment: .trailing)
                        Text(process.command).foregroundStyle(style.text).lineLimit(1)
                        Spacer()
                        Text(ByteFormat.percent(process.cpu))
                            .foregroundStyle(process.cpu > 0.5 ? style.warning : style.text)
                        Text(ByteFormat.percent(process.memory)).foregroundStyle(style.muted)
                    }
                    .font(style.font(11.5))
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Label2("контейнеры")
                if model.sessionState.containers.isEmpty {
                    Text("—").font(style.font(11.5)).foregroundStyle(style.muted)
                }
                ForEach(model.sessionState.containers) { container in
                    let stats = model.sessionState.stats[container.name]
                    HStack(spacing: 8) {
                        Text(container.state == .running ? "●" : "○")
                            .foregroundStyle(
                                container.isUnhealthy
                                    ? style.warning
                                    : container.state == .running ? style.accent : style.muted)
                        Text(container.name).foregroundStyle(style.text).lineLimit(1)
                        Spacer()
                        Text(stats.map { ByteFormat.percent($0.cpu) } ?? "—")
                            .foregroundStyle(style.muted)
                        Text(stats.map { ByteFormat.size($0.memoryUsed) } ?? "—")
                            .foregroundStyle(style.muted)
                    }
                    .font(style.font(11.5))
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private static let demoCores: [Double] = [0.62, 0.18, 0.44, 0.09, 0.77, 0.23, 0.31, 0.12]
    private static let demoDisks: [(String, Double)] = [
        ("/", 0.85), ("/var/lib/docker", 0.30), ("/backups", 0.55),
    ]
}

/// Тонкая полоса заполнения.
struct Bar: View {
    @Environment(\.style) private var style
    var fraction: Double
    var colour: Color

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Rectangle().fill(style.text.opacity(0.12))
                Rectangle().fill(colour)
                    .frame(width: geometry.size.width * min(max(fraction, 0), 1))
            }
        }
        .frame(height: 5)
    }
}
