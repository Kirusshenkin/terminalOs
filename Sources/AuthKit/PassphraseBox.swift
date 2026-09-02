import CommonCrypto
public import CryptoKit
public import Foundation

/// Экспорт профиля под парольной фразой.
///
/// Прежде ключ выводился HKDF с фиксированной солью — быстрым по определению.
/// Имея файл экспорта, атакующий перебирал бы миллиарды фраз в секунду офлайн.
/// Здесь — PBKDF2-SHA256 с высокой итерацией и случайной солью в заголовке: тот
/// же перебор становится непозволительно дорогим. PBKDF2, а не Argon2id, только
/// потому, что он есть в системе (CommonCrypto) и не тянет чужую библиотеку; при
/// нужде в memory-hard KDF это меняется в одном месте.
public enum PassphraseBox {
    public static let magic: [UInt8] = Array("PHEX".utf8)
    public static let version: UInt16 = 1
    /// OWASP-ориентир для PBKDF2-SHA256 (2023): порядок сотен тысяч.
    public static let iterations: UInt32 = 600_000
    private static let saltLength = 16

    public enum BoxError: Error, Equatable {
        case notAnExport
        case unsupportedVersion(UInt16)
        case truncated
        /// Фраза не подошла или файл подменён — AEAD не различает эти случаи,
        /// и это правильно: обе причины означают «открыть нельзя».
        case wrongPassphrase
    }

    /// Заголовок в открытую (соль и число итераций не секрет), дальше — AEAD.
    /// Формат: `PHEX` | версия(2) | итерации(4) | соль(16) | ChaChaPoly-бокс.
    public static func seal(_ plaintext: Data, passphrase: String) throws -> Data {
        var salt = Data(count: saltLength)
        _ = salt.withUnsafeMutableBytes { SecRandomCopyBytes(kSecRandomDefault, saltLength, $0.baseAddress!) }
        let key = try derive(passphrase: passphrase, salt: salt, iterations: iterations)
        let box = try ChaChaPoly.seal(plaintext, using: key).combined

        var out = Data(magic)
        out.append(bigEndian(version))
        out.append(bigEndian(iterations))
        out.append(salt)
        out.append(box)
        return out
    }

    public static func open(_ data: Data, passphrase: String) throws -> Data {
        guard data.count >= 4 + 2 + 4 + saltLength else { throw BoxError.truncated }
        guard Array(data.prefix(4)) == magic else { throw BoxError.notAnExport }
        var offset = 4
        let ver = readUInt16(data, at: &offset)
        guard ver == version else { throw BoxError.unsupportedVersion(ver) }
        let iters = readUInt32(data, at: &offset)
        let salt = data.subdata(in: offset..<(offset + saltLength))
        offset += saltLength
        let box = data.subdata(in: offset..<data.count)

        let key = try derive(passphrase: passphrase, salt: salt, iterations: iters)
        do {
            return try ChaChaPoly.open(ChaChaPoly.SealedBox(combined: box), using: key)
        } catch {
            // Сырая ошибка CryptoKit наверху бесполезна: человеку важно одно —
            // фраза не та (или файл битый), а не имя типа исключения.
            throw BoxError.wrongPassphrase
        }
    }

    /// PBKDF2-SHA256 → 32-байтный ключ. Пустая фраза допускается вызывающим —
    /// проверять её силу не дело KDF.
    static func derive(passphrase: String, salt: Data, iterations: UInt32) throws -> SymmetricKey {
        let password = Array(passphrase.utf8)
        var derived = [UInt8](repeating: 0, count: 32)
        let status = salt.withUnsafeBytes { saltBytes -> Int32 in
            CCKeyDerivationPBKDF(
                CCPBKDFAlgorithm(kCCPBKDF2),
                password, password.count,
                saltBytes.bindMemory(to: UInt8.self).baseAddress, salt.count,
                CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256),
                iterations,
                &derived, derived.count
            )
        }
        guard status == kCCSuccess else { throw BoxError.truncated }
        defer { for index in derived.indices { derived[index] = 0 } }
        return SymmetricKey(data: Data(derived))
    }

    // MARK: - Мелочи разбора

    private static func bigEndian(_ value: UInt16) -> Data {
        Data([UInt8(value >> 8), UInt8(value & 0xff)])
    }
    private static func bigEndian(_ value: UInt32) -> Data {
        Data([
            UInt8(value >> 24 & 0xff), UInt8(value >> 16 & 0xff),
            UInt8(value >> 8 & 0xff), UInt8(value & 0xff),
        ])
    }
    private static func readUInt16(_ data: Data, at offset: inout Int) -> UInt16 {
        let value = UInt16(data[data.startIndex + offset]) << 8
            | UInt16(data[data.startIndex + offset + 1])
        offset += 2
        return value
    }
    private static func readUInt32(_ data: Data, at offset: inout Int) -> UInt32 {
        var value: UInt32 = 0
        for index in 0..<4 { value = value << 8 | UInt32(data[data.startIndex + offset + index]) }
        offset += 4
        return value
    }
}
