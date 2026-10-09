import Foundation

/// A read-only LevelDB reader — just enough to recover the current key/value
/// pairs from a directory.
///
/// Termius держит свой IndexedDB в LevelDB: пачка `.ldb` (отсортированные
/// таблицы SSTable) и `.log` (журнал ещё не слитых записей). Чтобы прочитать
/// хост целиком, одной выборки печатных строк мало — нужна настоящая структура
/// ключ-значение и, главное, **последняя** версия каждого ключа: LevelDB не
/// переписывает записи на месте, а кладёт новую версию поверх, и наивное чтение
/// вернуло бы устаревший адрес или удалённый хост.
///
/// Контрольные суммы блоков и записей здесь не проверяются намеренно: это
/// чтение, и единственное, что делает битый блок, — не открывается секретбокс,
/// после чего запись просто пропускается. Проверять CRC означало бы тащить
/// ещё и crc32c ради ошибки, которую мы и так обрабатываем пропуском.
///
/// Only reading: Phosphor never writes LevelDB.
enum LevelDB {
    /// Latest live value for every user key across every table and log in the
    /// directory. Deleted keys are dropped.
    static func read(directory: String) -> [Data: Data] {
        let manager = FileManager.default
        guard let names = try? manager.contentsOfDirectory(atPath: directory) else { return [:] }

        // Последняя версия ключа — та, у которой больше порядковый номер
        // (sequence). Он монотонно растёт, так что сравнение номеров и есть
        // «кто новее», независимо от того, в таблице запись или в журнале.
        var latest: [Data: (sequence: UInt64, value: Data?, deleted: Bool)] = [:]
        func record(key: Data, sequence: UInt64, value: Data?, deleted: Bool) {
            if let existing = latest[key], existing.sequence >= sequence { return }
            latest[key] = (sequence, value, deleted)
        }

        for name in names.sorted() {
            guard
                let data = try? Data(
                    contentsOf: URL(fileURLWithPath: directory + "/" + name))
            else { continue }
            let bytes = [UInt8](data)
            if name.hasSuffix(".ldb") || name.hasSuffix(".sst") {
                readTable(bytes, into: record)
            } else if name.hasSuffix(".log") {
                readLog(bytes, into: record)
            }
        }

        var result: [Data: Data] = [:]
        for (key, entry) in latest where !entry.deleted {
            if let value = entry.value { result[key] = value }
        }
        return result
    }

    // MARK: - SSTable (.ldb)

    private static let tableMagic: UInt64 = 0xdb47_7524_8b80_fb57
    private static let footerSize = 48

    private static func readTable(
        _ bytes: [UInt8],
        into record: (_ key: Data, _ sequence: UInt64, _ value: Data?, _ deleted: Bool) -> Void
    ) {
        guard bytes.count >= footerSize else { return }
        let footer = bytes.count - footerSize
        let magic =
            UInt64(bytes[bytes.count - 8]) | UInt64(bytes[bytes.count - 7]) << 8
            | UInt64(bytes[bytes.count - 6]) << 16 | UInt64(bytes[bytes.count - 5]) << 24
            | UInt64(bytes[bytes.count - 4]) << 32 | UInt64(bytes[bytes.count - 3]) << 40
            | UInt64(bytes[bytes.count - 2]) << 48 | UInt64(bytes[bytes.count - 1]) << 56
        guard magic == tableMagic else { return }

        // Футер: handle метаиндекса, затем handle индекса. Метаиндекс ведёт к
        // фильтрам и статистике — для чтения данных он не нужен, его пропускаем.
        var cursor = footer
        guard varint(bytes, &cursor) != nil, varint(bytes, &cursor) != nil else { return }
        guard let indexOffset = varint(bytes, &cursor),
            let indexSize = varint(bytes, &cursor)
        else { return }

        guard let indexBlock = readBlock(bytes, offset: indexOffset, size: indexSize) else { return }
        // В индексном блоке значение каждой записи — handle блока данных.
        forEachEntry(in: indexBlock) { _, handle in
            var handleCursor = 0
            guard let dataOffset = varint(handle, &handleCursor),
                let dataSize = varint(handle, &handleCursor),
                let dataBlock = readBlock(bytes, offset: dataOffset, size: dataSize)
            else { return }
            forEachEntry(in: dataBlock) { internalKey, value in
                guard internalKey.count >= 8 else { return }
                // Последние 8 байт — трейлер: (sequence << 8) | type.
                var trailer: UInt64 = 0
                for shift in 0..<8 {
                    trailer |= UInt64(internalKey[internalKey.count - 8 + shift]) << (8 * shift)
                }
                let userKey = Data(internalKey[0..<(internalKey.count - 8)])
                let type = UInt8(trailer & 0xFF)
                record(userKey, trailer >> 8, Data(value), type == 0)
            }
        }
    }

    /// Reads one block given its handle: the `size` data bytes, decompressed if
    /// the trailing type byte says Snappy.
    private static func readBlock(_ bytes: [UInt8], offset: UInt64, size: UInt64) -> [UInt8]? {
        let start = Int(offset)
        let length = Int(size)
        guard start >= 0, length >= 0, start + length + 1 <= bytes.count else { return nil }
        let raw = Array(bytes[start..<(start + length)])
        let compression = bytes[start + length]
        switch compression {
        case 0: return raw
        case 1: return Snappy.decompress(raw)
        default: return nil
        }
    }

    /// Walks a block's entries, reconstructing each key from the shared prefix
    /// of the previous one. The restart array at the tail is only an index for
    /// seeks, so we stop where it begins and ignore it.
    private static func forEachEntry(in block: [UInt8], _ body: ([UInt8], [UInt8]) -> Void) {
        guard block.count >= 4 else { return }
        let restartCount =
            Int(block[block.count - 4]) | Int(block[block.count - 3]) << 8
            | Int(block[block.count - 2]) << 16 | Int(block[block.count - 1]) << 24
        let entriesEnd = block.count - (restartCount + 1) * 4
        guard entriesEnd >= 0, entriesEnd <= block.count else { return }

        var cursor = 0
        var previousKey: [UInt8] = []
        while cursor < entriesEnd {
            guard let shared = varint(block, &cursor),
                let nonShared = varint(block, &cursor),
                let valueLength = varint(block, &cursor)
            else { return }
            let sharedCount = Int(shared)
            let nonSharedCount = Int(nonShared)
            let valueCount = Int(valueLength)
            guard sharedCount <= previousKey.count,
                cursor + nonSharedCount + valueCount <= entriesEnd
            else { return }
            var key = Array(previousKey[0..<sharedCount])
            key.append(contentsOf: block[cursor..<(cursor + nonSharedCount)])
            cursor += nonSharedCount
            let value = Array(block[cursor..<(cursor + valueCount)])
            cursor += valueCount
            body(key, value)
            previousKey = key
        }
    }

    // MARK: - Journal (.log)

    private static let logBlockSize = 32768
    private static let logHeaderSize = 7

    private static func readLog(
        _ bytes: [UInt8],
        into record: (_ key: Data, _ sequence: UInt64, _ value: Data?, _ deleted: Bool) -> Void
    ) {
        // Журнал нарезан на блоки по 32 КиБ; логическая запись (батч) может
        // быть склеена из фрагментов FIRST/MIDDLE/LAST поверх границ блоков.
        var payload: [UInt8] = []
        var offset = 0
        while offset + logHeaderSize <= bytes.count {
            let blockRemaining = logBlockSize - (offset % logBlockSize)
            if blockRemaining < logHeaderSize {
                // Хвост блока меньше заголовка — это нулевое заполнение.
                offset += blockRemaining
                continue
            }
            let length = Int(bytes[offset + 4]) | Int(bytes[offset + 5]) << 8
            let type = bytes[offset + 6]
            let dataStart = offset + logHeaderSize
            guard dataStart + length <= bytes.count else { break }
            let fragment = Array(bytes[dataStart..<(dataStart + length)])
            offset = dataStart + length

            switch type {
            case 1:  // FULL
                applyBatch(fragment, into: record)
            case 2:  // FIRST
                payload = fragment
            case 3:  // MIDDLE
                payload.append(contentsOf: fragment)
            case 4:  // LAST
                payload.append(contentsOf: fragment)
                applyBatch(payload, into: record)
                payload = []
            default:
                // Нулевой или неизвестный тип — конец осмысленных данных блока.
                return
            }
        }
    }

    /// Applies one write batch: an 8-byte sequence, a 4-byte count, then that
    /// many put/delete entries, each advancing the sequence by one.
    private static func applyBatch(
        _ batch: [UInt8],
        into record: (_ key: Data, _ sequence: UInt64, _ value: Data?, _ deleted: Bool) -> Void
    ) {
        guard batch.count >= 12 else { return }
        var sequence: UInt64 = 0
        for shift in 0..<8 { sequence |= UInt64(batch[shift]) << (8 * shift) }
        let count =
            UInt32(batch[8]) | UInt32(batch[9]) << 8
            | UInt32(batch[10]) << 16 | UInt32(batch[11]) << 24

        var cursor = 12
        for index in 0..<Int(count) {
            guard cursor < batch.count else { return }
            let type = batch[cursor]
            cursor += 1
            switch type {
            case 1:  // put
                guard let key = lengthPrefixed(batch, &cursor),
                    let value = lengthPrefixed(batch, &cursor)
                else { return }
                record(Data(key), sequence + UInt64(index), Data(value), false)
            case 0:  // delete
                guard let key = lengthPrefixed(batch, &cursor) else { return }
                record(Data(key), sequence + UInt64(index), nil, true)
            default:
                return
            }
        }
    }

    /// Reads a varint length followed by that many bytes.
    private static func lengthPrefixed(_ bytes: [UInt8], _ cursor: inout Int) -> [UInt8]? {
        guard let length = varint(bytes, &cursor) else { return nil }
        let count = Int(length)
        guard count >= 0, cursor + count <= bytes.count else { return nil }
        let slice = Array(bytes[cursor..<(cursor + count)])
        cursor += count
        return slice
    }

    // MARK: - Varint

    /// LEB128 varint at `cursor`, advancing it; nil if the bytes run out.
    private static func varint(_ bytes: [UInt8], _ cursor: inout Int) -> UInt64? {
        var result: UInt64 = 0
        var shift: UInt64 = 0
        while cursor < bytes.count {
            let byte = bytes[cursor]
            cursor += 1
            result |= UInt64(byte & 0x7F) << shift
            if byte & 0x80 == 0 { return result }
            shift += 7
            if shift >= 64 { return nil }
        }
        return nil
    }
}
