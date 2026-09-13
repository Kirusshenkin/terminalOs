public import Foundation

/// Ряд точек в том виде, в каком он ложится на диск.
///
/// Формат свой и нарочно скучный: заголовок в открытую, дальше записи
/// одинаковой длины. JSON здесь стоил бы вчетверо дороже по месту и ничего бы
/// не дал — у точки восемь чисел и ни одного имени, которое стоило бы хранить
/// рядом с каждой из них.
///
/// Раскладка: `PMET`, версия `UInt16`, число точек `UInt32`, контрольная сумма
/// `UInt32`, затем точки по 64 байта. Заголовок читается без разбора тела:
/// файл от будущей версии должен уметь сказать об этом, а не рассыпаться.
public enum MetricArchive {
    public enum ArchiveError: Error, Equatable {
        /// Магии нет: это не наш файл.
        case notAnArchive
        /// Версия новее, чем понимает эта сборка.
        case unsupportedVersion(UInt16)
        /// Тело короче, чем обещает заголовок, — запись оборвали на середине.
        case truncated
        /// Длина сходится, а контрольная сумма — нет: байты поменялись.
        case damaged
        /// Заголовок обещает больше точек, чем мы вообще держим.
        case tooLarge(Int)
    }

    public static let magic: [UInt8] = Array("PMET".utf8)
    public static let currentVersion: UInt16 = 1

    /// Верхняя граница ряда. Буфер без потолка — это утечка с отложенным
    /// сроком, и файл на диске в этом смысле ничем не лучше памяти.
    public static let maximumPoints = 4_096

    static let headerSize = 14
    /// Восемь `Double`: время и семь величин.
    static let recordSize = 64

    /// Сворачивает ряд в байты, оставляя последние `maximumPoints` точек.
    public static func encode(_ points: [MetricPoint]) -> Data {
        let kept = points.suffix(maximumPoints)
        var body = Data(capacity: kept.count * recordSize)
        for point in kept {
            append(point.time.timeIntervalSince1970, to: &body)
            append(point.cpu, to: &body)
            append(point.memory, to: &body)
            append(point.swap, to: &body)
            append(point.networkIn, to: &body)
            append(point.networkOut, to: &body)
            append(point.diskRead, to: &body)
            append(point.diskWrite, to: &body)
        }

        var out = Data(magic)
        append(currentVersion, to: &out)
        append(UInt32(kept.count), to: &out)
        append(crc32(body), to: &out)
        out.append(body)
        return out
    }

    /// Разбирает байты обратно в ряд, проверяя всё, что можно проверить.
    ///
    /// Проверок три, и каждая ловит свою беду: длина — обрыв записи, сумма —
    /// порчу байтов, версия — файл из будущего. Молча вернуть половину ряда
    /// было бы хуже, чем не вернуть ничего: график соврал бы, а никто не узнал.
    public static func decode(_ data: Data) throws -> [MetricPoint] {
        guard data.count >= headerSize else { throw ArchiveError.truncated }
        let bytes = [UInt8](data)
        guard Array(bytes[0..<4]) == magic else { throw ArchiveError.notAnArchive }

        let version = UInt16(bytes[4]) << 8 | UInt16(bytes[5])
        guard version <= currentVersion else { throw ArchiveError.unsupportedVersion(version) }

        let count = Int(readUInt32(bytes, at: 6))
        guard count <= maximumPoints else { throw ArchiveError.tooLarge(count) }
        let expected = readUInt32(bytes, at: 10)

        let body = data.dropFirst(headerSize)
        guard body.count == count * recordSize else { throw ArchiveError.truncated }
        guard crc32(body) == expected else { throw ArchiveError.damaged }

        var points: [MetricPoint] = []
        points.reserveCapacity(count)
        let raw = [UInt8](body)
        for index in 0..<count {
            let base = index * recordSize
            points.append(
                MetricPoint(
                    time: Date(timeIntervalSince1970: readDouble(raw, at: base)),
                    cpu: readDouble(raw, at: base + 8),
                    memory: readDouble(raw, at: base + 16),
                    swap: readDouble(raw, at: base + 24),
                    networkIn: readDouble(raw, at: base + 32),
                    networkOut: readDouble(raw, at: base + 40),
                    diskRead: readDouble(raw, at: base + 48),
                    diskWrite: readDouble(raw, at: base + 56)
                ))
        }
        return points
    }

    // MARK: - Байты

    private static func append(_ value: Double, to data: inout Data) {
        append(value.bitPattern, to: &data)
    }

    private static func append(_ value: UInt64, to data: inout Data) {
        for shift in stride(from: 56, through: 0, by: -8) {
            data.append(UInt8(truncatingIfNeeded: value >> UInt64(shift)))
        }
    }

    private static func append(_ value: UInt32, to data: inout Data) {
        for shift in stride(from: 24, through: 0, by: -8) {
            data.append(UInt8(truncatingIfNeeded: value >> UInt32(shift)))
        }
    }

    private static func append(_ value: UInt16, to data: inout Data) {
        data.append(UInt8(truncatingIfNeeded: value >> 8))
        data.append(UInt8(truncatingIfNeeded: value))
    }

    private static func readUInt32(_ bytes: [UInt8], at offset: Int) -> UInt32 {
        var value: UInt32 = 0
        for index in 0..<4 { value = value << 8 | UInt32(bytes[offset + index]) }
        return value
    }

    private static func readDouble(_ bytes: [UInt8], at offset: Int) -> Double {
        var pattern: UInt64 = 0
        for index in 0..<8 { pattern = pattern << 8 | UInt64(bytes[offset + index]) }
        return Double(bitPattern: pattern)
    }

    /// CRC-32 (IEEE) без таблицы: файл маленький, а таблица на 1 КБ ради него —
    /// это память, которая живёт всё время работы приложения ни за чем.
    static func crc32<Bytes: Sequence>(_ bytes: Bytes) -> UInt32 where Bytes.Element == UInt8 {
        var crc: UInt32 = 0xFFFF_FFFF
        for byte in bytes {
            crc ^= UInt32(byte)
            for _ in 0..<8 {
                crc = (crc >> 1) ^ (0xEDB8_8320 & ~((crc & 1) &- 1))
            }
        }
        return crc ^ 0xFFFF_FFFF
    }
}
