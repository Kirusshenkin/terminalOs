public import CryptoKit
public import Foundation

/// Запись из `known_hosts`: чему мы однажды доверились.
public struct KnownHost: Identifiable, Hashable, Sendable {
    public var id: Int
    /// Имя или адрес. Пусто, если запись хеширована — тогда узнать его нельзя.
    public var host: String?
    public var algorithm: String
    public var base64: String
    /// Пометка `@revoked` или `@cert-authority`.
    public var marker: String?

    public var isHashed: Bool { host == nil }

    public var fingerprint: String {
        guard let blob = Data(base64Encoded: base64) else { return "SHA256:—" }
        let digest = SHA256.hash(data: blob)
        return "SHA256:" + Data(digest).base64EncodedString().replacingOccurrences(of: "=", with: "")
    }

    public var displayName: String {
        host ?? "имя скрыто (запись хеширована)"
    }
}

/// Читает и правит `~/.ssh/known_hosts`.
///
/// Отпечатки считаются локально — `ssh-keygen` для этого не нужен. Хешированные
/// записи мы показываем честно: имя из них не восстанавливается, и делать вид,
/// что мы его знаем, значит врать.
public enum KnownHostsFile {
    public static func defaultPath() -> String {
        NSHomeDirectory() + "/.ssh/known_hosts"
    }

    public static func parse(_ text: String) -> [KnownHost] {
        var result: [KnownHost] = []
        for (index, rawLine) in text.components(separatedBy: .newlines).enumerated() {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty, !line.hasPrefix("#") else { continue }

            var fields = line.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
            var marker: String?
            if fields.first?.hasPrefix("@") == true {
                marker = fields.removeFirst()
            }
            guard fields.count >= 3 else { continue }

            let names = fields[0]
            result.append(
                KnownHost(
                    id: index,
                    host: names.hasPrefix("|1|") ? nil : names,
                    algorithm: fields[1],
                    base64: fields[2],
                    marker: marker
                ))
        }
        return result
    }

    public static func render(_ hosts: [KnownHost], from original: String) -> String {
        let keep = Set(hosts.map(\.id))
        return original.components(separatedBy: .newlines)
            .enumerated()
            .filter { index, line in
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.isEmpty || trimmed.hasPrefix("#") { return true }
                return keep.contains(index)
            }
            .map(\.element)
            .joined(separator: "\n")
    }
}
