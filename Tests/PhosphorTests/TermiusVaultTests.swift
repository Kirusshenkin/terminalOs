import Foundation
import Testing

@testable import HostsKit

// Все фикстуры здесь синтетические: выдуманный ключ (32 байта `0x42`),
// выдуманные адреса и логины. Ни байта реальных данных Termius — репозиторий
// публичный.

// MARK: - Snappy

@Suite struct SnappyTests {
    /// Блок, сжатый эталонным `github.com/golang/snappy`: литералы и обратная
    /// ссылка-копия в одном потоке.
    @Test func decompressesReferenceBlock() throws {
        let compressed = try #require(
            Data(base64Encoded: "U1xQaG9zcGhvciByZWFkcyBUZXJtaXVzLiC2GAAwISEgMTIzNDU2Nzg5MA=="))
        let expected = "Phosphor reads Termius. Phosphor reads Termius. Phosphor reads Termius!! 1234567890"
        let out = try #require(Snappy.decompress([UInt8](compressed)))
        #expect(String(decoding: out, as: UTF8.self) == expected)
    }

    @Test func rejectsTruncatedStream() {
        // Длина обещает больше байтов, чем есть, — поток битый, вернётся nil.
        #expect(Snappy.decompress([0xFF, 0xFF, 0x7F, 0x00]) == nil)
    }
}

// MARK: - V8 decoder

@Suite struct V8DecoderTests {
    /// Объект со строкой UTF-16, отрицательным зигзаг-целым и null — типы,
    /// которые сборка хостов не трогает, но формат обязан понимать.
    @Test func decodesValueTypes() throws {
        let bytes: [UInt8] = [
            0x00,  // version varint, consumed by the envelope
            UInt8(ascii: "o"),
            UInt8(ascii: "\""), 0x01, UInt8(ascii: "a"),  // key "a"
            UInt8(ascii: "c"), 0x02, 0xA9, 0x03,  // value U+03A9 (Ω), UTF-16LE
            UInt8(ascii: "\""), 0x01, UInt8(ascii: "n"),  // key "n"
            UInt8(ascii: "I"), 0x09,  // value zigzag 9 → -5
            UInt8(ascii: "\""), 0x01, UInt8(ascii: "z"),  // key "z"
            UInt8(ascii: "_"),  // value undefined → null
            UInt8(ascii: "{"), 0x03,  // object terminator, property count
        ]
        let fields = try #require(V8Decoder.decodeObject(Data(bytes)))
        #expect(fields["a"] == .string("\u{03A9}"))
        #expect(fields["n"] == .int(-5))
        #expect(fields["z"] == .null)
    }

    @Test func rejectsNonObject() {
        #expect(V8Decoder.decodeObject(Data()) == nil)
        // Version only, no value after it.
        #expect(V8Decoder.decodeObject(Data([0x00])) == nil)
    }
}

// MARK: - Termius vault (end to end)

@Suite struct TermiusVaultTests {
    // Base64-фикстуры — целиком, без переносов: ломать литерал внутри значит
    // ломать сверку байт с тем, что сгенерировал эталонный LevelDB.
    // swiftlint:disable line_length
    /// Синтетический LevelDB: два хоста, два ssh_config, одна identity. `.ldb`
    /// получен компакцией (путь SSTable + Snappy), `.log` — перезапись адреса
    /// второго хоста (проверяет выбор последней версии поверх таблицы).
    private static let ldb =
        "1wYsAA2QAQAEAQEBAQMACQF8/w9vIgJpZEmQAyIIbG9jYWxfaWRJCiIIaWRlbnRpdHkJHgTYBB0eSBJ7AiIHY29udGVudCJMQkFFREF2AQDASDdMWkkzNWRHN3FKUGJMQmk0UzhhcHdIeU9kYmRYVnVsT1J3VERnPT17BAQJbAIBBAmbFZwEkgMdfgAMGXwQSEJBRUV2ewCwRFhDSWdIRzJuanRVeGlvV1locTliY0ROdzJZVTNjMVVhR0trMD17AwEMlAEMIRgABTp8ADb6ABl8EHBCQUVGenwA8FhZZisrdkllVWZZa0o0SnFzbTBxd0dxN1FCcFUxRnhTTzNXWDZjS29QNncvUTlBOEpmdDFBN0tpQnhyd1R0M3I2OEpCYktNdUdCWENjPXsDAQzLARABAQEBATqkAATIAT0gMAIiCnNzaF9jb25maWcpvgCQLkABAAouvgEUhAFCQUVCdscA8GFBMUxIZ1hKNTNJT0NlZTMrTkZLdWxORU52YkpIVVk2RGNYRUdVNWRLYUpQbGZhMmoydEhPVERyc0p6VndIWlNFNGU4M1pLdWNOdW9yTHg1OEZUa2lRenVlNnJIS0sxU05YZCH3FKoBAgECAAkBAP9NlADKLtgAAARG2AA2GAIu2AAQZEJBRUN21wDwS0NoeEFwMSs3RlAzL054T2ExSGdSTVNyMlJXbjNoaDA4YzEzZ2ZZUitEOWZRYUZCN3I1eSt2SmZycSt4a3VIMFkxcHsEAAAAAAEAAAABuYtKKggcAAAAAAEAAAABBjSfkBcUAAkDAQH/CQEoALwEAAAAAAEAAAABf7g+BcEECtAEFgAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAABX+4CLJHVH2w=="
    private static let log =
        "vp8b2ccAAQYAAAAAAAAAAQAAAAEFABABAQKyAQD/D28iAmlkScoBIghsb2NhbF9pZEkEIgpzc2hfY29uZmlnbyICaWRJkgMiCGxvY2FsX2lkSQx7AiIHY29udGVudCJsQkFFR0FBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUNNcGdvZG9RUEN5ZkFnYStsc29Da09tcCs1NlZ6Q0hmVW9SbHdDNTFxQk5WZy9vSWxLQy9lemkvaGp1Yzk0QXlmSmtNWEdFL3M9ewQ="
    // swiftlint:enable line_length

    // Ключ Termius в фикстуре — 32 байта `0x42`.
    private static let key = Data(repeating: 0x42, count: 32)

    /// Разворачивает фикстуру в каталог и отдаёт путь; каталог удаляется в
    /// `teardown` вызывающего.
    private func makeStore() throws -> String {
        let directory = NSTemporaryDirectory() + "termius-fixture-" + UUID().uuidString
        try FileManager.default.createDirectory(
            atPath: directory, withIntermediateDirectories: true)
        try #require(Data(base64Encoded: Self.ldb)).write(to: url(directory, "000004.ldb"))
        try #require(Data(base64Encoded: Self.log)).write(to: url(directory, "000002.log"))
        return directory
    }

    private func url(_ directory: String, _ name: String) -> URL {
        URL(fileURLWithPath: directory + "/" + name)
    }

    @Test func importsLinkedHosts() throws {
        let directory = try makeStore()
        defer { try? FileManager.default.removeItem(atPath: directory) }

        let hosts = TermiusVault.hosts(
            directories: [directory], localKey: Self.key, existing: [], defaultUser: "tester")

        #expect(hosts.count == 2)
        // Отсортировано по имени: "10.9.9.9"/"Bravo"? Имя Bravo идёт после Alpha.
        let alpha = try #require(hosts.first { $0.address == "10.0.0.1" })
        #expect(alpha.name == "Alpha")
        #expect(alpha.user == "deploy")  // через ssh_config → identity
        #expect(alpha.port == 2222)  // порт из ssh_config
        #expect(alpha.osName == "ubuntu")
        #expect(alpha.tags == ["termius"])

        let bravo = try #require(hosts.first { $0.address == "10.9.9.9" })
        #expect(bravo.name == "Bravo")  // перезапись из .log победила
        #expect(bravo.user == "tester")  // нет identity → defaultUser
        #expect(bravo.port == 22)
    }

    @Test func skipsHostsAlreadyPresent() throws {
        let directory = try makeStore()
        defer { try? FileManager.default.removeItem(atPath: directory) }

        let existing = ServerHost(name: "x", address: "10.0.0.1", port: 2222, user: "deploy")
        let hosts = TermiusVault.hosts(
            directories: [directory], localKey: Self.key, existing: [existing], defaultUser: "tester")
        #expect(hosts.contains { $0.address == "10.0.0.1" } == false)
        #expect(hosts.count == 1)
    }

    @Test func wrongKeyYieldsNoHosts() throws {
        let directory = try makeStore()
        defer { try? FileManager.default.removeItem(atPath: directory) }

        let hosts = TermiusVault.hosts(
            directories: [directory], localKey: Data(repeating: 0x00, count: 32),
            existing: [], defaultUser: "tester")
        #expect(hosts.isEmpty)
    }

    @Test func countsWithoutDecrypting() throws {
        let directory = try makeStore()
        defer { try? FileManager.default.removeItem(atPath: directory) }
        #expect(TermiusVault.availableHostCount(directories: [directory]) == 2)
    }
}
