public import HostsKit
public import SwiftUI

/// ⇧⌘O: подключиться к хосту, не снимая рук с клавиатуры.
///
/// Поиск тот же, что на странице хостов (`HostBook.search`), а строка вида
/// `user@host[:port]` подключает к серверу, которого в списке нет, — как
/// поле быстрого подключения там же.
struct QuickConnect: View {
    @Environment(\.style) private var style
    @Environment(\.dismiss) private var dismiss
    @Bindable var model: AppModel
    @State private var query = ""
    @State private var highlighted = 0
    @FocusState private var fieldFocused: Bool

    /// Больше не нужно: длинный список — это страница хостов, а не окно.
    private static let visible = 8

    private var matches: [ServerHost] {
        Array(model.book.search(query).prefix(Self.visible))
    }

    /// То, что подключится по ⏎: выделенный хост или адрес из строки.
    private var target: ServerHost? {
        if matches.indices.contains(highlighted) { return matches[highlighted] }
        return model.parseQuickConnect(query)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label2(model.strings("cmd.quickConnect"))
            TextField(model.strings("qc.placeholder"), text: $query)
                .textFieldStyle(.plain)
                .font(style.font(14))
                .foregroundStyle(style.bright)
                .padding(8)
                .overlay(Rectangle().stroke(style.text.opacity(0.3), lineWidth: 1))
                .focused($fieldFocused)
                .onSubmit(connect)
                .onKeyPress(.downArrow) { move(1) }
                .onKeyPress(.upArrow) { move(-1) }
                .onKeyPress(.escape) {
                    dismiss()
                    return .handled
                }
                .onChange(of: query) { highlighted = 0 }

            if matches.isEmpty {
                Text(
                    model.parseQuickConnect(query) == nil
                        ? model.strings("qc.nothing") : model.strings("qc.adHoc")
                )
                .font(style.font(11.5)).foregroundStyle(style.muted)
            }
            ForEach(Array(matches.enumerated()), id: \.element.id) { index, host in
                row(host, isHighlighted: index == highlighted)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        highlighted = index
                        connect()
                    }
            }
            Text(model.strings("qc.hint"))
                .font(style.font(10.5)).foregroundStyle(style.muted)
                .padding(.top, 4)
        }
        .padding(16)
        .frame(width: 440)
        .background(style.background)
        .onAppear { fieldFocused = true }
    }

    private func row(_ host: ServerHost, isHighlighted: Bool) -> some View {
        HStack(spacing: 10) {
            Text(host.name).font(style.font(12.5))
                .foregroundStyle(isHighlighted ? style.background : style.bright)
            Spacer()
            Text("\(host.user)@\(host.address)").font(style.font(11))
                .foregroundStyle(isHighlighted ? style.background : style.muted)
                .lineLimit(1).truncationMode(.middle)
        }
        .padding(.horizontal, 8).padding(.vertical, 5)
        .background(isHighlighted ? style.accent : .clear)
    }

    private func move(_ step: Int) -> KeyPress.Result {
        guard !matches.isEmpty else { return .ignored }
        highlighted = (highlighted + step + matches.count) % matches.count
        return .handled
    }

    private func connect() {
        guard let host = target else { return }
        dismiss()
        model.screen = .terminal
        Task { await model.connect(to: host) }
    }
}
