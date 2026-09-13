import Foundation
import Testing

@testable import MetricsKit

/// Ряд из `count` точек с шагом в две секунды, как его отдаёт живая сессия.
private func series(
    count: Int, from start: Date = Date(timeIntervalSince1970: 1_700_000_000)
)
    -> [MetricPoint]
{
    (0..<count).map { index -> MetricPoint in
        let step = Double(index)
        return MetricPoint(
            time: start.addingTimeInterval(step * 2),
            cpu: Double(index % 100) / 100,
            memory: 0.42,
            swap: 0,
            networkIn: step * 1_024,
            networkOut: step * 512,
            diskRead: 0,
            diskWrite: step
        )
    }
}

@Suite("Архив метрик")
struct MetricArchiveTests {
    @Test("ряд переживает запись и чтение без потерь")
    func roundTrip() throws {
        let points = series(count: 50)
        let decoded = try MetricArchive.decode(MetricArchive.encode(points))
        #expect(decoded.count == points.count)
        for (left, right) in zip(points, decoded) {
            // Время сравниваем по секундам, а не по объектам: в файле лежит
            // `Double` от эпохи, и `Date` собирается из него заново.
            #expect(abs(left.time.timeIntervalSince1970 - right.time.timeIntervalSince1970) < 1e-6)
            #expect(left.cpu == right.cpu)
            #expect(left.memory == right.memory)
            #expect(left.networkIn == right.networkIn)
            #expect(left.diskWrite == right.diskWrite)
        }
    }

    @Test("пустой ряд читается как пустой, а не как ошибка")
    func emptyIsValid() throws {
        #expect(try MetricArchive.decode(MetricArchive.encode([])).isEmpty)
    }

    @Test("ряд длиннее потолка обрезается при записи")
    func boundedOnWrite() throws {
        let points = series(count: MetricArchive.maximumPoints + 200)
        let decoded = try MetricArchive.decode(MetricArchive.encode(points))
        #expect(decoded.count == MetricArchive.maximumPoints)
        // Остаются последние: график показывает недавнее, а не самое старое.
        #expect(decoded.last?.diskWrite == points.last?.diskWrite)
    }

    @Test("оборванная на середине запись не читается как половина ряда")
    func tornWriteIsRefused() {
        let data = MetricArchive.encode(series(count: 30))
        // Обрыв в любом месте тела: заголовок обещает тридцать точек, а их нет.
        for cut in [1, 20, data.count / 2, data.count - 1] {
            #expect(throws: MetricArchive.ArchiveError.self) {
                _ = try MetricArchive.decode(data.prefix(cut))
            }
        }
    }

    @Test("испорченный байт виден по контрольной сумме")
    func flippedByteIsCaught() {
        var data = MetricArchive.encode(series(count: 10))
        let victim = data.count - 5
        data[victim] ^= 0xFF
        #expect(throws: MetricArchive.ArchiveError.damaged) {
            _ = try MetricArchive.decode(data)
        }
    }

    @Test("чужой файл не выдаётся за архив")
    func foreignFileRefused() {
        let data = Data("это не архив метрик, а просто текст".utf8)
        #expect(throws: MetricArchive.ArchiveError.notAnArchive) {
            _ = try MetricArchive.decode(data)
        }
    }

    @Test("архив из будущей версии называет версию, а не рассыпается")
    func futureVersionNamed() {
        var data = MetricArchive.encode(series(count: 3))
        data[4] = 0
        data[5] = UInt8(MetricArchive.currentVersion + 9)
        #expect(
            throws: MetricArchive.ArchiveError.unsupportedVersion(
                MetricArchive.currentVersion + 9)
        ) {
            _ = try MetricArchive.decode(data)
        }
    }

    @Test("заголовок с невероятным числом точек отвергается до чтения тела")
    func absurdCountRefused() {
        var data = MetricArchive.encode(series(count: 3))
        // Заголовок обещает миллиард точек: поверить ему — значит попытаться
        // выделить под них память.
        data[6] = 0x3B
        data[7] = 0x9A
        data[8] = 0xCA
        data[9] = 0x00
        #expect(throws: MetricArchive.ArchiveError.self) {
            _ = try MetricArchive.decode(data)
        }
    }
}

@Suite("История метрик на диске")
struct MetricStoreTests {
    private func temporaryDirectory() -> URL {
        URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("phosphor-metrics-\(UUID().uuidString)")
    }

    @Test("ряд переживает пересоздание хранилища")
    func survivesRestart() async {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let host = UUID()
        let points = series(count: 40, from: Date().addingTimeInterval(-80))

        await MetricStore(directory: directory).save(points, host: host)
        let restored = await MetricStore(directory: directory).load(host: host)
        #expect(restored.count == points.count)
    }

    @Test("нет файла — нет истории, и это не ошибка")
    func missingIsEmpty() async {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        #expect(await MetricStore(directory: directory).load(host: UUID()).isEmpty)
    }

    @Test("испорченный архив не всплывает во второй раз")
    func damagedArchiveIsDropped() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let host = UUID()
        let store = MetricStore(directory: directory)
        await store.save(series(count: 10, from: Date().addingTimeInterval(-20)), host: host)

        let file = directory.appendingPathComponent("\(host.uuidString).pmet")
        var data = try Data(contentsOf: file)
        data[data.count - 3] ^= 0xFF
        try data.write(to: file)

        #expect(await store.load(host: host).isEmpty)
        #expect(!FileManager.default.fileExists(atPath: file.path))
    }

    @Test("одна точка не создаёт файла: это ещё не ряд")
    func singlePointIsNotSaved() async {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let host = UUID()
        await MetricStore(directory: directory).save(series(count: 1), host: host)
        #expect(
            !FileManager.default.fileExists(
                atPath: directory.appendingPathComponent("\(host.uuidString).pmet").path))
    }

    @Test("точки старше суток не возвращаются")
    func staleHistoryIsIgnored() async {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let host = UUID()
        let store = MetricStore(directory: directory)
        let ancient = Date().addingTimeInterval(-MetricStore.maximumAge - 3_600)
        await store.save(series(count: 10, from: ancient), host: host)
        #expect(await store.load(host: host).isEmpty)
    }

    @Test("папка не растёт бесконечно: остаются последние архивы")
    func directoryIsBounded() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = MetricStore(directory: directory)
        for _ in 0..<(MetricStore.maximumArchives + 5) {
            await store.save(series(count: 3, from: Date().addingTimeInterval(-10)), host: UUID())
        }
        let left = try FileManager.default.contentsOfDirectory(atPath: directory.path)
            .filter { $0.hasSuffix(".pmet") }
        #expect(left.count <= MetricStore.maximumArchives)
    }

    @Test("забытый хост не оставляет файла")
    func forgetRemovesFile() async {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let host = UUID()
        let store = MetricStore(directory: directory)
        await store.save(series(count: 5, from: Date().addingTimeInterval(-10)), host: host)
        await store.forget(host: host)
        #expect(await store.load(host: host).isEmpty)
    }
}
