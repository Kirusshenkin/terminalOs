public import Foundation
import LocalAuthentication
import Security

public enum SecretError: Error, Equatable {
    case notFound
    case denied
    /// Набор отпечатков на этом Маке изменился с тех пор, как запись создали.
    ///
    /// Запись лежит под `biometryCurrentSet`, и это не сбой, а работающая
    /// защита: добавленный или удалённый палец делает прежние записи
    /// нечитаемыми навсегда — иначе чужой палец, добавленный в систему, открыл
    /// бы твои серверы. Отличать этот случай от «отказано» обязательно: причина
    /// разная, и делать человеку надо разное.
    case enrollmentChanged
    case keychain(OSStatus)
}


/// Somewhere small secrets live.
///
/// Deliberately narrow: passwords, passphrases, TOTP seeds and the profile's
/// master key. Anything larger belongs in the encrypted profile — the Keychain
/// is a key store, not a database.
public protocol SecretStore: Sendable {
    func read(_ account: String, reason: String) async throws -> Data
    func write(_ data: Data, account: String) async throws
    func delete(_ account: String) async throws
    func exists(_ account: String) async -> Bool
    /// Сменился ли набор отпечатков с тех пор, как запись создавали.
    ///
    /// Спрашивается до чтения, чтобы объяснить заранее, а не после отказа.
    func enrollmentChanged(_ account: String) async -> Bool
}

public extension SecretStore {
    /// Хранилищу без биометрии нечему меняться.
    func enrollmentChanged(_ account: String) async -> Bool { false }
}

/// Keychain-backed store where every item is gated by the system.
///
/// The important part is not the dialog but the access control: the item is
/// created so that macOS itself refuses to hand the bytes over without a fresh
/// check. Showing a prompt and then reading a plaintext file would be theatre.
///
/// Запасной путь для сборок без подписи разработчика: macOS заводит записи под
/// замком только приложению с entitlement связки ключей, остальным отвечает
/// `errSecMissingEntitlement`. Тогда запись ложится без системного замка, с
/// меткой, а подтверждение перед чтением спрашивает само приложение. Защита
/// слабее — байты стережёт процесс, а не macOS, — но без неё сборка без
/// подписи не сохраняет профиль вовсе. Подписанная сборка идёт основным путём.
public struct KeychainSecretStore: SecretStore {
    private let service: String
    /// Метка записи, подтверждение к которой спрашивает приложение.
    private static let appGatedMarker = Data("phosphor.app-gated".utf8)

    public init(service: String = "dev.phosphor.terminal") {
        self.service = service
    }

    /// `biometryCurrentSet` invalidates the item when the enrolled fingerprints
    /// change — which is the point, and also why re-enrolment has to be handled
    /// gracefully rather than surfacing as `errSecAuthFailed`.
    ///
    /// На машине без сенсора этот флаг не создаёт замок вовсе, и запись секрета
    /// падала бы с `errSecParam` — а значит, Mac mini без Touch ID не смог бы
    /// сохранить ни одного пароля. Там замок держит пароль пользователя:
    /// защита слабее биометрии, но это защита, а не её отсутствие.
    private func accessControl() throws -> SecAccessControl {
        let flags: SecAccessControlCreateFlags =
            Self.biometryState() == nil ? .userPresence : .biometryCurrentSet
        var error: Unmanaged<CFError>?
        guard
            let control = SecAccessControlCreateWithFlags(
                nil,
                kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
                flags,
                &error
            )
        else {
            throw SecretError.keychain(errSecParam)
        }
        return control
    }

    public func read(_ account: String, reason: String) async throws -> Data {
        if isAppGated(account) { try await confirmOwner(reason: reason) }
        let context = LAContext()
        context.localizedReason = reason
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecUseAuthenticationContext as String: context,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        switch status {
        case errSecSuccess:
            guard let data = item as? Data else { throw SecretError.notFound }
            return data
        case errSecItemNotFound:
            // Система убирает протухшую запись сама, поэтому «нет записи» и
            // «запись протухла» приходят одним и тем же кодом. Различает их
            // свидетель — он хранится отдельно и переживает протухание.
            throw hasNewEnrollment(account) ? SecretError.enrollmentChanged : SecretError.notFound
        case errSecUserCanceled:
            throw SecretError.denied
        case errSecAuthFailed, errSecInteractionNotAllowed:
            throw hasNewEnrollment(account) ? SecretError.enrollmentChanged : SecretError.denied
        default:
            throw SecretError.keychain(status)
        }
    }

    public func write(_ data: Data, account: String) throws {
        try? delete(account)
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrAccessControl as String: try accessControl(),
        ]
        var status = SecItemAdd(query as CFDictionary, nil)
        if status == errSecMissingEntitlement {
            // Сборка без entitlement: системный замок недоступен, ставим
            // метку, по которой чтение спросит подтверждение само.
            query[kSecAttrAccessControl as String] = nil
            query[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            query[kSecAttrGeneric as String] = Self.appGatedMarker
            status = SecItemAdd(query as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw SecretError.keychain(status) }
        rememberEnrollment(for: account)
    }

    /// Лежит ли запись без системного замка, под подтверждением приложения.
    ///
    /// Спрашиваются только атрибуты: у записи под системным замком они
    /// читаются без диалога, а сами байты не трогаются.
    private func isAppGated(_ account: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnAttributes as String: true,
            kSecUseAuthenticationUI as String: kSecUseAuthenticationUIFail,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
            let attributes = item as? [String: Any]
        else { return false }
        return attributes[kSecAttrGeneric as String] as? Data == Self.appGatedMarker
    }

    /// Подтверждение человека перед выдачей записи без системного замка.
    ///
    /// Та же политика, что у экрана входа: Touch ID, а без него часы или
    /// пароль учётной записи — запереть человека снаружи хуже, чем спросить
    /// пароль.
    private func confirmOwner(reason: String) async throws {
        let context = LAContext()
        do {
            try await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason)
        } catch let failure as LAError
            where [.userCancel, .appCancel, .systemCancel, .userFallback].contains(failure.code)
        {
            throw SecretError.denied
        }
    }

    public func delete(_ account: String) throws {
        // Свидетель уходит вместе с записью: он не секрет, но и переживать её
        // ему незачем — иначе следующая запись под тем же именем начнётся с
        // чужого воспоминания.
        try? deleteItem(account: Self.witnessAccount(account))
        try deleteItem(account: account)
    }

    private func deleteItem(account: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw SecretError.keychain(status)
        }
    }

    public func exists(_ account: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            // Ask only whether the item is there: no data, so no prompt.
            kSecUseAuthenticationUI as String: kSecUseAuthenticationUIFail,
        ]
        let status = SecItemCopyMatching(query as CFDictionary, nil)
        return status == errSecSuccess || status == errSecInteractionNotAllowed
    }

    // MARK: - Свидетель набора отпечатков

    /// Изменился ли набор отпечатков с тех пор, как запись создавали.
    ///
    /// Сравнивается слепок состояния биометрии — тот самый, по которому система
    /// и решает, протухла запись или нет. Сам слепок секретом не является:
    /// по нему нельзя ни узнать отпечаток, ни подделать его.
    public func enrollmentChanged(_ account: String) -> Bool {
        hasNewEnrollment(account)
    }

    private func hasNewEnrollment(_ account: String) -> Bool {
        guard let witness = readWitness(for: account), let now = Self.biometryState() else {
            // Не знаем, при каком наборе писали, или на этой машине биометрии
            // нет вовсе, — значит и утверждать нечего.
            return false
        }
        return witness != now
    }

    private static func witnessAccount(_ account: String) -> String {
        account + ".enrollment"
    }

    /// Слепок текущего набора отпечатков, если биометрия здесь вообще есть.
    static func biometryState() -> Data? {
        let context = LAContext()
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
        else { return nil }
        if #available(macOS 15, *) { return context.domainState.biometry.stateHash }
        return context.evaluatedPolicyDomainState
    }

    /// Кладёт слепок рядом с записью — без биометрического замка, иначе
    /// прочитать его в момент разбора беды было бы нельзя.
    private func rememberEnrollment(for account: String) {
        guard let state = Self.biometryState() else { return }
        let account = Self.witnessAccount(account)
        // `try?`: свидетель — вспомогательная запись. Не удалось положить —
        // теряем только точность объяснения, а не сам секрет.
        try? deleteItem(account: account)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: state,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
        ]
        _ = SecItemAdd(query as CFDictionary, nil)
    }

    private func readWitness(for account: String) -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: Self.witnessAccount(account),
            kSecReturnData as String: true,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess else { return nil }
        return item as? Data
    }
}

/// In-memory store for tests: same contract, no Keychain, no prompts.
public actor MemorySecretStore: SecretStore {
    private var items: [String: Data] = [:]

    public init() {}

    public func read(_ account: String, reason: String) async throws -> Data {
        guard let data = items[account] else { throw SecretError.notFound }
        return data
    }

    public func write(_ data: Data, account: String) throws {
        items[account] = data
    }

    public func delete(_ account: String) throws {
        items[account] = nil
    }

    public func exists(_ account: String) -> Bool {
        items[account] != nil
    }
}
