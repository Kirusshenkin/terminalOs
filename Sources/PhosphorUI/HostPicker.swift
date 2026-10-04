public import HostsKit
public import SwiftUI

/// Выбор сервера прямо на том экране, которому он нужен.
///
/// Docker, метрики и автонастройка без хоста показывать нечего. Раньше они
/// показывали витрину с придуманными числами — и человек видел работающий
/// сервер там, где не было даже соединения. Витрина убрана: пока сервер не
/// выбран, экран предлагает выбрать его из тех, что уже добавлены.
public struct HostPicker: View {
    @Environment(\.style) private var style
    @Bindable var model: AppModel
    private let title: String
    private let note: String
    @State private var query = ""

    public init(model: AppModel, title: String, note: String) {
        self.model = model
        self.title = title
        self.note = note
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label2(title)
            Text(note)
                .font(style.font(11))
                .foregroundStyle(style.muted)
                .padding(.bottom, 4)

            if model.book.hosts.isEmpty {
                Text(model.strings("common.noHosts"))
                    .font(style.font(12))
                    .foregroundStyle(style.muted)
                Button {
                    model.screen = .hosts
                    model.isAddingHost = true
                } label: {
                    Text(model.strings("common.addHost"))
                        .font(style.font(11.5))
                        .foregroundStyle(style.bright)
                }
                .buttonStyle(PressFeedback())
                .padding(.top, 2)
            } else {
                // Хостов бывают десятки: искать глазами по списку из сорока
                // строк — это не выбор, а пролистывание. Поиск сразу под рукой.
                search
                // Без прокрутки список вырастает выше окна и выталкивает шапку
                // за его верхний край.
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(shown) { host in
                            row(host)
                        }
                        if shown.isEmpty {
                            Text(model.strings("common.nothingFound"))
                                .font(style.font(11.5)).foregroundStyle(style.muted)
                                .padding(.vertical, 6)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func row(_ host: ServerHost) -> some View {
        let isCurrent = model.selectedHost == host.id
        return Button {
            Task { await model.connect(to: host) }
        } label: {
            HStack(spacing: 8) {
                Text(isCurrent ? "▸" : " ")
                    .foregroundStyle(isCurrent ? style.bright : style.muted)
                VStack(alignment: .leading, spacing: 1) {
                    Text(host.name)
                        .font(style.font(12.5))
                        .foregroundStyle(isCurrent ? style.bright : style.text)
                    Text("\(host.user)@\(host.address)")
                        .font(style.font(10.5))
                        .foregroundStyle(style.muted)
                }
                Spacer(minLength: 0)
            }
            .padding(.vertical, 3)
            .contentShape(Rectangle())
            .connecting(model.isConnecting(host), model: model)
        }
        .buttonStyle(PressFeedback())
    }
}

extension HostPicker {
    fileprivate var search: some View {
        HStack(spacing: 6) {
            Text(">").foregroundStyle(style.accent)
            TextField(model.strings("hosts.search"), text: $query)
                .textFieldStyle(.plain)
                .foregroundStyle(style.text)
                // Enter подключает первый найденный: набрал «b2b», нажал — и всё.
                .onSubmit {
                    if let first = shown.first { Task { await model.connect(to: first) } }
                }
        }
        .font(style.font(12))
        .padding(.horizontal, 10).padding(.vertical, 6)
        .overlay(Rectangle().stroke(style.text.opacity(0.3), lineWidth: 1))
        .padding(.bottom, 4)
    }

    /// Что показать: найденное, а без запроса — сначала те, с кем недавно
    /// работали. Порядок в книге — порядок добавления, и нужный сервер в нём
    /// оказывается где-то на третьем экране.
    fileprivate var shown: [ServerHost] {
        let needle = query.trimmingCharacters(in: .whitespaces).lowercased()
        let hosts = model.book.hosts.filter { host in
            needle.isEmpty
                || host.name.lowercased().contains(needle)
                || host.address.lowercased().contains(needle)
                || host.tags.contains { $0.lowercased().contains(needle) }
        }
        return Self.ordered(hosts, current: model.selectedHost, spaces: model.spaces)
    }

    /// Текущий — первым, за ним открытые спейсы, потом по свежести ответа,
    /// остальные — в прежнем порядке. Чистая функция.
    static func ordered(
        _ hosts: [ServerHost], current: ServerHost.ID?, spaces: [ServerHost.ID]
    ) -> [ServerHost] {
        hosts.enumerated().sorted { lhs, rhs in
            func rank(_ host: ServerHost) -> Int {
                if host.id == current { return 0 }
                if spaces.contains(host.id) { return 1 }
                return host.lastSeen == nil ? 3 : 2
            }
            let (left, right) = (rank(lhs.element), rank(rhs.element))
            if left != right { return left < right }
            if left == 2, let a = lhs.element.lastSeen, let b = rhs.element.lastSeen, a != b { return a > b }
            return lhs.offset < rhs.offset
        }.map(\.element)
    }
}
