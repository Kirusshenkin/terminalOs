public import Charts
public import MetricsKit
public import PhosphorCore
public import SwiftUI

/// Как метрики вели себя последний час, а не чему они равны сейчас.
///
/// Одно значение не отвечает на вопрос, ради которого на метрики и смотрят:
/// «это всегда так или началось только что». Поэтому здесь линии, а числа —
/// на обзорной странице.
struct MetricCharts: View {
    @Environment(\.style) private var style
    let points: [MetricPoint]
    let strings: Strings

    /// Одна линия: как её звать, каким цветом, что брать из точки и в чём это
    /// мерить — доля от целого или байты в секунду.
    private struct Series {
        var title: String
        var colour: Color
        var isRate: Bool = false
        var value: (MetricPoint) -> Double
    }

    var body: some View {
        if points.count < 2 {
            // Одна точка — это ещё не график: честно говорим, чего ждём.
            Text(strings("mon.waitingHistory"))
                .font(style.font(12)).foregroundStyle(style.muted)
                .fixedSize(horizontal: false, vertical: true)
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    chart(
                        strings("mon.cpuLoad"), fraction: true,
                        series: [
                            Series(title: strings("mon.cpuLoad"), colour: style.bright) { $0.cpu }
                        ])
                    chart(
                        strings("mon.memorySwap"), fraction: true,
                        series: [
                            Series(title: strings("mon.memory"), colour: style.bright) { $0.memory },
                            Series(title: "swap", colour: style.warning) { $0.swap },
                        ])
                    chart(
                        strings("mon.network"), fraction: false,
                        series: [
                            Series(title: strings("mon.in"), colour: style.bright, isRate: true) {
                                $0.networkIn
                            },
                            Series(title: strings("mon.out"), colour: style.accent, isRate: true) {
                                $0.networkOut
                            },
                        ])
                    chart(
                        strings("mon.disk"), fraction: false,
                        series: [
                            Series(title: strings("mon.read"), colour: style.bright, isRate: true) {
                                $0.diskRead
                            },
                            Series(title: strings("mon.write"), colour: style.accent, isRate: true) {
                                $0.diskWrite
                            },
                        ])
                }
                .padding(.trailing, 8)
            }
        }
    }

    /// Один график. Доли всегда рисуются от нуля до единицы: иначе шум в два
    /// процента выглядит как полка, и график врёт.
    private func chart(_ title: String, fraction: Bool, series: [Series]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 12) {
                Label2(title)
                ForEach(series, id: \.title) { line in
                    HStack(spacing: 4) {
                        Rectangle().fill(line.colour).frame(width: 8, height: 2)
                        Text(line.title).font(style.font(10)).foregroundStyle(style.muted)
                    }
                }
                Spacer(minLength: 0)
                Text(current(series)).font(style.font(11)).foregroundStyle(style.text)
            }
            Chart {
                ForEach(series, id: \.title) { line in
                    ForEach(points, id: \.time) { point in
                        LineMark(
                            x: .value("t", point.time),
                            y: .value("v", line.value(point))
                        )
                        .foregroundStyle(line.colour)
                        .interpolationMethod(.monotone)
                    }
                }
            }
            .chartLegend(.hidden)
            .chartYScale(domain: fraction ? 0...1 : 0...max(1, ceiling(series)))
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                    AxisGridLine().foregroundStyle(style.rule)
                    AxisValueLabel().foregroundStyle(style.muted)
                }
            }
            .chartYAxis {
                AxisMarks(values: .automatic(desiredCount: 3)) { mark in
                    AxisGridLine().foregroundStyle(style.rule)
                    AxisValueLabel {
                        if let value = mark.as(Double.self) {
                            Text(fraction ? ByteFormat.percent(value) : rate(value))
                                .foregroundStyle(style.muted)
                        }
                    }
                }
            }
            .frame(height: 110)
        }
    }

    /// Верх шкалы для скоростей: по самому большому значению в окне, чтобы
    /// график не жался к нулю на тихом сервере и не срезался на шумном.
    private func ceiling(_ series: [Series]) -> Double {
        let peak = series.flatMap { line in points.map(line.value) }.max() ?? 0
        return peak * 1.15
    }

    /// Последнее значение каждой линии — то, что иначе пришлось бы искать
    /// глазами на правом краю.
    private func current(_ series: [Series]) -> String {
        guard let last = points.last else { return "" }
        return series
            .map { line in
                line.isRate ? rate(line.value(last)) : ByteFormat.percent(line.value(last))
            }
            .joined(separator: " · ")
    }

    private func rate(_ bytesPerSecond: Double) -> String {
        "\(ByteFormat.size(Int64(bytesPerSecond)))\(strings("common.perSec"))"
    }
}
