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

    public var syncStorage: ServerHost? {
        book.sync.flatMap { state in book.hosts.first { $0.id == state.storage } }
    }

    /// Заводит ключи этой машины и делает первый круг: пустую папку займёт,
    /// в занятой оставит просьбу и покажет код.
    public func enableSync(storage: ServerHost.ID) async {
        guard book.sync == nil, profileWritable else { return }
        do {
            let name = Host.current().localizedName ?? "Mac"
            book.sync = SyncState(identity: try SyncIdentity.create(name: name), storage: storage)
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
        syncPhase = .off
        await writeProfile(startingSync: false)
    }

    public func approveMachine(_ id: String) async { await syncNow(SyncEngine.Changes(approve: [id])) }

    public func revokeMachine(_ id: String) async { await syncNow(SyncEngine.Changes(revoke: [id])) }

    /// Код машины, которая пустила эту, совпал: можно доверять её подписи.
    public func trustSigner(_ id: String) async { await syncNow(SyncEngine.Changes(trust: id)) }

    /// Убирает просьбу, не пуская машину.
    public func dismissMachine(_ id: String) async {
        guard let remote = syncRemote() else { return }
        do {
            try await remote.dismiss(id)
            syncRequests.removeAll { $0.id == id }
        } catch {
            syncPhase = .failed(strings.syncError(error))
        }
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
        guard let state = book.sync, let remote = syncRemote() else { return false }
        syncPhase = .working
        let items = book.syncItems()
        let outcome: SyncEngine.Outcome
        do {
            outcome = try await SyncEngine.run(items: items, state: state, remote: remote, changes: changes)
        } catch {
            syncPhase = .failed(strings.syncError(error))
            return false
        }
        // Профиль поменялся, пока шёл круг: применять ответ значит затереть правку.
        guard book.syncItems() == items, book.sync?.identity == state.identity else {
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
        case .synced(let records, var next, let waiting):
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

    private func syncRemote() -> SyncRemote? {
        guard let state = book.sync else { return nil }
        guard let host = book.hosts.first(where: { $0.id == state.storage }) else {
            syncPhase = .failed(strings("sync.noStorage"))
            return nil
        }
        let transport = SystemSSHTransport(host: host, route: book.route(for: host))
        return SyncRemote { command, input in
            try await transport.run(command, input: input, timeout: .seconds(60))
        }
    }
}
