// Keeps real infrastructure out of the repository.
//
// Usage: swift .github/scripts/no-real-data.swift
//
// It has already happened once: real addresses and host names reached public
// history through test fixtures and design mockups, and cleaning them meant
// rewriting every commit. A check before the commit is cheaper than a rewrite
// after the push.
//
// Addresses in examples, fixtures and screenshots belong to the ranges reserved
// for documentation (RFC 5737) or to private ranges. Anything else is a real
// machine somewhere — ours or a stranger's — and neither belongs here.
import Foundation

let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
    .deletingLastPathComponent().deletingLastPathComponent()
let selfPath = ".github/scripts/no-real-data.swift"

func regex(_ pattern: String, _ options: NSRegularExpression.Options = []) -> NSRegularExpression {
    do {
        return try NSRegularExpression(pattern: pattern, options: options)
    } catch {
        fatalError("pattern is a literal in this file and must compile: \(pattern)")
    }
}

// Имена, которые утекли однажды. Список дополняется, а не сокращается.
let bannedNames = regex(#"\b(valor|lafa|slotgo)\b"#, .caseInsensitive)
let privateKey = regex(#"BEGIN (OPENSSH|RSA|EC|DSA|PGP) PRIVATE KEY"#)
// Четыре октета, не окружённые цифрами: версия 1.20.0 сюда не попадает.
let addressPattern = regex(#"(?<![\d.])((?:\d{1,3}\.){3}\d{1,3})(?![\d.])"#)
let placeholders: Set = ["1.2.3.4", "5.6.7.8", "8.8.8.8"]

func say(_ line: String) {
    FileHandle.standardOutput.write(Data((line + "\n").utf8))
}

// Ranges that are never a real machine on the internet: private, loopback,
// unspecified, link-local, multicast, reserved and documentation.
let harmless: [(UInt32, Int)] = [
    ("0.0.0.0", 8), ("10.0.0.0", 8), ("127.0.0.0", 8), ("169.254.0.0", 16),
    ("172.16.0.0", 12), ("192.0.0.0", 24), ("192.0.2.0", 24), ("192.168.0.0", 16),
    ("198.18.0.0", 15), ("198.51.100.0", 24), ("203.0.113.0", 24), ("224.0.0.0", 4),
    ("240.0.0.0", 4),
].map { network, bits in
    guard let base = ipv4(network) else { fatalError("range is a literal in this file: \(network)") }
    return (base, bits)
}

/// Parses dotted-quad strictly: four octets up to 255, no leading zeros.
func ipv4(_ text: String) -> UInt32? {
    let parts = text.split(separator: ".", omittingEmptySubsequences: false)
    guard parts.count == 4 else { return nil }
    var value: UInt32 = 0
    for part in parts {
        guard let octet = UInt32(part), octet <= 255, part.count == 1 || part.first != "0" else {
            return nil
        }
        value = value << 8 | octet
    }
    return value
}

func allowed(_ address: String) -> Bool {
    // 256.1.1.1 и прочее — не адрес, а строка в тесте
    guard let value = ipv4(address) else { return true }
    if placeholders.contains(address) { return true }
    return harmless.contains { base, bits in value >> (32 - bits) == base >> (32 - bits) }
}

func problems(in name: String, text: String) -> [String] {
    var found: [String] = []
    let lines = text.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline)
    for (index, line) in lines.enumerated() {
        let line = String(line)
        let range = NSRange(line.startIndex..., in: line)
        let number = index + 1
        for match in addressPattern.matches(in: line, range: range) {
            guard let span = Range(match.range(at: 1), in: line) else { continue }
            let address = String(line[span])
            if !allowed(address) { found.append("\(name):\(number): адрес \(address)") }
        }
        if privateKey.firstMatch(in: line, range: range) != nil {
            found.append("\(name):\(number): приватный ключ")
        }
        if let banned = bannedNames.firstMatch(in: line, range: range),
            let span = Range(banned.range, in: line)
        {
            found.append("\(name):\(number): имя «\(line[span])»")
        }
    }
    return found
}

// Отслеживаемые и новые, ещё не добавленные файлы. Раньше брались только
// отслеживаемые — и новый отчёт с настоящим именем хоста прошёл проверку
// «✓» прямо перед своим первым коммитом (#12). `-z`: имена с пробелами.
func listFiles() throws -> [String] {
    let git = Process()
    git.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    git.arguments = ["git", "ls-files", "-z", "--cached", "--others", "--exclude-standard"]
    git.currentDirectoryURL = root
    let output = Pipe()
    git.standardOutput = output
    try git.run()
    let data = output.fileHandleForReading.readDataToEndOfFile()
    git.waitUntilExit()
    guard git.terminationStatus == 0 else {
        throw CocoaError(.fileReadUnknown, userInfo: [NSLocalizedDescriptionKey: "git ls-files failed"])
    }
    let names = String(decoding: data, as: UTF8.self).split(separator: "\0").map(String.init)
    return Set(names).sorted()
}

do {
    var found: [String] = []
    for name in try listFiles() where name != selfPath {
        // Binary or unreadable files can't carry a copy-pasted address in text form.
        guard let data = FileManager.default.contents(atPath: root.appendingPathComponent(name).path),
            let text = String(data: data, encoding: .utf8)
        else { continue }
        found += problems(in: name, text: text)
    }
    if found.isEmpty {
        say("✓ ни реальных адресов, ни ключей")
        exit(0)
    }
    say("реальные данные в репозитории:")
    for problem in found { say("  \(problem)") }
    say("\nЗамени на диапазоны RFC 5737 (192.0.2.x, 198.51.100.x,")
    say("203.0.113.x) и вымышленные имена.")
    exit(1)
} catch {
    say("проверка не запустилась: \(error.localizedDescription)")
    exit(2)
}
