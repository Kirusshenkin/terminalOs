public import MetricsKit
public import PhosphorCore
public import SessionKit
public import SwiftUI

/// Cores, memory, disks and network for the selected host.
public struct MonitorView: View {
    @Environment(\.style) private var style
    let model: AppModel

    public init(model: AppModel) { self.model = model }
    private var strings: Strings { model.strings }

    public var body: some View {
        HStack(alignment: .top, spacing: 22) {
            cores
            Rectangle().fill(style.rule).frame(width: 1)
            right
        }
    }

    /// Живые ядра, если хост подключён; иначе показательные — чтобы окно не
    /// было пустым до первого подключения.
    private var coreValues: [Double] {
        let live = model.sessionState.coreUsage
        return live.isEmpty ? Self.demoCores : live
    }

    private var stealValues: [Double] {
        model.sessionState.coreSteal
    }

    private var isLive: Bool { !model.sessionState.coreUsage.isEmpty }

    private var cores: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Label2("\(strings("monitor.cores")) · \(coreValues.count)")
                if !isLive {
                    Text("нет соединения — показаны примерные значения")
                        .font(style.font(10.5)).foregroundStyle(style.muted)
                }
            }
            ForEach(Array(coreValues.enumerated()), id: \.offset) { index, value in
                HStack(spacing: 10) {
                    Text("cpu\(index)")
                        .font(style.font(12)).foregroundStyle(style.muted).frame(
                            width: 40, alignment: .leading)
                    Sparkline(values: Self.history(seed: index, latest: value))
                        .stroke(value > 0.7 ? style.warning : style.accent, lineWidth: 1.4)
                        .frame(height: 16)
                    Text(ByteFormat.percent(value))
                        .font(style.font(12)).foregroundStyle(value > 0.7 ? style.warning : style.text)
                        .frame(width: 44, alignment: .trailing)
                    // Steal is a neighbour on the hypervisor eating your time;
                    // nothing you change on the server will help, so it is shown
                    // separately rather than folded into usage.
                    if index < stealValues.count, stealValues[index] > 0.01 {
                        Text("steal \(ByteFormat.percent(stealValues[index]))")
                            .font(style.font(10.5)).foregroundStyle(style.warning.opacity(0.8))
                    }
                }
            }
            Rule().padding(.vertical, 4)
            HStack(spacing: 22) {
                if let snapshot = model.sessionState.latest {
                    metric(
                        "load",
                        String(
                            format: "%.2f %.2f %.2f",
                            snapshot.loadOne, snapshot.loadFive, snapshot.loadFifteen))
                    metric(strings("monitor.uptime"), ByteFormat.duration(seconds: snapshot.uptime))
                } else {
                    metric("load", "—")
                    metric(strings("monitor.uptime"), "—")
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var right: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Label2("\(strings("monitor.memory")) · MemAvailable")
                let snapshot = model.sessionState.latest
                Bar(fraction: snapshot?.memoryUsage ?? 0.36, colour: style.accent)
                Text(
                    snapshot.map {
                        "\(ByteFormat.size($0.memoryUsed)) из \(ByteFormat.size($0.memoryTotal))"
                    } ?? "—"
                )
                .font(style.font(12)).foregroundStyle(style.bright)
            }
            VStack(alignment: .leading, spacing: 8) {
                Label2(strings("monitor.disks"))
                ForEach(disks, id: \.0) { disk in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(disk.0).font(style.font(12)).foregroundStyle(style.text)
                            Spacer()
                            Text(ByteFormat.percent(disk.1))
                                .font(style.font(12))
                                .foregroundStyle(disk.1 > 0.8 ? style.warning : style.text)
                        }
                        Bar(fraction: disk.1, colour: disk.1 > 0.8 ? style.warning : style.accent)
                    }
                }
            }
            VStack(alignment: .leading, spacing: 6) {
                Label2(strings("monitor.network"))
                if let flow = model.sessionState.throughput.first {
                    Text("↓ \(ByteFormat.size(Int64(flow.down)))/с   ↑ \(ByteFormat.size(Int64(flow.up)))/с")
                        .font(style.font(12)).foregroundStyle(style.bright)
                } else {
                    Text("—").font(style.font(12)).foregroundStyle(style.muted)
                }
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func metric(_ title: String, _ value: String) -> some View {
        HStack(spacing: 6) {
            Text(title).font(style.font(12)).foregroundStyle(style.muted)
            Text(value).font(style.font(12)).foregroundStyle(style.bright)
        }
    }

    private static let demoCores: [Double] = [0.62, 0.18, 0.44, 0.09, 0.77, 0.23, 0.31, 0.12]
    /// Диски с сервера, если он на связи; иначе показательные.
    private var disks: [(String, Double)] {
        guard let snapshot = model.sessionState.latest, !snapshot.filesystems.isEmpty else {
            return Self.demoDisks
        }
        return snapshot.filesystems.map { ($0.mount, $0.usage) }
    }

    private static let demoDisks: [(String, Double)] = [
        ("/", 0.85), ("/var/lib/docker", 0.30), ("/backups", 0.55),
    ]

    /// Deterministic sample history so the sparkline is stable between redraws.
    private static func history(seed: Int, latest: Double) -> [Double] {
        (0..<28).map { step in
            let wave = sin(Double(step) * 0.5 + Double(seed)) * 0.12
            return min(0.98, max(0.02, latest + wave))
        }
    }
}

/// A polyline over normalised values.
struct Sparkline: Shape {
    var values: [Double]

    func path(in rect: CGRect) -> Path {
        var path = Path()
        guard values.count > 1 else { return path }
        let step = rect.width / CGFloat(values.count - 1)
        for (index, value) in values.enumerated() {
            let point = CGPoint(x: CGFloat(index) * step, y: rect.height * (1 - CGFloat(value)))
            if index == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        return path
    }
}

/// A thin usage bar.
struct Bar: View {
    @Environment(\.style) private var style
    var fraction: Double
    var colour: Color

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Rectangle().fill(style.text.opacity(0.12))
                Rectangle().fill(colour).frame(width: geometry.size.width * min(max(fraction, 0), 1))
            }
        }
        .frame(height: 5)
    }
}
