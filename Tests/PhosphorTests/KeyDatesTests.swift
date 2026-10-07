import Foundation
import Testing

@testable import HostsKit
@testable import KeysKit
@testable import PhosphorCore
@testable import PhosphorUI
@testable import ProvisionKit
@testable import SSHKit

@Suite("Даты ключей")
struct KeyDatesTests {
    @Test("профиль, записанный до журнала ключей, читается с пустым журналом")
    func oldBookDecodes() throws {
        let old = #"{"groups":[],"hosts":[],"snippets":[],"forwards":[]}"#
        let book = try JSONDecoder().decode(HostBook.self, from: Data(old.utf8))
        #expect(book.addedKeys.isEmpty)
    }

    @Test("журнал переживает запись и чтение профиля")
    func roundTrip() throws {
        var book = HostBook()
        let host = UUID()
        let date = Date(timeIntervalSince1970: 1_790_000_000)
        book.recordKeyAdded(fingerprint: "SHA256:abc", host: host, at: date)
        let decoded = try JSONDecoder().decode(HostBook.self, from: JSONEncoder().encode(book))
        #expect(decoded.keyAddedDate(fingerprint: "SHA256:abc", host: host) == date)
    }

    @Test("дата привязана к хосту: тот же ключ на другом сервере — без даты")
    func perHost() {
        var book = HostBook()
        let host = UUID()
        book.recordKeyAdded(fingerprint: "SHA256:abc", host: host)
        #expect(book.keyAddedDate(fingerprint: "SHA256:abc", host: UUID()) == nil)
    }

    @Test("удалённый ключ забывает дату, повторное добавление — новая дата")
    func forgetAndReAdd() {
        var book = HostBook()
        let host = UUID()
        book.recordKeyAdded(fingerprint: "SHA256:abc", host: host, at: Date(timeIntervalSince1970: 1))
        book.forgetKey(fingerprint: "SHA256:abc", host: host)
        #expect(book.keyAddedDate(fingerprint: "SHA256:abc", host: host) == nil)
        book.recordKeyAdded(fingerprint: "SHA256:abc", host: host, at: Date(timeIntervalSince1970: 2))
        book.recordKeyAdded(fingerprint: "SHA256:abc", host: host, at: Date(timeIntervalSince1970: 3))
        #expect(book.addedKeys.count == 1, "одна запись на ключ и хост")
        #expect(book.keyAddedDate(fingerprint: "SHA256:abc", host: host) == Date(timeIntervalSince1970: 3))
    }

    @Test("журнал ограничен сверху и вытесняет старое")
    func bounded() {
        var book = HostBook()
        let host = UUID()
        for index in 0..<(HostBook.addedKeysLimit + 10) {
            book.recordKeyAdded(fingerprint: "SHA256:\(index)", host: host)
        }
        #expect(book.addedKeys.count == HostBook.addedKeysLimit)
        #expect(book.keyAddedDate(fingerprint: "SHA256:0", host: host) == nil)
        #expect(book.keyAddedDate(fingerprint: "SHA256:\(HostBook.addedKeysLimit + 9)", host: host) != nil)
    }

    @Test("локальный ключ несёт дату создания файла")
    func localKeyDate() throws {
        let line = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIH1vN3Kk8lQ2mZ0pW7xR4tYs6uVbNcXdEfGh you@mac"
        let date = Date(timeIntervalSince1970: 1_790_000_000)
        let key = try #require(
            LocalKeys.parse(privatePath: "/tmp/id_test", publicText: line, hasPrivate: true, created: date))
        #expect(key.created == date)
    }
}

@Suite("Установка tmux")
struct TmuxInstallTests {
    private func profile(root: Bool, sudo: Bool, manager: String?) -> HostProfile {
        HostProfile(
            osName: "ubuntu", osVersion: "24.04", uptimeSeconds: 600,
            isRoot: root, canSudo: sudo, dockerPath: nil, dockerNeedsSudo: false,
            isPodman: false, hasNginx: false, hasCertbot: false, hasUFW: false,
            containerCount: 0, authorizedKeyCount: 1, packageManager: manager)
    }

    @Test("сами запускаем с sudo -n: пароль спросить некому")
    func nonInteractiveSudo() {
        let command = profile(root: false, sudo: true, manager: "apt").installCommand(
            for: "tmux", interactive: false)
        #expect(
            command?.contains("sudo -n env DEBIAN_FRONTEND=noninteractive apt-get install -y -qq tmux")
                == true)
        #expect(command?.hasPrefix("sudo -n apt-get update") == true, "свежий сервер ещё без списков пакетов")
    }

    @Test("у root sudo не нужен вовсе")
    func rootNoSudo() {
        let command = profile(root: true, sudo: false, manager: "dnf").installCommand(
            for: "tmux", interactive: false)
        #expect(command == "dnf install -y tmux")
    }

    @Test("в итог отказа идут последние строки вывода")
    func reasonTail() {
        let result = CommandResult(
            status: 100, stdout: "", stderr: "a\nb\nc\nE: Unable to locate package tmux")
        #expect(AppModel.reason(result) == "b\nc\nE: Unable to locate package tmux")
    }
}
