import Foundation
import Testing

@testable import AuthKit
@testable import PhosphorUI

/// Хранилище, которое умеет изображать смену набора отпечатков.
///
/// Настоящая связка ключей в этот момент ведёт себя двояко: запись то
/// исчезает, то остаётся и отказывает при чтении. Проверяем оба поворота —
/// объяснение человеку должно быть одинаковым.
private actor StaleStore: SecretStore {
    enum Behaviour: Sendable {
        /// Всё как обычно.
        case normal
        /// Набор сменился, система убрала запись.
        case enrollmentMovedItemGone
        /// Набор сменился, запись на месте, но не отдаётся.
        case enrollmentMovedItemRefuses
        /// Человек нажал «Отмена».
        case cancelled
    }

    private var items: [String: Data] = [:]
    private var behaviour: Behaviour

    init(behaviour: Behaviour = .normal) {
        self.behaviour = behaviour
    }

    func become(_ behaviour: Behaviour) {
        self.behaviour = behaviour
    }

    func read(_ account: String, reason: String) async throws -> Data {
        switch behaviour {
        case .enrollmentMovedItemGone: throw SecretError.enrollmentChanged
        case .enrollmentMovedItemRefuses: throw SecretError.enrollmentChanged
        case .cancelled: throw SecretError.denied
        case .normal:
            guard let data = items[account] else { throw SecretError.notFound }
            return data
        }
    }

    func write(_ data: Data, account: String) throws {
        items[account] = data
    }

    func delete(_ account: String) throws {
        items[account] = nil
    }

    func exists(_ account: String) -> Bool {
        switch behaviour {
        case .enrollmentMovedItemGone: false
        case .enrollmentMovedItemRefuses, .cancelled, .normal: items[account] != nil
        }
    }

    func enrollmentChanged(_ account: String) -> Bool {
        switch behaviour {
        case .enrollmentMovedItemGone, .enrollmentMovedItemRefuses: true
        case .normal, .cancelled: false
        }
    }
}

private struct Sample: Codable, Equatable {
    var hosts: [String]
}

@Suite("Смена набора отпечатков")
struct EnrollmentTests {
    private func temporaryURL() -> URL {
        URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("phosphor-\(UUID().uuidString)/profile.phosphor")
    }

    @Test("исчезнувший ключ после смены набора объясняется, а не зовётся утерянным")
    func vanishedKeyIsExplained() async throws {
        let url = temporaryURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let secrets = StaleStore()
        let store = ProfileStore(store: secrets, url: url)
        try await store.save(Sample(hosts: ["prod-01"]), reason: "тест")

        await secrets.become(.enrollmentMovedItemGone)
        let fresh = ProfileStore(store: secrets, url: url)
        await #expect(throws: ProfileStoreError.enrollmentChanged) {
            _ = try await fresh.load(Sample.self, reason: "тест")
        }
    }

    @Test("отказавшая запись после смены набора объясняется тем же")
    func refusingKeyIsExplained() async throws {
        let url = temporaryURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let secrets = StaleStore()
        let store = ProfileStore(store: secrets, url: url)
        try await store.save(Sample(hosts: ["prod-01"]), reason: "тест")

        await secrets.become(.enrollmentMovedItemRefuses)
        let fresh = ProfileStore(store: secrets, url: url)
        await #expect(throws: SecretError.enrollmentChanged) {
            _ = try await fresh.load(Sample.self, reason: "тест")
        }
    }

    @Test("просто удалённый ключ по-прежнему зовётся утерянным")
    func deletedKeyStaysLost() async throws {
        let url = temporaryURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let secrets = StaleStore()
        let store = ProfileStore(store: secrets, url: url)
        try await store.save(Sample(hosts: ["prod-01"]), reason: "тест")
        try await secrets.delete(ProfileStore.masterKeyAccount)

        let fresh = ProfileStore(store: secrets, url: url)
        await #expect(throws: ProfileStoreError.keyLost) {
            _ = try await fresh.load(Sample.self, reason: "тест")
        }
    }

    @Test("после смены набора экспорт всё-таки ставится обратно")
    func importSurvivesEnrollmentChange() async throws {
        let source = temporaryURL()
        let target = temporaryURL()
        defer {
            try? FileManager.default.removeItem(at: source.deletingLastPathComponent())
            try? FileManager.default.removeItem(at: target.deletingLastPathComponent())
        }
        let value = Sample(hosts: ["prod-01", "prod-02"])
        let origin = ProfileStore(store: StaleStore(), url: source)
        try await origin.save(value, reason: "тест")
        let bundle = try await origin.export(passphrase: "длинная фраза", reason: "тест")

        // На этой машине профиль уже лежит, а ключ к нему протух вместе с
        // набором отпечатков: ровно тот случай, ради которого экспорт и делают.
        let secrets = StaleStore()
        let victim = ProfileStore(store: secrets, url: target)
        try await victim.save(Sample(hosts: ["старое"]), reason: "тест")
        await secrets.become(.enrollmentMovedItemGone)

        let recovered = ProfileStore(store: secrets, url: target)
        _ = try await recovered.importProfile(bundle, as: Sample.self, passphrase: "длинная фраза", reason: "тест")
        await secrets.become(.normal)
        #expect(try await recovered.load(Sample.self, reason: "тест") == value)
    }

    @Test("нажатая «Отмена» не заводит новый ключ поверх профиля")
    func cancelDoesNotMintAKey() async throws {
        let url = temporaryURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let secrets = StaleStore()
        let store = ProfileStore(store: secrets, url: url)
        try await store.save(Sample(hosts: ["prod-01"]), reason: "тест")
        let bundle = try await store.export(passphrase: "фраза", reason: "тест")

        await secrets.become(.cancelled)
        let fresh = ProfileStore(store: secrets, url: url)
        await #expect(throws: SecretError.denied) {
            _ = try await fresh.importProfile(bundle, as: Sample.self, passphrase: "фраза", reason: "тест")
        }

        // Отказ ничего не испортил: профиль открывается, как открывался.
        await secrets.become(.normal)
        #expect(
            try await ProfileStore(store: secrets, url: url)
                .load(Sample.self, reason: "тест") == Sample(hosts: ["prod-01"]))
    }

    @Test("объяснение говорит, что случилось и что делать")
    func explanationIsUseful() {
        let strings = Strings(language: .russian)
        let text = strings.describe(SecretError.enrollmentChanged)
        #expect(text.contains("Touch ID"))
        #expect(text.contains("экспорт"))
        #expect(strings.describe(ProfileStoreError.enrollmentChanged) == text)
    }
}
