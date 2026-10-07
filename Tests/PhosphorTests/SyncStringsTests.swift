import Testing

@testable import PhosphorUI
@testable import SyncKit

@Suite("Синхронизация: подписи")
struct SyncStringsTests {
    @Test("каждая ошибка синхронизации переведена на оба языка", arguments: Language.allCases)
    func errorsTranslated(language: Language) {
        let strings = Strings(language: language)
        let errors: [SyncError] = [
            .unknownSigner("m"), .badSignature, .rollback(seen: 3, got: 2), .notForThisMachine,
            .unreadable("host/x"), .malformed("snapshot"), .keys, .busy, .storage("No space left"),
        ]
        for text in errors.map(strings.syncError) {
            #expect(!text.hasPrefix("sync."))
            #expect(!text.contains("%@"))
        }
        #expect(strings.syncError(SyncError.rollback(seen: 3, got: 2)).contains("2"))
    }

    @Test("ключи интерфейса синхронизации есть в таблице на обоих языках")
    func tableComplete() {
        for (key, values) in Strings.syncTable {
            #expect(values.count == 2, "\(key)")
        }
    }
}
