public import CryptoKit
public import Foundation

/// Что говорит последний релиз о себе: `latest.json` из ассетов GitHub.
///
/// Бэкенда нет, поэтому сигнал об обновлении — сам релиз. Манифест подписан
/// ключом P-256 (§20.1 плана): HTTPS доказывает, что файл пришёл с GitHub,
/// подпись — что его выпустили мы, а не тот, кто получил доступ к релизам.
public struct UpdateManifest: Codable, Sendable, Equatable {
    public var version: String
    public var build: Int
    public var url: URL
    public var size: Int
    public var sha256: String

    public init(version: String, build: Int, url: URL, size: Int, sha256: String) {
        self.version = version
        self.build = build
        self.url = url
        self.size = size
        self.sha256 = sha256
    }

    public enum Problem: Error, Equatable {
        /// Подпись не сошлась: файл не наш или испорчен. Ничего не ставим.
        case badSignature
        /// Ссылка ведёт не в наши релизы — даже с верной подписью не идём туда.
        case foreignURL
        case malformed
    }

    /// Публичный ключ, которым проверяется подпись релиза (DER, base64).
    /// Приватная половина живёт только в секретах GitHub.
    public static let publicKey =
        "MFkwEwYHKoZIzj0CAQYIKoZIzj0DAQcDQgAEKxKEJxjRPraVZCnacN4gN09uyd7s5YceRagMQ6FlNIaEbT2hhcuh94iUlEltbVlqNk8cG5FlDGnYG8HQvF3QAA=="

    /// Откуда берутся манифест и архивы. Подписанная ссылка в другое место —
    /// всё равно отказ: ключ могли украсть, домен — нет.
    public static let releasesPrefix = "https://github.com/Kirusshenkin/terminalOs/releases/download/"

    /// Проверяет подпись (`openssl dgst -sha256 -sign`, DER) и разбирает
    /// манифест. Чистая функция: ключ передаётся, чтобы тест мог подставить свой.
    public static func verified(
        _ data: Data, signature: Data, publicKey: String = publicKey
    ) throws -> UpdateManifest {
        guard let keyData = Data(base64Encoded: publicKey),
            let key = try? P256.Signing.PublicKey(derRepresentation: keyData),
            let ecdsa = try? P256.Signing.ECDSASignature(derRepresentation: signature),
            key.isValidSignature(ecdsa, for: data)
        else { throw Problem.badSignature }
        // Лишние поля манифеста (install, mcp) нам не нужны и не мешают.
        guard let manifest = try? JSONDecoder().decode(UpdateManifest.self, from: data) else {
            throw Problem.malformed
        }
        guard manifest.url.absoluteString.hasPrefix(releasesPrefix) else { throw Problem.foreignURL }
        return manifest
    }

    /// Новее ли релиз того, что запущено. Сравнивается номер сборки: он только
    /// растёт (число коммитов), а строку версии сравнивать незачем.
    public func isNewer(thanBuild current: Int) -> Bool { build > current }

    /// Совпадает ли скачанный архив с тем, что обещал манифест.
    public func matches(_ archive: Data) -> Bool {
        guard archive.count == size else { return false }
        let digest = SHA256.hash(data: archive).map { String(format: "%02x", $0) }.joined()
        return digest == sha256.lowercased()
    }
}
