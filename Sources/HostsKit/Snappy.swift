import Foundation

/// Snappy block decompression — the one format LevelDB compresses its blocks
/// with.
///
/// LevelDB по умолчанию жмёт блоки Snappy, поэтому без распаковки из `.ldb`
/// Termius читается хорошо если половина. Формат простой: длина результата
/// варинтом, дальше литералы и ссылки-копии на уже распакованное. Своя сотня
/// строк вместо зависимости (CLAUDE.md).
///
/// Only decompression: Phosphor reads these blocks, it never writes them.
enum Snappy {
    /// Decompressed bytes, or nil when the stream is malformed — a truncated
    /// or corrupt block is skipped, not fatal.
    static func decompress(_ input: [UInt8]) -> [UInt8]? {
        var cursor = 0
        guard let expected = varint(input, &cursor) else { return nil }
        var out = [UInt8]()
        out.reserveCapacity(expected)

        while cursor < input.count {
            let tag = input[cursor]
            cursor += 1
            let ok =
                tag & 0x03 == 0
                ? literal(tag, input, &cursor, &out)
                : copyElement(tag, input, &cursor, &out)
            guard ok else { return nil }
        }
        return out.count == expected ? out : nil
    }

    /// Literal: upper six bits are length-1, or a selector for how many
    /// following little-endian bytes carry the length.
    private static func literal(
        _ tag: UInt8, _ input: [UInt8], _ cursor: inout Int, _ out: inout [UInt8]
    ) -> Bool {
        var length = Int(tag >> 2)
        if length >= 60 {
            let extra = length - 59
            guard cursor + extra <= input.count else { return false }
            length = 0
            for shift in 0..<extra { length |= Int(input[cursor + shift]) << (8 * shift) }
            cursor += extra
        }
        length += 1
        guard cursor + length <= input.count else { return false }
        out.append(contentsOf: input[cursor..<(cursor + length)])
        cursor += length
        return true
    }

    /// Copy element: a back-reference whose offset width (1, 2 or 4 bytes) is
    /// the tag's type bits.
    private static func copyElement(
        _ tag: UInt8, _ input: [UInt8], _ cursor: inout Int, _ out: inout [UInt8]
    ) -> Bool {
        let length: Int
        let offset: Int
        switch tag & 0x03 {
        case 1:  // 1-byte offset: length 4..11, offset up to 2047.
            length = 4 + Int((tag >> 2) & 0x07)
            guard cursor + 1 <= input.count else { return false }
            offset = Int(tag >> 5) << 8 | Int(input[cursor])
            cursor += 1
        case 2:  // 2-byte offset.
            length = 1 + Int(tag >> 2)
            guard cursor + 2 <= input.count else { return false }
            offset = Int(input[cursor]) | Int(input[cursor + 1]) << 8
            cursor += 2
        default:  // 4-byte offset.
            length = 1 + Int(tag >> 2)
            guard cursor + 4 <= input.count else { return false }
            offset =
                Int(input[cursor]) | Int(input[cursor + 1]) << 8
                | Int(input[cursor + 2]) << 16 | Int(input[cursor + 3]) << 24
            cursor += 4
        }
        return copy(offset: offset, length: length, into: &out)
    }

    /// Copies `length` bytes from `offset` back in the output. Overlapping
    /// copies are valid in Snappy, so this goes one byte at a time.
    private static func copy(offset: Int, length: Int, into out: inout [UInt8]) -> Bool {
        guard offset > 0, offset <= out.count, length >= 0 else { return false }
        var source = out.count - offset
        for _ in 0..<length {
            out.append(out[source])
            source += 1
        }
        return true
    }

    /// LEB128 varint at `cursor`, advancing it; nil if the bytes run out.
    private static func varint(_ input: [UInt8], _ cursor: inout Int) -> Int? {
        var result = 0
        var shift = 0
        while cursor < input.count {
            let byte = input[cursor]
            cursor += 1
            result |= Int(byte & 0x7F) << shift
            if byte & 0x80 == 0 { return result }
            shift += 7
            if shift > 28 { return nil }
        }
        return nil
    }
}
