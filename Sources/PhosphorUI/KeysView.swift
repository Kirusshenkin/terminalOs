public import KeysKit
public import SwiftUI

/// Keys installed on the server, with the lock-out guard in plain sight.
public struct KeysView: View {
    @Environment(\.style) private var style
    @Bindable var model: AppModel

    public init(model: AppModel) { self.model = model }
    private var strings: Strings { model.strings }

    /// Ключи с сервера; пример — только пока нет подключения.
    private var keys: [AuthorizedKey] {
        model.serverKeys.isEmpty ? AuthorizedKeysFile.parse(Self.sample) : model.serverKeys
    }

    private var isLive: Bool { !model.serverKeys.isEmpty }
    private var currentFingerprint: String? { model.myFingerprint ?? keys.first?.fingerprint }

    public var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 14) {
                Text("authorized_keys").font(style.font(15)).foregroundStyle(style.bright)
                Text("root@app-1").font(style.font(12)).foregroundStyle(style.muted)
                Spacer()
                if !isLive {
                    Text("нет подключения — показан пример")
                        .font(style.font(10.5)).foregroundStyle(style.muted)
                }
                PhButton("обновить") { Task { await model.loadKeys() } }
                PhButton("+ добавить", kind: .primary) {}
            }
            header
            ForEach(keys) { key in row(key) }
            if let error = model.keysError {
                Text(error).font(style.font(11.5)).foregroundStyle(style.warning)
            }
            warning
            Spacer(minLength: 0)
        }
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

    private var warning: some View {
        Text(strings("keys.lockout"))
            .font(style.font(11.5))
            .foregroundStyle(style.warning)
            .padding(.horizontal, 12).padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(style.surface)
            .overlay(Rectangle().stroke(style.warning.opacity(0.45), lineWidth: 1))
    }

    private static let sample = """
        ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIH1vN3Kk8lQ2mZ0pW7xR4tYs6uVbNcXdEfGhIjKlMnOp you@mac
        ecdsa-sha2-nistp256 AAAAE2VjZHNhLXNoYTItbmlzdHAyNTYAAAAIbmlzdHAyNTYAAABBBBmZ8kQ== secure-enclave
        command="deploy.sh",no-pty ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIKlMnOpQrStUvWxYz012345 deploy@ci
        #phosphor-disabled ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIP0oQrStUvWxYz0123456789AbCdEfGhIjKlMnOpQr temp
        """
}
