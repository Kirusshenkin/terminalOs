public import MetricsKit
public import PhosphorCore
public import SessionKit
public import SwiftUI

/// Всё, что известно о состоянии сервера, на одном экране.
public struct MonitorView: View {
    @Environment(\.style) private var style
    @Bindable var model: AppModel

    public init(model: AppModel) { self.model = model }

    private var strings: Strings { model.strings }
    private var snapshot: Snapshot? { model.sessionState.latest }
    private var isLive: Bool { snapshot != nil }

    public var body: some View {
        HStack(alignment: .top, spacing: 22) {
            SectionNav(title: strings("tab.monitor"), strings: strings, page: $model.monitorPage)
            Rectangle().fill(style.rule).frame(width: 1)
            VStack(alignment: .leading, spacing: 12) {
                summary
                Rule()
                page
                Spacer(minLength: 0)
            }
        }
    }

    /// Каждая страница показывает своё во всю ширину, а не втискивается
    /// в треть экрана рядом с двумя другими.
    @ViewBuilder private var page: some View {
        switch model.monitorPage {
        case .overview:
            if model.session == nil {
                HostPicker(
                    model: model,
                    title: strings("tab.monitor"),
                    note: strings("mon.pickNote")
                )
                .frame(maxWidth: 320, alignment: .leading)
            } else {
                HStack(alignment: .top, spacing: 20) {
                    cores
                    Rectangle().fill(style.rule).frame(width: 1)
                    middle
                }
            }
        case .processes: processes
        case .storage: middle
        case .network: right
        }
    }

    /// Полный список процессов, а не пять строк в углу.
    private var processes: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label2(strings("mon.topProcesses"))
            HStack(spacing: 10) {
                Label2("pid").frame(width: 70, alignment: .trailing)
                Label2(strings("mon.command")).frame(maxWidth: .infinity, alignment: .leading)
                Label2("cpu").frame(width: 70, alignment: .trailing)
                Label2(strings("mon.memory")).frame(width: 80, alignment: .trailing)
            }
            .padding(.bottom, 4)
            .overlay(alignment: .bottom) { Rule() }

            if snapshot?.processes.isEmpty ?? true {
                Text(strings("mon.noData"))
                    .font(style.font(12)).foregroundStyle(style.muted)
            }
            ForEach(snapshot?.processes ?? [], id: \.pid) { process in
                HStack(spacing: 10) {
                    Text("\(process.pid)")
                        .foregroundStyle(style.muted).frame(width: 70, alignment: .trailing)
                    Text(process.command)
                        .foregroundStyle(style.text)
                        .frame(maxWidth: .infinity, alignment: .leading).lineLimit(1)
                    Text(ByteFormat.percent(process.cpu))
                        .foregroundStyle(process.cpu > 0.5 ? style.warning : style.text)
                        .frame(width: 70, alignment: .trailing)
                    Text(ByteFormat.percent(process.memory))
                        .foregroundStyle(style.muted).frame(width: 80, alignment: .trailing)
                }
                .font(style.font(12))
                .padding(.vertical, 3)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Верхняя строка: то, что хочется знать, не читая ничего дальше.
    private var summary: some View {
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            stat(strings("mon.uptime"), snapshot.map { ByteFormat.duration(seconds: $0.uptime) } ?? "—")
            stat(
                "load",
                snapshot.map {
                    String(format: "%.2f %.2f %.2f", $0.loadOne, $0.loadFive, $0.loadFifteen)
                } ?? "—")
            stat(
                strings("mon.processes"),
                snapshot.map { "\($0.runningProcesses) \(strings("common.of")) \($0.totalProcesses)" } ?? "—")
            stat(strings("mon.memory"), snapshot.map { ByteFormat.percent($0.memoryUsage) } ?? "—")
            stat(strings("mon.handles"), snapshot.map { "\($0.openFiles)" } ?? "—")
            stat(strings("mon.containers"), containersSummary)
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(snapshot?.cpuModel.isEmpty == false ? snapshot?.cpuModel ?? "" : "—")
                    .font(style.font(11)).foregroundStyle(style.muted).lineLimit(1)
                Text(snapshot.map { "\(strings("mon.kernel")) \($0.kernel)" } ?? strings("mon.noLink"))
                    .font(style.font(11)).foregroundStyle(style.muted)
            }
        }
    }

    private var containersSummary: String {
        let all = model.sessionState.containers
        guard !all.isEmpty else { return "—" }
        let running = all.filter { $0.state == .running }.count
        let sick = all.filter(\.isUnhealthy).count
        return sick > 0
            ? "\(running)/\(all.count) · \(sick) \(strings("mon.sick"))"
            : "\(running) \(strings("common.of")) \(all.count)"
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
                Text(strings("mon.secondSnapshot"))
                    .font(style.font(11)).foregroundStyle(style.muted)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var usage: [Double] { model.sessionState.coreUsage }

    private var steal: [Double] { model.sessionState.coreSteal }

    // MARK: - Память, диски

    private var middle: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Label2("\(strings("monitor.memory")) · MemAvailable")
                Bar(fraction: snapshot?.memoryUsage ?? 0, colour: style.accent)
                HStack {
                    Text(
                        snapshot.map {
                            "\(ByteFormat.size($0.memoryUsed)) \(strings("common.of")) \(ByteFormat.size($0.memoryTotal))"
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
                Label2(strings("mon.diskIO"))
                if model.sessionState.diskThroughput.isEmpty {
                    Text("—").font(style.font(11.5)).foregroundStyle(style.muted)
                }
                ForEach(model.sessionState.diskThroughput, id: \.name) { flow in
                    HStack {
                        Text(flow.name).foregroundStyle(style.muted)
                        Spacer()
                        Text("↓ \(ByteFormat.size(Int64(flow.down)))\(strings("common.perSec"))")
                        Text("↑ \(ByteFormat.size(Int64(flow.up)))\(strings("common.perSec"))")
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
        guard snapshot.swapTotal > 0 else { return strings("mon.noSwap") }
        return "swap \(ByteFormat.size(snapshot.swapTotal - snapshot.swapFree))"
            + " \(strings("common.of")) \(ByteFormat.size(snapshot.swapTotal))"
    }

    private var disks: [(String, Double, String)] {
        guard let snapshot, !snapshot.filesystems.isEmpty else { return [] }
        return snapshot.filesystems.map {
            ($0.mount, $0.usage, "\(strings("mon.free")) \(ByteFormat.size($0.available))")
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
                        Text("↓ \(ByteFormat.size(Int64(flow.down)))\(strings("common.perSec"))")
                        Text("↑ \(ByteFormat.size(Int64(flow.up)))\(strings("common.perSec"))")
                    }
                    .font(style.font(11.5))
                    .foregroundStyle(style.text)
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Label2(strings("mon.topProcesses"))
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
                Label2(strings("mon.containers"))
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
