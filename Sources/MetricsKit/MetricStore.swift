public import Foundation
import OSLog
import VaultKit

/// Ряды метрик, пережившие закрытие приложения.
///
/// Смысл не в архиве как таковом, а в том, что переподключение к серверу
/// перестаёт стирать картину: вернувшись через час, видишь, что было этот час,
/// а не пустой график, который снова придётся набирать с нуля.
///
/// Хранится по файлу на хост, рядом с профилем. Секретов в этих числах нет —
/// загрузка ядер и занятая память, — поэтому шифровать нечего; права всё равно
/// 0600, потому что список идентификаторов хостов тоже никого не касается.
public actor MetricStore {
    /// Тот, которым пользуется приложение.
    public static let shared = MetricStore()

    /// Сколько точек держим — и в памяти, и на диске.
    ///
    /// Снимки приходят раз в две секунды, то есть это последние двадцать четыре
    /// минуты. Дальше график всё равно не читается глазами, а файл растёт: 720
    /// точек — это 46 КБ на хост, и это потолок, а не «пока что».
    public static let capacity = 720

    /// Меньше двух точек — это не ряд, а одно число: рисовать нечего, писать
    /// файл незачем. Заодно прогон тестов не оставляет следов на диске.
    static let minimumToKeep = 2

    /// Сколько архивов держим в папке. Хост, к которому не подключались
    /// месяцами, не должен занимать место вечно.
    static let maximumArchives = 64

    /// Сколько времени точка остаётся интересной.
    ///
    /// Ось графика — настоящее время, поэтому вчерашний хвост рядом с
    /// сегодняшним просто сдвинет масштаб. Сутки — это ещё «что было, пока меня
    /// не было»; неделя — уже сплющенная в точку полоса и враньё о масштабе.
    static let maximumAge: TimeInterval = 86_400

    private let directory: URL
    private let log = Logger(subsystem: "dev.phosphor.terminal", category: "metrics")

    public init(directory: URL = MetricStore.defaultDirectory()) {
        self.directory = directory
    }

    public static func defaultDirectory() -> URL {
        let base =
            FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first ?? URL(fileURLWithPath: NSHomeDirectory())
        return base.appendingPathComponent("Phosphor/metrics")
    }

    /// Ряд, сохранённый для этого хоста. Нет файла — нет истории, и это
    /// нормальное состояние, а не ошибка.
    public func load(host: UUID, now: Date = Date()) -> [MetricPoint] {
        let url = url(for: host)
        guard let data = try? Data(contentsOf: url) else { return [] }
        do {
            let oldest = now.addingTimeInterval(-Self.maximumAge)
            return try MetricArchive.decode(data).filter { $0.time > oldest }
        } catch {
            // Испорченный архив не стоит ни падения, ни диалога: график
            // начнётся заново. Но и молчать нельзя — файл надо убрать, иначе он
            // будет всплывать при каждом подключении.
            let reason = String(describing: error)
            log.warning(
                "архив метрик \(url.lastPathComponent, privacy: .public) непригоден: \(reason, privacy: .public)"
            )
            try? FileManager.default.removeItem(at: url)
            return []
        }
    }

    /// Сохраняет ряд, обрезав его сверху.
    ///
    /// Запись атомарная: обрыв на середине оставляет прежний файл целым, а не
    /// половину нового. Половина архива хуже, чем его отсутствие, — она
    /// выглядит как данные.
    public func save(_ points: [MetricPoint], host: UUID) {
        guard points.count >= Self.minimumToKeep else { return }
        let kept = Array(points.suffix(Self.capacity))
        do {
            try AtomicFile.write(MetricArchive.encode(kept), to: url(for: host))
            prune()
        } catch {
            log.warning(
                "не удалось записать историю метрик: \(String(describing: error), privacy: .public)")
        }
    }

    /// Убирает историю одного хоста — например, когда хост удалили из списка.
    public func forget(host: UUID) {
        // `try?`: файла может не быть, и это ровно то, чего мы добиваемся.
        try? FileManager.default.removeItem(at: url(for: host))
    }

    private func url(for host: UUID) -> URL {
        directory.appendingPathComponent("\(host.uuidString).pmet")
    }

    /// Держит папку в берегах: остаются самые свежие архивы.
    private func prune() {
        let manager = FileManager.default
        guard
            let names = try? manager.contentsOfDirectory(
                at: directory, includingPropertiesForKeys: [.contentModificationDateKey])
        else { return }
        let archives = names.filter { $0.pathExtension == "pmet" }
        guard archives.count > Self.maximumArchives else { return }
        let dated = archives.map { url -> (url: URL, date: Date) in
            let modified =
                (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?
                .contentModificationDate
            return (url, modified ?? .distantPast)
        }
        for entry in dated.sorted(by: { $0.date > $1.date }).dropFirst(Self.maximumArchives) {
            try? manager.removeItem(at: entry.url)
        }
    }
}
