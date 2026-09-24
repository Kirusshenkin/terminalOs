import Foundation
import Testing

@testable import HostsKit
@testable import KeysKit
@testable import SessionKit

@Suite("known_hosts")
struct KnownHostsTests {
    private let sample = """
        # комментарий
        example.com ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIH1vN3Kk8lQ2mZ0pW7xR4tYs6uVbNcXdEfGh
        10.0.0.1,10.0.0.2 ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQC
        |1|abc=|def= ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIKlMnOpQrStUvWxYz012345
        @revoked bad.example ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIP0oQrStUvWxYz012
        """

    @Test("разбираем имена, тип и пометки")
    func parses() {
        let hosts = KnownHostsFile.parse(sample)
        #expect(hosts.count == 4)
        #expect(hosts[0].host == "example.com")
        #expect(hosts[1].host == "10.0.0.1,10.0.0.2")
        #expect(hosts[3].marker == "@revoked")
    }

    @Test("хешированная запись честно объявляется скрытой")
    func hashedIsHonest() throws {
        let hashed = try #require(KnownHostsFile.parse(sample).first { $0.isHashed })
        #expect(hashed.host == nil)
        // Имя из хеша не восстанавливается, и делать вид, что мы его знаем, — врать.
        #expect(hashed.host == nil)
    }

    @Test("отпечаток считается локально в формате OpenSSH")
    func fingerprint() {
        let entry = KnownHostsFile.parse(sample)[0]
        #expect(entry.fingerprint.hasPrefix("SHA256:"))
        #expect(!entry.fingerprint.contains("="))
    }

    @Test("забытая запись исчезает, остальные и комментарии остаются")
    func removalKeepsRest() {
        let hosts = KnownHostsFile.parse(sample)
        let remaining = hosts.filter { $0.host != "example.com" }
        let rendered = KnownHostsFile.render(remaining, from: sample)
        #expect(!rendered.contains("example.com ssh-ed25519"))
        #expect(rendered.contains("# комментарий"))
        #expect(rendered.contains("10.0.0.1"))
        #expect(KnownHostsFile.parse(rendered).count == 3)
    }
}

@Suite("Проброс портов")
struct PortForwardTests {
    private let hostID = UUID()

    @Test("локальный слушает только на 127.0.0.1")
    func localBindsLoopback() {
        let forward = PortForward(
            direction: .local, listenPort: 5432, targetHost: "127.0.0.1",
            targetPort: 5432, hostID: hostID)
        // Пробросить порт и случайно открыть его всей сети — обидная ошибка.
        #expect(forward.specification == "127.0.0.1:5432:127.0.0.1:5432")
        #expect(forward.direction.flag == "-L")
    }

    @Test("удалённый описывается без привязки к loopback")
    func remoteSpec() {
        let forward = PortForward(
            direction: .remote, listenPort: 8080, targetHost: "localhost",
            targetPort: 3000, hostID: hostID)
        #expect(forward.specification == "8080:localhost:3000")
        #expect(forward.direction.flag == "-R")
    }

    @Test("ошибки ssh переводятся в подсказку")
    func explainsFailures() {
        let forward = PortForward(listenPort: 80, targetPort: 80, hostID: hostID)
        #expect(
            ForwardManager.explain("bind: Address already in use", forward: forward)
                .contains("уже занят"))
        #expect(
            ForwardManager.explain("Control socket connect: No such file", forward: forward)
                .contains("подключись"))
        #expect(
            ForwardManager.explain("Permission denied", forward: forward)
                .contains("1024"))
    }
}

@Suite("Память о сервере после подключения")
struct HostMemoryTests {
    private func book() -> HostBook {
        HostBook(hosts: [ServerHost(name: "prod-01", address: "10.0.0.1")])
    }

    @Test("проба заполняет систему и время, которых иначе не было бы")
    func fillsFromProbe() {
        var book = book()
        let id = book.hosts[0].id
        #expect(book.hosts[0].osName == nil)
        #expect(book.hosts[0].lastSeen == nil)

        let moment = Date(timeIntervalSince1970: 1_700_000_000)
        let filled = book.remember(id, osName: "ubuntu", at: moment)
        #expect(filled)
        #expect(book.hosts[0].osName == "ubuntu")
        #expect(book.hosts[0].lastSeen == moment)
        // Значок на карточке перестаёт быть заглушкой ровно здесь.
        #expect(book.hosts[0].osBadge == "UBU")
    }

    @Test("повтор в ту же минуту не считается изменением")
    func doesNotRewriteOnEverySnapshot() {
        var book = book()
        let id = book.hosts[0].id
        let moment = Date(timeIntervalSince1970: 1_700_000_000)
        let first = book.remember(id, osName: "debian", at: moment)
        let again = book.remember(id, osName: "debian", at: moment.addingTimeInterval(5))
        let later = book.remember(id, osName: "debian", at: moment.addingTimeInterval(120))
        #expect(first)
        #expect(!again)
        #expect(later)
    }

    @Test("проба, ничего не узнавшая, не затирает то, что знали")
    func keepsKnownNameWhenProbeIsBlank() {
        var book = book()
        let id = book.hosts[0].id
        book.remember(id, osName: "alpine", at: Date(timeIntervalSince1970: 1))
        // `unknown` — это ответ пробы «не разобрал /etc/os-release», а не имя.
        book.remember(id, osName: "unknown", at: Date(timeIntervalSince1970: 1_000))
        book.remember(id, osName: nil, at: Date(timeIntervalSince1970: 2_000))
        #expect(book.hosts[0].osName == "alpine")
    }

    @Test("чужой идентификатор ничего не меняет")
    func unknownHostIsIgnored() {
        var book = book()
        let changed = book.remember(UUID(), osName: "ubuntu")
        #expect(!changed)
        #expect(book.hosts[0].osName == nil)
    }
}
