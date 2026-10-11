import Foundation
import Testing
@testable import DockerKit
@testable import HostsKit
@testable import KeysKit
@testable import MetricsKit
@testable import PhosphorCore
@testable import ProvisionKit
@testable import SessionKit
@testable import ThemeKit

@Suite("Расширенные метрики")
struct ExtendedMetricsTests {
    private let first = """
        T 1756800000
        L 0.42 0.51 0.48 3/184 9111
        U 3542400.12 28000000.00
        C cpu0 50 0 25 400 5 0 0 0
        M MemTotal: 32000000
        M MemAvailable: 20000000
        M SwapTotal: 2000000
        M SwapFree: 1500000
        B nvme0n1 200000 400000
        F 4096
        S 912 45.5 12.3 node
        S 41 2.0 0.5 postgres
        K 6.8.0-45-generic
        P AMD EPYC 7763 64-Core Processor
        """

    private let second = """
        T 1756800002
        L 0.44 0.51 0.48 5/186 9111
        U 3542402.12 28000004.00
        C cpu0 100 0 50 450 10 0 0 0
        M MemTotal: 32000000
        M MemAvailable: 19000000
        M SwapTotal: 2000000
        M SwapFree: 1500000
        B nvme0n1 204000 408000
        F 4200
        """

    @Test("процессы, дескрипторы, ядро и модель процессора разбираются")
    func parsesExtras() throws {
        let snapshot = try #require(SnapshotParser.parse(first))
        #expect(snapshot.runningProcesses == 3)
        #expect(snapshot.totalProcesses == 184)
        #expect(snapshot.openFiles == 4096)
        #expect(snapshot.kernel == "6.8.0-45-generic")
        #expect(snapshot.cpuModel.contains("EPYC"))
    }

    @Test("самые тяжёлые процессы приходят в долях, а не в процентах")
    func parsesProcesses() throws {
        let snapshot = try #require(SnapshotParser.parse(first))
        #expect(snapshot.processes.count == 2)
        #expect(snapshot.processes[0].pid == 912)
        #expect(snapshot.processes[0].command == "node")
        #expect(abs(snapshot.processes[0].cpu - 0.455) < 0.001)
    }

    @Test("swap считается использованным, а не свободным")
    func swapAccounting() throws {
        let snapshot = try #require(SnapshotParser.parse(first))
        #expect(snapshot.swapTotal == 2_000_000 * 1024)
        #expect(snapshot.swapFree == 1_500_000 * 1024)
    }

    @Test("скорость диска переводится из секторов в байты")
    func diskThroughput() throws {
        let a = try #require(SnapshotParser.parse(first))
        let b = try #require(SnapshotParser.parse(second))
        let flow = try #require(SnapshotParser.diskThroughput(from: a, to: b).first)
        #expect(flow.name == "nvme0n1")
        // (204000-200000) секторов × 512 байт ÷ 2 с
        #expect(flow.down == 4_000.0 * 512 / 2)
        #expect(flow.up == 8_000.0 * 512 / 2)
    }

    @Test("счётчики диска после перезагрузки не дают отрицательной скорости")
    func diskCountersResetSafely() throws {
        let a = try #require(SnapshotParser.parse(second))
        let b = try #require(SnapshotParser.parse(first))
        #expect(
            SnapshotParser.diskThroughput(from: a, to: b).allSatisfy {
                $0.down >= 0 && $0.up >= 0
            })
    }

    @Test("команда сбора спрашивает всё нужное одним каналом")
    func probeCoversEverything() {
        let loop = ProcProbe.loop()
        for needle in [
            "/proc/loadavg", "/proc/stat", "/proc/meminfo", "df -PB1",
            "/proc/net/dev", "/proc/diskstats", "file-nr", "ps -eo",
        ] {
            #expect(loop.contains(needle), "в цикле нет \(needle)")
        }
        // Неизменное спрашивается отдельно и один раз.
        #expect(ProcProbe.once.contains("uname -r"))
        #expect(ProcProbe.once.contains("cpuinfo"))
        #expect(
            !loop.contains("cpuinfo"), "модель процессора не меняется — не спрашиваем её каждые две секунды")
    }
}

@Suite("Переменные окружения контейнера")
struct DockerEnvironmentTests {
    @Test("значение со знаком равенства не обрезается")
    func keepsValueWithEquals() {
        let json = """
            [{"Config":{"Env":["NODE_ENV=production","DSN=postgres://u:p@h/db?x=1","EMPTY="]}}]
            """
        let parsed = DockerCLI.parseEnvironment(json)
        #expect(parsed.count == 3)
        #expect(parsed[0] == ("NODE_ENV", "production"))
        #expect(parsed[1].value == "postgres://u:p@h/db?x=1")
        #expect(parsed[2].value == "")
    }

    @Test("строка без имени и мусор вместо json дают пустой список")
    func survivesJunk() {
        #expect(DockerCLI.parseEnvironment("не json").isEmpty)
        #expect(DockerCLI.parseEnvironment("[]").isEmpty)
        #expect(
            DockerCLI.parseEnvironment(
                """
                [{"Config":{"Env":["=нет имени","без знака равенства"]}}]
                """
            ).isEmpty)
    }
}
