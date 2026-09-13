public import Foundation

/// Reads Termius's *connection history* — the one thing it leaves in the clear.
///
/// Сохранённые хосты Termius держит зашифрованными: каждая запись в его
/// IndexedDB — это `04 01`, случайный nonce и бокс libsodium (XSalsa20-Poly1305),
/// а ключ к ним выводится из `localKey` в связке ключей под службой `Termius`.
/// Прочитать эту связку может только сам Termius — чужому процессу система
/// покажет диалог и спросит пароль учётной записи. Поэтому здесь честно берётся
/// то, что лежит в открытую: журнал машин, к которым подключались, — адрес и
/// геометка рядом с ним.
///
/// Разбор идёт по печатным строкам из файлов LevelDB: адрес и стоящая рядом
/// метка города. Это приближение, и оно так и подписано — тегом
/// `termius-history`, а не выдаётся за настоящий список серверов.
public enum TermiusHistory {
    public struct Entry: Equatable, Sendable {
        public var address: String
        /// City / region / country as Termius stored it, when one sat nearby.
        public var location: String?

        public init(address: String, location: String? = nil) {
            self.address = address
            self.location = location
        }
    }

    /// Where Termius keeps its LevelDB, in both the sandboxed and the
    /// non-sandboxed layout. The caller reads whichever exists.
    public static func defaultDirectories() -> [String] {
        let home = NSHomeDirectory()
        return [
            home + "/Library/Application Support/Termius/IndexedDB"
                + "/file__0.indexeddb.leveldb",
            home + "/Library/Containers/com.termius.mac/Data/Library/Application Support"
                + "/Termius/IndexedDB/file__0.indexeddb.leveldb",
        ]
    }

    /// Pulls entries out of raw LevelDB bytes. Pure, so it runs on a fixture in
    /// tests without any Termius install.
    public static func parse(_ data: Data) -> [Entry] {
        let tokens = printableStrings(in: data, minimum: 3)
        var entries: [Entry] = []
        var seen: Set<String> = []
        for (index, token) in tokens.enumerated() {
            for address in addresses(in: token) where !seen.contains(address) {
                seen.insert(address)
                entries.append(Entry(address: address, location: nearbyLocation(tokens, after: index)))
            }
        }
        return entries.sorted { $0.address < $1.address }
    }

    /// Reads and merges the history from whichever directory Termius uses.
    public static func scan(directories: [String] = defaultDirectories()) -> [Entry] {
        let manager = FileManager.default
        var merged: [String: Entry] = [:]
        for directory in directories {
            guard let names = try? manager.contentsOfDirectory(atPath: directory) else { continue }
            for name in names where name.hasSuffix(".ldb") || name.hasSuffix(".log") {
                // `try?`: a locked or partial LevelDB file is skipped, not an
                // error to report — the rest still yields history.
                guard let data = try? Data(contentsOf: URL(fileURLWithPath: directory + "/" + name))
                else { continue }
                for entry in parse(data) where merged[entry.address] == nil || entry.location != nil {
                    merged[entry.address] = entry
                }
            }
        }
        return merged.values.sorted { $0.address < $1.address }
    }

    /// Turns history into hosts to offer, deduplicating against what exists.
    ///
    /// Логин и порт остались в зашифрованной части хранилища, поэтому здесь их
    /// нет и выдумывать их нечем: подставляется имя текущего пользователя как
    /// заготовка, которую человек правит в форме хоста. Ценность записи — в
    /// адресе: он настоящий.
    public static func hosts(from entries: [Entry], existing: [ServerHost]) -> [ServerHost] {
        let taken = Set(existing.map { $0.address })
        return entries.filter { !taken.contains($0.address) }.map { entry in
            ServerHost(
                name: entry.location.map { "\(entry.address) · \($0)" } ?? entry.address,
                address: entry.address, port: 22, user: NSUserName(),
                tags: ["termius-history"]
            )
        }
    }

    // MARK: - Извлечение

    /// Every run of printable ASCII of at least `minimum` characters.
    private static func printableStrings(in data: Data, minimum: Int) -> [String] {
        var result: [String] = []
        var current: [UInt8] = []
        for byte in data {
            if byte >= 0x20, byte < 0x7F {
                current.append(byte)
            } else {
                if current.count >= minimum {
                    result.append(String(decoding: current, as: UTF8.self))
                }
                current.removeAll(keepingCapacity: true)
            }
        }
        if current.count >= minimum { result.append(String(decoding: current, as: UTF8.self)) }
        return result
    }

    /// Valid dotted-quad addresses inside a token, filtering obvious noise such
    /// as version numbers (which never have four parts).
    private static func addresses(in token: String) -> [String] {
        var found: [String] = []
        let scalars = Array(token)
        var index = 0
        while index < scalars.count {
            if scalars[index].isNumber, index == 0 || !scalars[index - 1].isNumber,
                index == 0 || scalars[index - 1] != "."
            {
                var end = index
                while end < scalars.count, scalars[end].isNumber || scalars[end] == "." { end += 1 }
                let candidate = String(scalars[index..<end])
                if isDottedQuad(candidate),
                    isStandalone(scalars, start: index, end: end),
                    isReachable(candidate)
                {
                    found.append(candidate)
                }
                index = end
            } else {
                index += 1
            }
        }
        return found
    }

    /// Адрес сам по себе, а не кусок чего-то большего.
    ///
    /// `v1.2.3.4-beta` разбирается как безупречный dotted-quad — и он им не
    /// является. Проверяем, что вплотную к числу не стоит буква: версия, путь
    /// и имя файла так отсеиваются, а адрес в кавычках или в скобках остаётся.
    private static func isStandalone(_ scalars: [Character], start: Int, end: Int) -> Bool {
        let glued: (Character) -> Bool = { $0.isLetter || $0 == "-" || $0 == "_" || $0 == "/" }
        if start > 0, glued(scalars[start - 1]) { return false }
        if end < scalars.count, glued(scalars[end]) { return false }
        return true
    }

    /// Адрес, к которому вообще можно подключиться.
    ///
    /// Нули, петля и служебные диапазоны в журнале встречаются, но сервером не
    /// бывают: предложить их к импорту — значит завести хост, которого нет.
    private static func isReachable(_ address: String) -> Bool {
        let octets = address.split(separator: ".").compactMap { Int($0) }
        guard octets.count == 4, let first = octets.first else { return false }
        // 0.x — «этот узел», 127.x — петля, 224+ — многоадресные и служебные.
        guard first != 0, first != 127, first < 224 else { return false }
        return octets != [255, 255, 255, 255]
    }

    private static func isDottedQuad(_ text: String) -> Bool {
        let parts = text.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 4 else { return false }
        return parts.allSatisfy { part in
            guard let value = Int(part), value >= 0, value <= 255 else { return false }
            // A leading zero on a multi-digit octet is not how Termius writes
            // addresses — it is checksum noise that happens to parse.
            return part.count == 1 || part.first != "0"
        }
    }

    /// A "City, RR, CC" geo-tag within a few tokens after the address.
    private static func nearbyLocation(_ tokens: [String], after index: Int) -> String? {
        let upper = min(index + 4, tokens.count - 1)
        guard upper > index else { return nil }
        for candidate in tokens[(index + 1)...upper] where looksLikeLocation(candidate) {
            return candidate.trimmingCharacters(in: CharacterSet(charactersIn: "\"' "))
        }
        return nil
    }

    private static func looksLikeLocation(_ token: String) -> Bool {
        let trimmed = token.trimmingCharacters(in: CharacterSet(charactersIn: "\"' "))
        let parts = trimmed.split(separator: ",").map {
            $0.trimmingCharacters(in: .whitespaces)
        }
        // City, region code, country code — the last two are two-letter codes.
        guard parts.count == 3, let country = parts.last else { return false }
        return country.count == 2 && country.allSatisfy { $0.isLetter && $0.isUppercase }
            && !parts[0].isEmpty && parts[0].first?.isLetter == true
    }
}
