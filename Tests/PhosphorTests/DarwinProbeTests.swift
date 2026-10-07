import Foundation
import Testing

@testable import MetricsKit

@Suite("Метрики с Мака")
struct DarwinProbeTests {
    /// Блок, который печатает `DarwinProbe.loop` на macOS.
    private func block(time: Int, user: Int, system: Int, idle: Int) -> String {
        """
        T \(time)
        L 8.88 7.76 10.57 7/999
        U 116521
        M MemTotal: 67108864
        M MemAvailable: 30706032
        M SwapTotal: 2097152
        M SwapFree: 1048576
        D / 994662584320 16595525632 76956622848
        D /System/Volumes/Data 994662584320 880882966528 76956622848
        N en0 12923154270 6157621541
        B disk0 566179936 607526824
        F 10821
        S 389 39.0 0.5 WindowServer
        S 491 22.6 0.1 syspolicyd
        C cpu0 \(user) 0 \(system) \(idle) 0 0 0 0
        """
    }

    @Test("блок с Мака разбирается тем же парсером, что и /proc")
    func parses() throws {
        let snapshot = try #require(SnapshotParser.parse(block(time: 100, user: 25, system: 7, idle: 68)))
        #expect(snapshot.memoryTotal == 67_108_864 * 1024)
        #expect(snapshot.memoryAvailable == 30_706_032 * 1024)
        #expect(snapshot.swapTotal == 2_097_152 * 1024)
        #expect(snapshot.filesystems.map(\.mount) == ["/", "/System/Volumes/Data"])
        #expect(snapshot.interfaces.map(\.name) == ["en0"])
        #expect(snapshot.cores.count == 1, "на macOS загрузка только общая")
        #expect(snapshot.processes.first?.command == "WindowServer")
        #expect(snapshot.runningProcesses == 7 && snapshot.totalProcesses == 999)
    }

    @Test("общая загрузка считается по дельте накопленных процентов")
    func usageIsDelta() throws {
        let first = try #require(SnapshotParser.parse(block(time: 100, user: 25, system: 7, idle: 68)))
        let second = try #require(SnapshotParser.parse(block(time: 102, user: 75, system: 17, idle: 108)))
        // За интервал: 50 user + 10 system + 40 idle → занято 60%.
        let usage = SnapshotParser.usage(from: first, to: second)
        #expect(usage.count == 1)
        #expect(abs(usage[0] - 0.6) < 0.0001)
    }

    @Test("на Маке не трогаем /proc, а интервал выдерживает iostat")
    func commands() {
        let loop = DarwinProbe.loop(interval: 3)
        #expect(!loop.contains("/proc"))
        #expect(loop.contains("iostat -n 0 -w 3 -c 2"))
        #expect(!loop.contains("sleep"), "iostat и меряет, и ждёт")
        #expect(DarwinProbe.once.contains("machdep.cpu.brand_string"))
    }

    @Test("пара команд выбирается по системе")
    func choosesProbe() {
        #expect(MetricsProbe(darwin: true).loop == DarwinProbe.loop())
        #expect(MetricsProbe(darwin: false).loop == ProcProbe.loop())
        #expect(MetricsProbe(darwin: false).once == ProcProbe.once)
    }
}
