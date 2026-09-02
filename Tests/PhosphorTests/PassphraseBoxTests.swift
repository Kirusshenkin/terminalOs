import Foundation
import Testing

@testable import AuthKit

@Suite("Экспорт под парольной фразой")
struct PassphraseBoxTests {
    @Test("что зашифровали той же фразой — то и расшифровали")
    func roundTrip() throws {
        let plain = Data("хосты, ключи, аудит".utf8)
        let sealed = try PassphraseBox.seal(plain, passphrase: "correct horse battery staple")
        let opened = try PassphraseBox.open(sealed, passphrase: "correct horse battery staple")
        #expect(opened == plain)
    }

    @Test("неверная фраза — отказ, а не мусор")
    func wrongPassphrase() throws {
        let sealed = try PassphraseBox.seal(Data("секрет".utf8), passphrase: "right")
        #expect(throws: (any Error).self) {
            try PassphraseBox.open(sealed, passphrase: "wrong")
        }
    }

    @Test("подмена шифротекста ловится AEAD")
    func tamper() throws {
        var sealed = try PassphraseBox.seal(Data("данные".utf8), passphrase: "pw")
        sealed[sealed.count - 1] ^= 0xff
        #expect(throws: (any Error).self) {
            try PassphraseBox.open(sealed, passphrase: "pw")
        }
    }

    @Test("два экспорта одной фразой различаются: соль случайная")
    func randomSalt() throws {
        let a = try PassphraseBox.seal(Data("x".utf8), passphrase: "pw")
        let b = try PassphraseBox.seal(Data("x".utf8), passphrase: "pw")
        #expect(a != b)
    }

    @Test("не наш файл отвергается по магии, а не падает")
    func notAnExport() {
        #expect(throws: PassphraseBox.BoxError.notAnExport) {
            try PassphraseBox.open(Data("это не экспорт вовсе".utf8), passphrase: "pw")
        }
    }

    @Test("заголовок несёт версию, число итераций и соль")
    func header() throws {
        let sealed = try PassphraseBox.seal(Data("d".utf8), passphrase: "pw")
        #expect(Array(sealed.prefix(4)) == PassphraseBox.magic)
        // версия(2) + итерации(4) + соль(16) + бокс не короче тега.
        #expect(sealed.count > 4 + 2 + 4 + 16)
    }
}
