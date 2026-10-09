public import Foundation

/// Reads Termius's *saved hosts* — the real list, decrypted.
///
/// В отличие от `TermiusHistory`, которая берёт только открытые адреса из
/// журнала подключений, здесь читается само хранилище: LevelDB → записи V8 →
/// расшифровка полей секретбоксом на ключе `localKey` из связки ключей. Хост
/// собирается со связями: его адрес и имя лежат в `content`, порт — в
/// привязанном `ssh_config`, логин — в его `ssh_identity`.
///
/// Ключ `localKey` принадлежит Termius, и macOS отдаёт его чужому процессу
/// только после того, как спросит пароль учётной записи, — поэтому ключ сюда
/// передаётся снаружи (его читает слой приложения), а сам разбор остаётся
/// детерминированным: те же файлы и тот же ключ дают тот же результат.
///
/// Only reading: Phosphor never writes Termius's store.
public enum TermiusVault {
    /// Where Termius keeps its IndexedDB, sandboxed and not.
    public static func defaultDirectories() -> [String] { TermiusHistory.defaultDirectories() }

    /// How many hosts the store holds, *without* decrypting anything.
    ///
    /// Нужно для бейджа «импортировать N» на первом экране: он считается до
    /// нажатия и не должен спрашивать пароль от связки ключей. Поэтому читается
    /// только структура — сколько записей в хранилище хостов, — а расшифровка
    /// (и запрос ключа) откладывается до самого импорта.
    public static func availableHostCount(directories: [String] = defaultDirectories()) -> Int {
        guard let directory = directories.first(where: { FileManager.default.fileExists(atPath: $0) })
        else { return 0 }
        return records(in: LevelDB.read(directory: directory), database: Store.hosts).count
    }

    /// Builds hosts from the store, skipping any already present.
    ///
    /// `defaultUser` подставляется, когда у хоста нет привязанной identity с
    /// логином: у Termius так бывает, и выдумать логин неоткуда — пусть человек
    /// поправит его в карточке, как и в импорте из истории.
    public static func hosts(
        directories: [String] = defaultDirectories(),
        localKey: Data,
        existing: [ServerHost],
        defaultUser: String = NSUserName()
    ) -> [ServerHost] {
        let decrypted = load(directories: directories, localKey: localKey, defaultUser: defaultUser)
        let taken = Set(existing.map { "\($0.user)@\($0.address):\($0.port)" })
        return decrypted.filter { !taken.contains("\($0.user)@\($0.address):\($0.port)") }
    }

    /// All decryptable hosts from the store, linked to their port and login.
    static func load(directories: [String], localKey: Data, defaultUser: String) -> [ServerHost] {
        guard localKey.count == SecretBox.keySize else { return [] }
        let directory = directories.first { FileManager.default.fileExists(atPath: $0) }
        guard let directory else { return [] }
        let store = LevelDB.read(directory: directory)

        let hostRecords = records(in: store, database: Store.hosts)
        let configsByID = index(records(in: store, database: Store.sshConfigs))
        let identitiesByID = index(records(in: store, database: Store.sshIdentities))

        var hosts: [ServerHost] = []
        for record in hostRecords {
            guard let content = decryptContent(record["content"], key: localKey),
                let address = content["address"] as? String, !address.isEmpty
            else { continue }

            let label = (content["label"] as? String).flatMap { $0.isEmpty ? nil : $0 }
            let osName = (content["os_name"] as? String).flatMap { $0.isEmpty ? nil : $0 }

            let config = reference(record["ssh_config"]).flatMap { configsByID[$0] }
            let port = config.flatMap { portFrom(decryptContent($0["content"], key: localKey)) } ?? 22
            let identity = config.flatMap { reference($0["identity"]) }.flatMap { identitiesByID[$0] }
            let user =
                identity.flatMap { userFrom(decryptContent($0["content"], key: localKey)) }
                ?? defaultUser

            hosts.append(
                ServerHost(
                    name: label ?? address,
                    address: address,
                    port: port,
                    user: user,
                    tags: ["termius"],
                    osName: osName
                ))
        }
        return hosts.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    // MARK: - Stores

    /// Per-entity IndexedDB database ids inside Termius's LevelDB. Stable across
    /// installs — they are assigned in the order Termius creates the stores.
    private enum Store {
        static let hosts: UInt8 = 16
        static let sshConfigs: UInt8 = 4
        static let sshIdentities: UInt8 = 12
    }

    /// Decoded V8 objects for one object store.
    ///
    /// Ключ записи в LevelDB у Chromium — `00 <db> 01 01 <первичный ключ>`:
    /// база на сущность, объектное хранилище 1, индекс 1. Фильтруем по этой
    /// форме и декодируем значение из V8.
    private static func records(in store: [Data: Data], database: UInt8) -> [[String: V8Value]] {
        var result: [[String: V8Value]] = []
        for (key, value) in store {
            let bytes = [UInt8](key)
            guard bytes.count >= 4, bytes[0] == 0, bytes[1] == database,
                bytes[2] == 1, bytes[3] == 1
            else { continue }
            if let object = V8Decoder.decodeObject(value) { result.append(object) }
        }
        return result
    }

    /// Indexes records by their global `id`, which is what cross-store
    /// references point at.
    private static func index(_ records: [[String: V8Value]]) -> [Int64: [String: V8Value]] {
        var byID: [Int64: [String: V8Value]] = [:]
        for record in records {
            if let id = record["id"]?.intValue { byID[id] = record }
        }
        return byID
    }

    /// The `id` a reference field (`{id, local_id}`) points at.
    private static func reference(_ value: V8Value?) -> Int64? {
        value?.objectValue?["id"]?.intValue
    }

    // MARK: - Field decryption

    /// Opens a `BA…` field: base64 of `04 01` + 24-byte nonce + secretbox, then
    /// parses the plaintext as a JSON object. Nil for an empty or unreadable
    /// field — the caller skips it.
    private static func decryptContent(_ value: V8Value?, key: Data) -> [String: Any]? {
        guard let text = value?.stringValue, let plain = open(text, key: key) else { return nil }
        return try? JSONSerialization.jsonObject(with: plain) as? [String: Any]
    }

    private static func open(_ base64: String, key: Data) -> Data? {
        guard let raw = Data(base64Encoded: base64),
            raw.count >= 2 + SecretBox.nonceSize + SecretBox.tagSize, raw[raw.startIndex] == 4
        else { return nil }
        let nonce = raw.subdata(in: (raw.startIndex + 2)..<(raw.startIndex + 2 + SecretBox.nonceSize))
        let box = raw.subdata(in: (raw.startIndex + 2 + SecretBox.nonceSize)..<raw.endIndex)
        return SecretBox.open(box, nonce: nonce, key: key)
    }

    /// Port out of a decrypted ssh_config, stored by Termius as a number or a
    /// string.
    private static func portFrom(_ content: [String: Any]?) -> Int? {
        guard let content else { return nil }
        if let number = content["port"] as? Int { return number }
        if let text = content["port"] as? String, let number = Int(text) { return number }
        return nil
    }

    /// Login out of a decrypted ssh_identity.
    private static func userFrom(_ content: [String: Any]?) -> String? {
        guard let user = content?["username"] as? String, !user.isEmpty else { return nil }
        return user
    }
}
