import Foundation
import Testing

@testable import HostsKit
@testable import KeysKit

@Suite("Импорт: Termius, ключи, известные хосты")
struct ImportTests {
    // MARK: - История Termius

    @Test("адрес и геометка вытаскиваются из байтов, версии — нет")
    func termiusBasic() {
        // Так это лежит в LevelDB: адрес, потом рядом «город, регион, страна».
        var bytes = Data()
        bytes.append(contentsOf: "app-version".utf8)
        bytes.append(0)
        bytes.append(contentsOf: "1.20.0".utf8)  // версия — не адрес
        bytes.append(0)
        bytes.append(contentsOf: "192.0.2.10".utf8)
        bytes.append(0)
        bytes.append(contentsOf: "location".utf8)
        bytes.append(0)
        bytes.append(contentsOf: "Sampletown, ST, ZZ".utf8)
        bytes.append(0)

        let entries = TermiusHistory.parse(bytes)
        #expect(entries.count == 1)
        #expect(entries.first?.address == "192.0.2.10")
        #expect(entries.first?.location == "Sampletown, ST, ZZ")
    }

    @Test("повторный адрес в разных версиях записи не задваивается")
    func termiusDedup() {
        var bytes = Data()
        for _ in 0..<3 {
            bytes.append(contentsOf: "198.51.100.20".utf8)
            bytes.append(0)
            bytes.append(contentsOf: "Example City, EX, ZZ".utf8)
            bytes.append(0)
        }
        let entries = TermiusHistory.parse(bytes)
        #expect(entries.count == 1)
        #expect(entries.first?.location == "Example City, EX, ZZ")
    }

    @Test("не-адреса отбрасываются: октет больше 255 и ведущий ноль")
    func termiusRejectsJunk() {
        var bytes = Data()
        for token in ["256.1.1.1", "01.2.3.4", "1.2.3", "10.0.0.1"] {
            bytes.append(contentsOf: token.utf8)
            bytes.append(0)
        }
        let entries = TermiusHistory.parse(bytes)
        #expect(entries.map(\.address) == ["10.0.0.1"])
    }

    @Test("история превращается в хосты, уже добавленные — пропускаются")
    func termiusToHosts() {
        let entries = [
            TermiusHistory.Entry(address: "10.0.0.1", location: "Sampletown, ST, ZZ"),
            TermiusHistory.Entry(address: "10.0.0.2", location: nil),
        ]
        let existing = [ServerHost(name: "уже есть", address: "10.0.0.1")]
        let hosts = TermiusHistory.hosts(from: entries, existing: existing)
        #expect(hosts.count == 1)
        #expect(hosts.first?.address == "10.0.0.2")
        #expect(hosts.first?.tags.contains("termius-history") == true)
    }

    // MARK: - Локальные ключи

    @Test("публичный ключ разбирается в имя, алгоритм и комментарий")
    func localKeyParse() {
        let pub = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIabc admin@example"
        let key = LocalKeys.parse(
            privatePath: "/home/k/.ssh/id_ed25519", publicText: pub, hasPrivate: true)
        #expect(key?.name == "id_ed25519")
        #expect(key?.algorithm == "ssh-ed25519")
        #expect(key?.comment == "admin@example")
        #expect(key?.hasPrivate == true)
        #expect(key?.bits == 256)
    }

    @Test("ключ без пары помечается, но всё равно читается")
    func localKeyNoPrivate() {
        let pub = "ssh-rsa AAAAB3NzaC1yc2E deploy"
        let key = LocalKeys.parse(
            privatePath: "/home/k/.ssh/orphan", publicText: pub, hasPrivate: false)
        #expect(key?.hasPrivate == false)
        #expect(key?.comment == "deploy")
    }

    // MARK: - known_hosts

    @Test("известный хост становится сервером, хешированный — нет")
    func knownHostConversion() {
        let plain = KnownHost(
            id: 0, host: "203.0.113.9", algorithm: "ssh-ed25519", base64: "AAAA", marker: nil)
        #expect(plain.asServerHost()?.address == "203.0.113.9")

        let hashed = KnownHost(
            id: 1, host: nil, algorithm: "ssh-ed25519", base64: "AAAA", marker: nil)
        #expect(hashed.asServerHost() == nil)

        let revoked = KnownHost(
            id: 2, host: "1.2.3.4", algorithm: "ssh-ed25519", base64: "AAAA", marker: "@revoked")
        #expect(revoked.asServerHost() == nil)
    }

    @Test("несколько ключей одного хоста дают один сервер")
    func knownHostDedup() {
        let text = """
            1.2.3.4 ssh-ed25519 AAAA
            1.2.3.4 ssh-rsa BBBB
            1.2.3.4 ecdsa-sha2-nistp256 CCCC
            |1|hashed=|hashed= ssh-ed25519 DDDD
            5.6.7.8 ssh-ed25519 EEEE
            """
        let servers = KnownHostsFile.servers(text)
        #expect(servers.map(\.address) == ["1.2.3.4", "5.6.7.8"])
    }

    @Test("нестандартный порт из [host]:port сохраняется")
    func knownHostPort() {
        let entry = KnownHost(
            id: 0, host: "[198.51.100.2]:2222", algorithm: "ssh-ed25519",
            base64: "AAAA", marker: nil)
        let host = entry.asServerHost()
        #expect(host?.name == "198.51.100.2")
        #expect(host?.port == 2222)
    }

    // MARK: - Дым на реальных файлах (скип, если их нет)

    @Test("реальный ~/.ssh читается без падений")
    func realKeys() {
        let dir = LocalKeys.directory()
        guard FileManager.default.fileExists(atPath: dir) else { return }
        _ = LocalKeys.scan()  // не должно бросать/падать
    }
}
