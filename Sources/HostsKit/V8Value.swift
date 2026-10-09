public import Foundation

/// The slice of V8's structured-clone format that Termius's IndexedDB uses.
///
/// Каждая запись Termius в IndexedDB — это объект, сериализованный V8 и
/// завёрнутый Blink: число-версия, потом теги значений. Нам нужен крошечный
/// угол формата — верхний объект со строковыми ключами, где значения бывают
/// строкой (включая шифртекст `BA…`), целым (`local_id`, `id`), вложенным
/// объектом-ссылкой (`{id, local_id}`) или пустышкой. Массивы, даты, typed
/// arrays и прочее Termius в этих записях не держит, поэтому их здесь нет.
///
/// Только чтение: Phosphor разбирает чужой формат, но никогда его не пишет.
public enum V8Value: Equatable, Sendable {
    case string(String)
    case int(Int64)
    case double(Double)
    case object([String: V8Value])
    case null

    /// Строковое значение поля, если оно строка.
    public var stringValue: String? {
        if case .string(let text) = self { return text }
        return nil
    }

    /// Целое значение поля, если оно целое.
    public var intValue: Int64? {
        if case .int(let value) = self { return value }
        return nil
    }

    /// Вложенный объект-ссылка, если это объект.
    public var objectValue: [String: V8Value]? {
        if case .object(let fields) = self { return fields }
        return nil
    }
}

/// Decodes one Blink-wrapped V8 record into its top-level object.
///
/// Разбор устроен так, чтобы испорченная запись не роняла импорт: встретив
/// неизвестный тег или конец данных, декодер возвращает `nil`, а вызывающий
/// просто пропускает запись. Это не проглоченная ошибка — формат чужой и может
/// меняться между версиями Termius, и единственная разумная реакция на
/// непонятную запись — не брать её, а не падать на всём импорте.
public enum V8Decoder {
    /// Top-level object of a record, or nil when the bytes are not a V8 object
    /// we understand.
    public static func decodeObject(_ data: Data) -> [String: V8Value]? {
        var reader = Reader(bytes: [UInt8](data))
        guard reader.readEnvelope() else { return nil }
        guard case .object(let fields)? = reader.readValue() else { return nil }
        return fields
    }

    private struct Reader {
        let bytes: [UInt8]
        var index = 0

        /// Reads a LEB128 unsigned varint; returns 0 and parks at the end when
        /// the bytes run out, so a truncated record ends the parse instead of
        /// trapping.
        mutating func varint() -> UInt64 {
            var result: UInt64 = 0
            var shift: UInt64 = 0
            while index < bytes.count {
                let byte = bytes[index]
                index += 1
                result |= UInt64(byte & 0x7F) << shift
                if byte & 0x80 == 0 { break }
                shift += 7
                if shift >= 64 { break }
            }
            return result
        }

        /// Между полями Blink расставляет нулевые байты-заполнители; значимый
        /// тег — первый ненулевой.
        mutating func skipPadding() {
            while index < bytes.count, bytes[index] == 0 { index += 1 }
        }

        /// Skips the record's version prefix and the Blink envelope tags
        /// (`0xFF` followed by a version varint, up to twice) before the value.
        /// Returns false if there is nothing left to read.
        mutating func readEnvelope() -> Bool {
            guard !bytes.isEmpty else { return false }
            _ = varint()
            while index < bytes.count, bytes[index] == 0xFF {
                index += 1
                _ = varint()
            }
            return index < bytes.count
        }

        mutating func readValue() -> V8Value? {
            skipPadding()
            guard index < bytes.count else { return nil }
            let tag = bytes[index]
            switch tag {
            case UInt8(ascii: "\""), UInt8(ascii: "S"), UInt8(ascii: "c"):
                return readString().map(V8Value.string)
            default:
                break
            }
            index += 1
            switch tag {
            case UInt8(ascii: "I"):
                // Знаковое целое в зигзаг-кодировке.
                let raw = varint()
                return .int(Int64(bitPattern: raw >> 1) ^ -Int64(bitPattern: raw & 1))
            case UInt8(ascii: "U"):
                return .int(Int64(bitPattern: varint()))
            case UInt8(ascii: "N"):
                guard index + 8 <= bytes.count else { return nil }
                let value = bytes[index..<(index + 8)].withUnsafeBytes {
                    $0.loadUnaligned(as: Double.self)
                }
                index += 8
                return .double(value)
            case UInt8(ascii: "T"), UInt8(ascii: "F"), UInt8(ascii: "_"), UInt8(ascii: "0"):
                // true / false / undefined / null — всё, что нам неинтересно,
                // сводится к «пусто».
                return .null
            case UInt8(ascii: "o"):
                return readObject()
            default:
                return nil
            }
        }

        /// Reads a string value: tag byte, byte length, then the bytes —
        /// Latin-1/UTF-8 for `"`/`S`, UTF-16LE for `c`.
        mutating func readString() -> String? {
            skipPadding()
            guard index < bytes.count else { return nil }
            let tag = bytes[index]
            index += 1
            let length = Int(varint())
            guard length >= 0, index + length <= bytes.count else { return nil }
            let slice = bytes[index..<(index + length)]
            index += length
            if tag == UInt8(ascii: "c") {
                var scalars: [Unicode.Scalar] = []
                var offset = slice.startIndex
                while offset + 1 < slice.endIndex {
                    let unit = UInt16(slice[offset]) | UInt16(slice[offset + 1]) << 8
                    if let scalar = Unicode.Scalar(unit) { scalars.append(scalar) }
                    offset += 2
                }
                var string = ""
                string.unicodeScalars.append(contentsOf: scalars)
                return string
            }
            return String(decoding: slice, as: UTF8.self)
        }

        /// Reads an object: `(key, value)` pairs until the `{` terminator,
        /// then the trailing property count.
        mutating func readObject() -> V8Value? {
            var fields: [String: V8Value] = [:]
            while true {
                skipPadding()
                guard index < bytes.count else { return nil }
                if bytes[index] == UInt8(ascii: "{") { break }
                guard let key = readString(), let value = readValue() else { return nil }
                fields[key] = value
            }
            index += 1  // consume '{'
            _ = varint()  // property count, which we do not need
            return .object(fields)
        }
    }
}
