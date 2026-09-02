public import KeysKit
public import SwiftUI

/// Keys installed on the server, with the lock-out guard in plain sight.
public struct KeysView: View {
    @Environment(\.style) private var style
    @Bindable var model: AppModel

    public init(model: AppModel) { self.model = model }
    private var strings: Strings { model.strings }

    /// Только ключи, прочитанные с сервера. Пример на этом экране опасен
    /// вдвойне: спутать показанный ключ с настоящим — значит решить, что доступ
    /// у кого-то есть, когда его нет, или наоборот.
    private var keys: [AuthorizedKey] { model.serverKeys }

    private var isLive: Bool { model.session != nil }
    private var currentFingerprint: String? { model.myFingerprint ?? keys.first?.fingerprint }

    @ViewBuilder public var body: some View {
        if model.session == nil {
            HostPicker(
                model: model,
                title: "authorized_keys",
                note: "ключи читаются с сервера — выбери, с какого"
            )
            .frame(maxWidth: 320, alignment: .leading)
            Spacer(minLength: 0)
        } else {
            live
        }
    }

    private var live: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 14) {
                Text("authorized_keys").font(style.font(15)).foregroundStyle(style.bright)
                Text(target).font(style.font(12)).foregroundStyle(style.muted)
                Spacer()
                PhButton("обновить") { Task { await model.loadKeys() } }
                PhButton("+ добавить", kind: .primary) { model.isAddingKey = true }
            }
            header
            ForEach(keys) { key in row(key) }
            if model.isAddingKey { keyEditor }
            if let error = model.keysError {
                Text(error).font(style.font(11.5)).foregroundStyle(style.warning)
            }
            warning
            Spacer(minLength: 0)
        }
    }

    /// Кому принадлежит файл, который правим: имя берётся из профиля, а не из
    /// того, что прислал сервер.
    private var target: String {
        guard let id = model.selectedHost,
            let host = model.book.hosts.first(where: { $0.id == id })
        else { return "" }
        return "\(host.user)@\(host.name)"
    }

    private var header: some View {
        HStack(spacing: 10) {
            Label2("ключ").frame(width: 240, alignment: .leading)
            Label2("отпечаток").frame(maxWidth: .infinity, alignment: .leading)
            Label2("опции").frame(width: 140, alignment: .leading)
            Label2("").frame(width: 80, alignment: .leading)
        }
        .padding(.bottom, 4)
        .overlay(alignment: .bottom) { Rule() }
    }

    private func row(_ key: AuthorizedKey) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(key.isEnabled ? "●" : "○")
                        .foregroundStyle(key.weakness == nil ? style.accent : style.warning)
                    Text("\(key.algorithm) · \(key.comment ?? "—")")
                        .foregroundStyle(key.isEnabled ? style.text : style.muted)
                }
                if let weakness = key.weakness {
                    Text(weakness).font(style.font(10.5)).foregroundStyle(style.warning)
                } else if key.fingerprint == currentFingerprint {
                    Text(strings("keys.current")).font(style.font(10.5)).foregroundStyle(style.muted)
                }
            }
            .frame(width: 240, alignment: .leading)

            Text(key.fingerprint)
                .font(style.font(11)).foregroundStyle(style.muted)
                .frame(maxWidth: .infinity, alignment: .leading)

            Text(key.options ?? "—")
                .font(style.font(11)).foregroundStyle(style.muted)
                .frame(width: 140, alignment: .leading)
                .lineLimit(1)

            PhButton("удалить", kind: .danger) { model.requestKeyRemoval(key) }
                .disabled(!isLive)
                .opacity(isLive ? 1 : 0.4)
        }
        .font(style.font(12))
        .padding(.vertical, 6)
        .opacity(key.isEnabled ? 1 : 0.55)
    }

    /// Ввод новой строки ключа. Проверка — до отправки на сервер: строка,
    /// не похожая на ключ, туда просто не поедет.
    private var keyEditor: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label2("вставь строку из id_ed25519.pub")
            TextField("ssh-ed25519 AAAA… comment", text: $model.newKeyLine, axis: .vertical)
                .textFieldStyle(.plain)
                .font(style.font(11.5))
                .foregroundStyle(style.text)
                .lineLimit(2...4)
                .padding(.horizontal, 10).padding(.vertical, 6)
                .overlay(Rectangle().stroke(style.text.opacity(0.3), lineWidth: 1))
            HStack(spacing: 8) {
                if let preview = model.newKeyPreview {
                    Text(preview).font(style.font(11)).foregroundStyle(style.muted)
                }
                Spacer()
                PhButton("отмена") {
                    model.isAddingKey = false
                    model.newKeyLine = ""
                }
                PhButton("добавить на сервер", kind: .primary) {
                    Task { await model.addKeyToServer() }
                }
                .disabled(model.newKeyPreview == nil)
                .opacity(model.newKeyPreview == nil ? 0.4 : 1)
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .background(style.surface)
    }

    private var warning: some View {
        Text(strings("keys.lockout"))
            .font(style.font(11.5))
            .foregroundStyle(style.warning)
            .padding(.horizontal, 12).padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(style.surface)
            .overlay(Rectangle().stroke(style.warning.opacity(0.45), lineWidth: 1))
    }

}
