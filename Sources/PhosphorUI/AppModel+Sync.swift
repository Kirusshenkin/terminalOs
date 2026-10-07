public import Foundation
public import HostsKit
import SSHKit
public import SyncKit

/// Где сейчас синхронизация — одной строкой для страницы профиля.
public enum SyncPhase: Equatable, Sendable {
    case off
    case working
    /// Эта машина оставила просьбу и ждёт, пока её пустят с другой.
    case waiting(code: String)
    /// Машину пустили; перед первой записью человек сверяет код той, что пустила.
    case confirm(signer: SyncMachine)
    case synced(Date)
    case failed(String)
}

/// Синхронизация профиля между своими машинами через папку на своём сервере (#18).
@MainActor
extension AppModel {
    /// Через сколько после правки уходит синхронизация: правки подряд — одна поездка.
    static let syncDelay: Duration = .seconds(3)
    /// Как давно должна быть прошлая синхронизация, чтобы возврат в окно её запустил.
    static let syncStaleAfter: TimeInterval = 5 * 60

    public var syncState: SyncState? { book.sync }

    /// Хранилища по порядку; хост, которого больше нет в списке, — nil.
    public var syncStorages: [(id: ServerHost.ID, host: ServerHost?)] {
        (book.sync?.storages ?? []).map { id in (id, book.hosts.first { $0.id == id }) }
    }

    /// Ещё один сервер с полной копией: следующий круг сам запишет туда снимок.
    public func addStorage(_ id: ServerHost.ID) async {
        guard var state = book.sync, !state.storages.contains(id) else { return }
        state.storages.append(id)
        book.sync = state
        await writeProfile(startingSync: false)
        await syncNow()
    }

    /// Перестаёт ходить на сервер. Папка на нём остаётся: её могут читать
    /// другие машины, а удалить её — решение человека, а не приложения.
    public func removeStorage(_ id: ServerHost.ID) async {
        guard var state = book.sync, state.storages.count > 1 else { return }
        state.storages.removeAll { $0 == id }
        state.marks[id] = nil
        book.sync = state
        syncFailures[id] = nil
        await writeProfile(startingSync: false)
    }

    /// Заводит ключи этой машины и делает первый круг: пустую папку займёт,
    /// в занятой оставит просьбу и покажет код.
    public func enableSync(storage: ServerHost.ID) async {
        guard book.sync == nil, profileWritable else { return }
        do {
            let name = Host.current().localizedName ?? "Mac"
            book.sync = SyncState(identity: try SyncIdentity.create(name: name), storages: [storage])
        } catch {
            syncPhase = .failed(strings.syncError(error))
            return
        }
        // Ключи машины пишутся в профиль до первой поездки: иначе после
        // перезапуска родилась бы вторая машина с другим кодом.
        guard await writeProfile(startingSync: false) else {
            book.sync = nil
            return
        }
        await syncNow()
    }

    /// Выключает синхронизацию на этой машине. Хосты остаются; в списке
    /// машин на других она остаётся, пока её там не отзовут.
    public func disableSync() async {
        syncTask?.cancel()
        book.sync = nil
        syncRequests = []
        syncFailures = [:]
        syncClockWarnings = []
        syncPhase = .off
        await writeProfile(startingSync: false)
    }

    public func approveMachine(_ id: String) async { await syncNow(SyncEngine.Changes(approve: [id])) }

    public func revokeMachine(_ id: String) async { await syncNow(SyncEngine.Changes(revoke: [id])) }

    /// Код машины, которая пустила эту, совпал: можно доверять её подписи.
    public func trustSigner(_ machine: SyncMachine) async {
        await syncNow(SyncEngine.Changes(trust: machine))
    }

    /// Убирает просьбу, не пуская машину.
    public func dismissMachine(_ id: String) async {
        // Просьба лежит в каждом хранилище, куда дотянулась машина: убирать
        // отовсюду. Ошибка одного сервера — в его строке, остальные не ждут.
        for (storage, remote) in syncRemotes() {
            do {
                try await remote.dismiss(id)
            } catch {
                syncFailures[storage] = strings.syncError(error)
            }
        }
        syncRequests.removeAll { $0.id == id }
    }

    /// Синхронизация после правки — с задержкой, чтобы серия правок ушла одной.
    func scheduleSync() {
        guard book.sync != nil else { return }
        syncTask?.cancel()
        syncTask = Task {
            // `try?`: сон прерывает только отмена — пришла правка новее,
            // и синхронизация уже запланирована заново.
            try? await Task.sleep(for: Self.syncDelay)
            guard !Task.isCancelled else { return }
            await syncNow()
        }
    }

    /// Возврат в окно после долгого перерыва — повод забрать чужие правки.
    func syncIfStale() {
        guard let state = book.sync, !syncRunning else { return }
        let last = state.lastSync ?? .distantPast
        if Date().timeIntervalSince(last) > Self.syncStaleAfter { Task { await syncNow() } }
    }

    /// Один круг: прочитать хранилище, слить, записать, применить к профилю.
    public func syncNow(_ changes: SyncEngine.Changes = .init()) async {
        guard book.sync != nil, profileWritable else { return }
        guard !syncRunning else {
            // Круг уже идёт; просьбу человека (пустить, отозвать) не теряем.
            syncPending.approve += changes.approve
            syncPending.revoke += changes.revoke
            syncPending.trust = changes.trust ?? syncPending.trust
            syncAgain = true
            return
        }
        syncRunning = true
        defer { syncRunning = false }
        var changes = changes
        // Правка посреди круга: результат устарел ещё до применения, и круг
        // повторяется. Три раза подряд — значит, правят непрерывно; доедет
        // со следующей записью.
        for _ in 0..<3 {
            changes.approve += syncPending.approve
            changes.revoke += syncPending.revoke
            changes.trust = changes.trust ?? syncPending.trust
            syncPending = SyncEngine.Changes()
            syncAgain = false
            guard await syncRound(changes) else { return }
            changes = SyncEngine.Changes()
            if !syncAgain { return }
        }
    }

    /// `false` — круг не удался или результат устарел и применять его нечего.
    private func syncRound(_ changes: SyncEngine.Changes) async -> Bool {
        guard let state = book.sync else { return false }
        let remotes = syncRemotes()
        syncPhase = .working
        let items = book.syncItems()
        let outcome: SyncEngine.Outcome
        do {
            outcome = try await SyncEngine.run(items: items, state: state, remotes: remotes, changes: changes)
        } catch {
            syncPhase = .failed(remotes.isEmpty ? strings("sync.noStorage") : strings.syncError(error))
            return false
        }
        // Профиль или список хранилищ поменялся, пока шёл круг: применять ответ
        // значит затереть правку.
        guard book.syncItems() == items, book.sync?.identity == state.identity,
            book.sync?.storages == state.storages
        else {
            syncAgain = true
            return true
        }
        switch outcome {
        case .awaitingApproval(let next, let code):
            book.sync = next
            syncPhase = .waiting(code: code)
        case .confirmSigner(let next, let signer):
            book.sync = next
            syncPhase = .confirm(signer: signer)
        case .synced(let records, var next, let waiting, let failures):
            syncFailures = failures.mapValues { strings.syncError($0) }
            let now = Int64(Date().timeIntervalSince1970 * 1_000)
            syncClockWarnings = SyncMerge.ahead(records, now: now).sorted { $0.key < $1.key }.map {
                id, lead in
                let name = next.machines.first { $0.id == id }?.name ?? id
                return strings.ordered("sync.ahead", [name, "\(max(1, lead / 86_400_000))"])
            }
            for id in next.storages where remotes[id] == nil { syncFailures[id] = strings("sync.noStorage") }
            book.applySync(records)
            next.rebase(book.syncItems(), merged: records)
            book.sync = next
            syncRequests = waiting
            syncPhase = .synced(next.lastSync ?? Date())
            syncForwardsFromBook()
            await syncMCPModesFromBook()
        }
        await writeProfile(startingSync: false)
        return true
    }

    /// Хранилища, чьи хосты есть в списке. Пропавший хост — ошибка его строки.
    private func syncRemotes() -> [UUID: SyncRemote] {
        var remotes: [UUID: SyncRemote] = [:]
        for id in book.sync?.storages ?? [] {
            guard let host = book.hosts.first(where: { $0.id == id }) else { continue }
            let transport = SystemSSHTransport(host: host, route: book.route(for: host))
            remotes[id] = SyncRemote { command, input in
                try await transport.run(command, input: input, timeout: .seconds(60))
            }
        }
        return remotes
    }
}
