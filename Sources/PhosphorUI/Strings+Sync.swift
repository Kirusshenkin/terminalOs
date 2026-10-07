public import SyncKit

extension Strings {
    /// Ошибка синхронизации словами человека. Сетевые — общими словами
    /// транспорта: «прокси лежит» и «отказ в доступе» звучат одинаково везде.
    public func syncError(_ error: any Error) -> String {
        guard let failure = error as? SyncError else { return describe(error) }
        return switch failure {
        case .unknownSigner(let machine): format("sync.err.unknownSigner", machine)
        case .badSignature: self("sync.err.badSignature")
        case .rollback(let seen, let got): ordered("sync.err.rollback", ["\(got)", "\(seen)"])
        case .notForThisMachine: self("sync.err.notForThisMachine")
        case .unreadable(let what): format("sync.err.unreadable", what)
        case .malformed(let what): format("sync.err.malformed", what)
        case .keys: self("sync.err.keys")
        case .busy: self("sync.err.busy")
        case .storage(let text): format("sync.err.storage", text.isEmpty ? "—" : String(text.prefix(200)))
        }
    }
}

extension Strings {
    /// Несколько `%@` подряд, по порядку.
    func ordered(_ key: String, _ values: [String]) -> String {
        var text = self(key)
        for value in values {
            guard let range = text.range(of: "%@") else { break }
            text.replaceSubrange(range, with: value)
        }
        return text
    }
}
