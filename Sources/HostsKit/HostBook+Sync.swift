public import Foundation
public import SyncKit

/// The profile as sync records, and back.
///
/// Only what a person edits travels: groups, hosts, snippets, forwards and
/// key dates. What a machine observes for itself — when a host last answered,
/// what system it runs — stays local: it changes every minute, and syncing it
/// would let a background probe on one Mac overwrite an edit made on another.
extension HostBook {
    public func syncItems() -> [SyncItem] {
        let encoder = JSONEncoder()
        // Порядок ключей фиксирован: одинаковая запись должна давать одинаковые
        // байты, иначе каждая синхронизация видела бы правку там, где её нет.
        encoder.outputFormatting = .sortedKeys
        var items: [SyncItem] = []
        func add(_ kind: SyncRecord.Kind, _ id: String, _ value: some Encodable) {
            // Эти типы состоят из строк, чисел и дат: кодирование не падает.
            // Если однажды упадёт, запись просто не уедет в этот раз, а не
            // превратится в удаление: удаление — это отсутствие в базе, а не тут.
            guard let payload = try? encoder.encode(value) else { return }
            items.append(SyncItem(kind: kind, id: id, payload: payload))
        }
        for group in groups { add(.group, group.id.uuidString, group) }
        for host in hosts {
            var shared = host
            shared.osName = nil
            shared.lastSeen = nil
            add(.host, host.id.uuidString, shared)
        }
        for snippet in snippets { add(.snippet, snippet.id.uuidString, snippet) }
        for forward in forwards { add(.forward, forward.id.uuidString, forward) }
        for key in addedKeys { add(.addedKey, Self.addedKeyID(key), key) }
        return items
    }

    /// Replaces the synced parts of the book with merged records.
    ///
    /// Local order is kept; new items go to the end. A record this version
    /// cannot read (written by a newer app) leaves the local copy alone.
    public mutating func applySync(_ records: [SyncRecord]) {
        var byKind: [SyncRecord.Kind: [SyncRecord]] = [:]
        for record in records { byKind[record.kind, default: []].append(record) }
        groups = Self.merge(groups, byKind[.group] ?? [], id: { $0.id.uuidString })
        let seen = Dictionary(hosts.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        hosts = Self.merge(hosts, byKind[.host] ?? [], id: { $0.id.uuidString }).map { host in
            var host = host
            host.osName = seen[host.id]?.osName
            host.lastSeen = seen[host.id]?.lastSeen
            return host
        }
        snippets = Self.merge(snippets, byKind[.snippet] ?? [], id: { $0.id.uuidString })
        forwards = Self.merge(forwards, byKind[.forward] ?? [], id: { $0.id.uuidString })
        addedKeys = Self.merge(addedKeys, byKind[.addedKey] ?? [], id: Self.addedKeyID)
    }

    static func addedKeyID(_ key: AddedKey) -> String { "\(key.hostID.uuidString) \(key.fingerprint)" }

    private static func merge<T: Codable>(_ local: [T], _ records: [SyncRecord], id: (T) -> String) -> [T] {
        let decoder = JSONDecoder()
        let byID = Dictionary(records.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var result: [T] = []
        var placed = Set<String>()
        func resolve(_ record: SyncRecord, fallback: T?) -> T? {
            guard let payload = record.payload else { return nil }
            // Запись новее, чем умеет эта версия, — не повод терять свою копию.
            return (try? decoder.decode(T.self, from: payload)) ?? fallback
        }
        for item in local {
            let key = id(item)
            guard placed.insert(key).inserted else { continue }
            // Записи нет вовсе — её не было и в хранилище, и локально она
            // только что штамповалась: оставляем как есть.
            guard let record = byID[key] else {
                result.append(item)
                continue
            }
            if let value = resolve(record, fallback: item) { result.append(value) }
        }
        for record in records.sorted(by: { $0.stamp < $1.stamp }) where !placed.contains(record.id) {
            placed.insert(record.id)
            if let value = resolve(record, fallback: nil) { result.append(value) }
        }
        return result
    }
}
