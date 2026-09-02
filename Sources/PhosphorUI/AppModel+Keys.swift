public import DockerKit
public import HostsKit
public import KeysKit
public import PhosphorCore
public import ProvisionKit
public import SSHKit
public import SessionKit

/// Работа с `authorized_keys` на сервере.
@MainActor
extension AppModel {
    /// Читает ключи с сервера и запоминает, каким подключён ты сам.
    public func loadKeys() async {
        guard let host = book.hosts.first(where: { $0.id == selectedHost }) else { return }
        let manager = KeyManager(
            transport: SystemSSHTransport(host: host, reach: book.reach(for: host)))
        keysError = nil
        do {
            serverKeys = try await manager.load()
            myFingerprint = await manager.currentFingerprint()
        } catch {
            keysError = "\(strings("keys.readFailed")) \(error)"
        }
    }

    /// Читает ключи из ~/.ssh. Только публичная часть; приватная не трогается.
    public func loadLocalKeys() {
        localKeys = LocalKeys.scan()
    }

    /// Дописывает ключ в `authorized_keys` на сервере.
    public func addKeyToServer() async {
        guard let host = book.hosts.first(where: { $0.id == selectedHost }) else {
            keysError = strings("keys.noHost")
            return
        }
        let manager = KeyManager(
            transport: SystemSSHTransport(host: host, reach: book.reach(for: host)))
        do {
            serverKeys = try await manager.add(
                line: newKeyLine, to: serverKeys, currentFingerprint: myFingerprint)
            newKeyLine = ""
            isAddingKey = false
            keysError = nil
        } catch {
            keysError = "\(strings("keys.addFailed")) \(error)"
        }
    }

    /// Просит подтверждение, если удаляется ключ, которым ты подключён.
    public func requestKeyRemoval(_ key: AuthorizedKey) {
        if key.fingerprint == myFingerprint {
            pendingKeyRemoval = key
        } else {
            Task { await removeKey(key) }
        }
    }

    public func confirmKeyRemoval(_ key: AuthorizedKey) {
        pendingKeyRemoval = nil
        Task { await removeKey(key, force: true) }
    }

    private func removeKey(_ key: AuthorizedKey, force: Bool = false) async {
        guard let host = book.hosts.first(where: { $0.id == selectedHost }) else { return }
        let manager = KeyManager(
            transport: SystemSSHTransport(host: host, reach: book.reach(for: host)))
        do {
            // При явном согласии перестаём считать этот ключ своим — проверка
            // должна пропустить осознанное решение, но не случайное.
            serverKeys = try await manager.remove(
                ids: [key.id], from: serverKeys,
                currentFingerprint: force ? nil : myFingerprint
            )
            keysError = nil
        } catch KeyManager.KeyError.wouldLockOut {
            keysError = strings("keys.lastKey")
        } catch {
            keysError = "\(error)"
        }
    }

}
