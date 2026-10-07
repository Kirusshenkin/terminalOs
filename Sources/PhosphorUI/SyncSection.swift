import HostsKit
import SwiftUI
import SyncKit

/// Синхронизация между своими машинами — блок на странице профиля (#18).
struct SyncSection: View {
    @Environment(\.style) private var style
    @Bindable var model: AppModel
    @State private var storage: ServerHost.ID?
    /// Машина, отзыв которой ждёт второго нажатия: отзыв меняет ключ
    /// профиля для всех, случайный клик тут дороже лишнего.
    @State private var revoking: String?

    private var strings: Strings { model.strings }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label2(strings("sync.title"))
            Text(strings("sync.note"))
                .font(style.font(11)).foregroundStyle(style.muted)
                .fixedSize(horizontal: false, vertical: true)
            if let state = model.syncState {
                enabled(state)
            } else {
                setup
            }
        }
    }

    @ViewBuilder private var setup: some View {
        if model.book.hosts.isEmpty {
            note(strings("sync.noHosts"))
        } else {
            HStack(spacing: 8) {
                Menu {
                    ForEach(model.book.hosts) { host in
                        Button(host.name) { storage = host.id }
                    }
                } label: {
                    Text("\(strings("sync.storage")): \(storageName ?? "—")")
                        .font(style.font(11.5)).foregroundStyle(style.text)
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                PhButton(strings("sync.enable"), kind: .primary) {
                    guard let storage else { return }
                    Task { await model.enableSync(storage: storage) }
                }
                .disabled(storage == nil)
            }
            status
        }
    }

    private var storageName: String? {
        storage.flatMap { id in model.book.hosts.first { $0.id == id }?.name }
    }

    @ViewBuilder private func enabled(_ state: SyncState) -> some View {
        Text("\(strings("sync.storage")): \(model.syncStorage?.name ?? "—") · ~/.phosphor-sync")
            .font(style.font(11.5)).foregroundStyle(style.text)
        HStack(spacing: 8) {
            PhButton(strings(state.isJoined ? "sync.now" : "sync.check")) { Task { await model.syncNow() } }
            PhButton(strings("sync.disable")) { Task { await model.disableSync() } }
        }
        status
        if state.isJoined {
            machines(state)
            requests
        }
    }

    @ViewBuilder private var status: some View {
        switch model.syncPhase {
        case .off: EmptyView()
        case .working: note(strings("sync.working"))
        case .waiting(let code): note(strings.format("sync.waiting", code), color: style.bright)
        case .confirm(let signer):
            note(strings.ordered("sync.confirm", [signer.name, signer.code]), color: style.bright)
            PhButton(strings("sync.trust"), kind: .primary) { Task { await model.trustSigner(signer.id) } }
        case .synced(let date):
            note(strings.format("sync.synced", date.formatted(date: .omitted, time: .shortened)))
        case .failed(let text): note(text, color: style.warning)
        }
    }

    private func machines(_ state: SyncState) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label2(strings("sync.machines"))
            ForEach(state.machines) { machine in
                HStack(spacing: 8) {
                    Text(machine.name).font(style.font(12)).foregroundStyle(style.text)
                    Text(machine.code).font(style.font(11)).foregroundStyle(style.muted)
                    Spacer(minLength: 4)
                    if machine.id == state.identity.id {
                        Text(strings("sync.thisMachine")).font(style.font(11)).foregroundStyle(style.muted)
                    } else if revoking == machine.id {
                        PhButton(strings("sync.revoke"), kind: .danger) {
                            revoking = nil
                            Task { await model.revokeMachine(machine.id) }
                        }
                    } else {
                        PhButton(strings("sync.revoke")) { revoking = machine.id }
                    }
                }
                if revoking == machine.id {
                    note(strings.format("sync.revokeConfirm", machine.name), color: style.warning)
                }
            }
        }
    }

    @ViewBuilder private var requests: some View {
        if !model.syncRequests.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Label2(strings("sync.requests"))
                note(strings("sync.requestNote"))
                ForEach(model.syncRequests) { machine in
                    HStack(spacing: 8) {
                        Text(machine.name).font(style.font(12)).foregroundStyle(style.text)
                        Text(machine.code).font(style.font(12.5, weight: .medium)).foregroundStyle(
                            style.bright)
                        Spacer(minLength: 4)
                        PhButton(strings("sync.approve"), kind: .primary) {
                            Task { await model.approveMachine(machine.id) }
                        }
                        PhButton(strings("sync.dismiss")) { Task { await model.dismissMachine(machine.id) } }
                    }
                }
            }
        }
    }

    private func note(_ text: String, color: Color? = nil) -> some View {
        Text(text)
            .font(style.font(11)).foregroundStyle(color ?? style.muted)
            .fixedSize(horizontal: false, vertical: true)
            .textSelection(.enabled)
    }
}
