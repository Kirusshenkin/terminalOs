public import Foundation
public import KeysKit
public import PhosphorCore
public import SSHKit

/// Читает и правит `authorized_keys` на сервере.
///
/// Единственная операция во всём приложении, которая может отрезать тебя от
/// сервера навсегда, поэтому проверка на самоблокировку стоит **до** записи, а
/// не после, и запись атомарна с бэкапом рядом.
public actor KeyManager {
    public enum KeyError: Error, Equatable {
        /// После правки не осталось ни одного рабочего ключа, либо исчез тот,
        /// которым открыта текущая сессия.
        case wouldLockOut
        case readFailed(String)
        case writeFailed(String)
    }

    private let transport: any SSHTransport
    private let path: String

    public init(transport: any SSHTransport, path: String = "~/.ssh/authorized_keys") {
        self.transport = transport
        self.path = path
    }

    /// Ключи с сервера. Пустой файл — это не ошибка, а нормальное состояние.
    public func load() async throws -> [AuthorizedKey] {
        let command = "cat \(Shell.quote(path)) 2>/dev/null || true"
        do {
            let result = try await transport.run(command, timeout: .seconds(20))
            return AuthorizedKeysFile.parse(result.stdout)
        } catch {
            throw KeyError.readFailed("\(error)")
        }
    }

    /// Отпечаток ключа, которым открыта текущая сессия.
    ///
    /// Нужен, чтобы отличить «удаляю чужой ключ» от «отрезаю себя»: без этого
    /// защита от самоблокировки не работает.
    public func currentFingerprint() async -> String? {
        // `ssh -G` не годится: нужен ключ, который сервер реально принял.
        let command = "ssh-add -L 2>/dev/null | head -20 || true"
        guard let result = try? await transport.run(command, timeout: .seconds(10)),
            result.succeeded
        else { return nil }
        return AuthorizedKeysFile.parse(result.stdout).first?.fingerprint
    }

    /// Записывает новый набор ключей, если это не отрежет доступ.
    public func write(_ keys: [AuthorizedKey], currentFingerprint: String?) async throws {
        let removed = Set<Int>()
        guard
            !AuthorizedKeysFile.wouldLockOut(
                keys: keys, removing: removed, currentFingerprint: currentFingerprint
            )
        else {
            throw KeyError.wouldLockOut
        }
        let content = AuthorizedKeysFile.render(keys)
        let command = AuthorizedKeysFile.writeCommand(content: content, path: path)
        do {
            let result = try await transport.run(command, timeout: .seconds(30))
            guard result.succeeded else {
                throw KeyError.writeFailed(String(result.stderr.prefix(160)))
            }
        } catch let error as KeyError {
            throw error
        } catch {
            throw KeyError.writeFailed("\(error)")
        }
    }

    /// Удаляет ключи по идентификаторам, проверив последствия заранее.
    public func remove(
        ids: Set<Int>, from keys: [AuthorizedKey], currentFingerprint: String?
    ) async throws -> [AuthorizedKey] {
        guard
            !AuthorizedKeysFile.wouldLockOut(
                keys: keys, removing: ids, currentFingerprint: currentFingerprint
            )
        else {
            throw KeyError.wouldLockOut
        }
        let remaining = keys.filter { !ids.contains($0.id) }
        try await write(remaining, currentFingerprint: currentFingerprint)
        return remaining
    }

    /// Включает или выключает ключ, не удаляя его.
    ///
    /// Выключенный ключ остаётся в файле закомментированным: так его можно
    /// вернуть, не разыскивая заново.
    public func setEnabled(
        _ enabled: Bool, id: Int, in keys: [AuthorizedKey], currentFingerprint: String?
    ) async throws -> [AuthorizedKey] {
        var updated = keys
        guard let index = updated.firstIndex(where: { $0.id == id }) else { return keys }
        updated[index].isEnabled = enabled
        // Выключение ключа равносильно его удалению с точки зрения доступа.
        guard
            !AuthorizedKeysFile.wouldLockOut(
                keys: updated, removing: [], currentFingerprint: currentFingerprint
            )
        else {
            throw KeyError.wouldLockOut
        }
        try await write(updated, currentFingerprint: currentFingerprint)
        return updated
    }

    /// Добавляет ключ, если такого отпечатка ещё нет.
    public func add(
        line: String, to keys: [AuthorizedKey], currentFingerprint: String?
    ) async throws -> [AuthorizedKey] {
        guard let parsed = AuthorizedKeysFile.parse(line).first else {
            throw KeyError.writeFailed("строка не похожа на ключ")
        }
        guard !keys.contains(where: { $0.fingerprint == parsed.fingerprint }) else { return keys }
        var updated = keys
        updated.append(
            AuthorizedKey(
                id: (keys.map(\.id).max() ?? 0) + 1,
                options: parsed.options, algorithm: parsed.algorithm,
                base64: parsed.base64, comment: parsed.comment, isEnabled: true
            ))
        try await write(updated, currentFingerprint: currentFingerprint)
        return updated
    }
}
