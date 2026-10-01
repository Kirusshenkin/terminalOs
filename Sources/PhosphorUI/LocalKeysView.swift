public import AppKit
public import KeysKit
public import SwiftUI

/// Key pairs in ~/.ssh on this Mac. They belong to no server, so they live
/// apart from any server's authorized_keys.
public struct LocalKeysView: View {
    @Environment(\.style) private var style
    @Bindable var model: AppModel

    public init(model: AppModel) { self.model = model }
    private var strings: Strings { model.strings }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            localKeys
            Spacer(minLength: 0)
        }
        .task { model.loadLocalKeys() }
    }

    /// Ключи, которые лежат у тебя в ~/.ssh. Показываем публичную часть с
    /// комментарием — обычно это и есть «юзер», под которым ключ выдан.
    private var localKeys: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(strings("keys.local")).font(style.font(15)).foregroundStyle(style.bright)
                Text("~/.ssh").font(style.font(11.5)).foregroundStyle(style.muted)
            }
            if model.localKeys.isEmpty {
                Text(strings("keys.noPairs"))
                    .font(style.font(12)).foregroundStyle(style.muted)
            }
            ForEach(model.localKeys) { key in
                HStack(spacing: 10) {
                    Text(key.name)
                        .font(style.font(12.5)).foregroundStyle(style.text)
                        .frame(width: 220, alignment: .leading).lineLimit(1)
                    Text(key.algorithm + (key.bits.map { " · \($0)b" } ?? ""))
                        .font(style.font(11)).foregroundStyle(style.muted)
                        .frame(width: 150, alignment: .leading)
                    Text(key.comment ?? "—")
                        .font(style.font(11.5)).foregroundStyle(style.muted)
                        .frame(maxWidth: .infinity, alignment: .leading).lineLimit(1)
                    if !key.hasPrivate {
                        Text(strings("keys.noPrivate"))
                            .font(style.font(10)).foregroundStyle(style.warning)
                    }
                    if let weakness = key.weakness {
                        Text(strings.keyWeakness(weakness)).font(style.font(10)).foregroundStyle(style.warning)
                    }
                }
                .padding(.vertical, 4)
                .overlay(alignment: .bottom) {
                    Rectangle().fill(style.rule.opacity(0.4)).frame(height: 1)
                }
                .contextMenu {
                    Button(strings("keys.copyPrint")) {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(key.fingerprint, forType: .string)
                    }
                }
            }
        }
    }
}
