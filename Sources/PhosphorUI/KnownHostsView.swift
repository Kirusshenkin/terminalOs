public import KeysKit
public import SwiftUI

/// Кому мы однажды доверились и чей отпечаток запомнили.
public struct KnownHostsView: View {
    @Environment(\.style) private var style
    @Bindable var model: AppModel

    public init(model: AppModel) { self.model = model }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text("известные хосты").font(style.font(15)).foregroundStyle(style.bright)
                Text("~/.ssh/known_hosts · \(model.knownHosts.count)")
                    .font(style.font(12)).foregroundStyle(style.muted)
                Spacer()
                PhButton("обновить") { model.loadKnownHosts() }
            }

            HStack(spacing: 10) {
                Label2("хост").frame(width: 240, alignment: .leading)
                Label2("тип").frame(width: 130, alignment: .leading)
                Label2("отпечаток").frame(maxWidth: .infinity, alignment: .leading)
                Label2("").frame(width: 90)
            }
            .padding(.bottom, 4)
            .overlay(alignment: .bottom) { Rule() }

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(model.knownHosts) { entry in row(entry) }
                }
            }

            if let error = model.knownHostsError {
                Text(error).font(style.font(11.5)).foregroundStyle(style.warning)
            }

            Text(
                "отпечатки считаются здесь, на этой машине — ssh-keygen для этого не нужен. "
                    + "«Забыть» удаляет строку: следующее подключение спросит доверие заново"
            )
            .font(style.font(11)).foregroundStyle(style.muted)
        }
    }

    private func row(_ entry: KnownHost) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 1) {
                Text(entry.displayName)
                    .foregroundStyle(entry.isHashed ? style.muted : style.text)
                    .lineLimit(1)
                if let marker = entry.marker {
                    Text(marker).font(style.font(10)).foregroundStyle(style.warning)
                }
            }
            .frame(width: 240, alignment: .leading)

            Text(entry.algorithm)
                .foregroundStyle(style.muted).frame(width: 130, alignment: .leading)

            Text(entry.fingerprint)
                .font(style.font(11)).foregroundStyle(style.muted)
                .frame(maxWidth: .infinity, alignment: .leading)

            PhButton("забыть", kind: .danger) { model.forget(entry) }
                .frame(width: 90)
        }
        .font(style.font(12))
        .padding(.vertical, 5)
        .overlay(alignment: .bottom) { Rectangle().fill(style.rule.opacity(0.4)).frame(height: 1) }
    }
}
