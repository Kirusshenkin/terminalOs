public import SwiftUI

/// Ввод парольной фразы для экспорта или импорта профиля.
///
/// Фраза — единственное, что защищает файл экспорта, поэтому вводится явно и
/// скрыто, а не подставляется. Для экспорта просим подтвердить фразу дважды:
/// опечатка здесь означает файл, который потом не открыть.
struct PassphraseSheet: View {
    @Environment(\.style) private var style
    @Environment(\.dismiss) private var dismiss
    @Bindable var model: AppModel
    let prompt: AppModel.ProfilePrompt

    @State private var passphrase = ""
    @State private var confirm = ""

    private var isExport: Bool {
        if case .export = prompt { return true }
        return false
    }
    private var ready: Bool {
        !passphrase.isEmpty && (!isExport || passphrase == confirm)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(model.strings(isExport ? "profile.export" : "profile.import"))
                .font(style.font(15)).foregroundStyle(style.bright)
            Text(model.strings("profile.passphraseNote"))
                .font(style.font(11)).foregroundStyle(style.muted)
                .fixedSize(horizontal: false, vertical: true)

            field(model.strings("profile.passphrase"), text: $passphrase)
            if isExport {
                field(model.strings("profile.passphraseAgain"), text: $confirm)
                if !confirm.isEmpty, passphrase != confirm {
                    Text(model.strings("profile.mismatch"))
                        .font(style.font(10)).foregroundStyle(style.warning)
                }
            }

            HStack(spacing: 8) {
                Spacer()
                PhButton(model.strings("common.cancel")) { dismiss() }
                PhButton(model.strings(isExport ? "profile.export" : "profile.import"),
                    kind: .primary) {
                    run()
                }
                .disabled(!ready)
                .opacity(ready ? 1 : 0.4)
            }
        }
        .padding(18)
        .frame(width: 380)
        .background(style.surface)
    }

    private func field(_ title: String, text: Binding<String>) -> some View {
        SecureField(title, text: text)
            .textFieldStyle(.plain)
            .font(style.font(13))
            .foregroundStyle(style.text)
            .padding(.horizontal, 10).padding(.vertical, 7)
            .overlay(Rectangle().stroke(style.text.opacity(0.3), lineWidth: 1))
    }

    private func run() {
        let phrase = passphrase
        dismiss()
        switch prompt {
        case .export:
            Task { await model.performExport(passphrase: phrase) }
        case .importFrom(let url):
            Task { await model.performImport(from: url, passphrase: phrase) }
        }
    }
}
