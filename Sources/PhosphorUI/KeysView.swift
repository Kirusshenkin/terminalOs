public import KeysKit
public import SwiftUI

/// Keys installed on the server, with the lock-out guard in plain sight.
public struct KeysView: View {
    @Environment(\.style) private var style
    let model: AppModel

    public init(model: AppModel) { self.model = model }
    private var strings: Strings { model.strings }

    private var keys: [AuthorizedKey] { AuthorizedKeysFile.parse(Self.sample) }
    private var currentFingerprint: String? { keys.first?.fingerprint }

    public var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 14) {
                Text("authorized_keys").font(style.font(15)).foregroundStyle(style.bright)
                Text("root@app-1").font(style.font(12)).foregroundStyle(style.muted)
                Spacer()
                PhButton("+ добавить", kind: .primary) {}
                PhButton("скопировать мой") {}
            }
            header
            ForEach(keys) { key in row(key) }
            warning
            Spacer(minLength: 0)
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Label2("ключ").frame(width: 240, alignment: .leading)
            Label2("отпечаток").frame(maxWidth: .infinity, alignment: .leading)
            Label2("опции").frame(width: 200, alignment: .leading)
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
                .frame(width: 200, alignment: .leading)
                .lineLimit(1)
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
