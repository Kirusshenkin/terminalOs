public import HostsKit
public import SwiftUI

/// Форма нового или существующего хоста.
public struct HostEditor: View {
    @Environment(\.style) private var style
    @Bindable var model: AppModel
    /// Хост, который правим. Пусто — создаём новый.
    private let existing: ServerHost?

    @State private var name: String
    @State private var address: String
    @State private var user: String
    @State private var port: String
    @State private var tags: String
    @State private var groupID: HostGroup.ID?
    @State private var reachKind: ReachKind
    @State private var proxyHost: String
    @State private var proxyPort: String

    private enum ReachKind: String, CaseIterable {
        case direct, socks
        var title: String {
            switch self {
            case .direct: "напрямую"
            case .socks: "через прокси"
            }
        }
    }

    public init(model: AppModel, editing host: ServerHost? = nil) {
        self.model = model
        self.existing = host
        _name = State(initialValue: host?.name ?? "")
        _address = State(initialValue: host?.address ?? "")
        _user = State(initialValue: host?.user ?? "root")
        _port = State(initialValue: String(host?.port ?? 22))
        _tags = State(initialValue: host?.tags.joined(separator: ", ") ?? "")
        _groupID = State(initialValue: host?.groupID)
        if case .socks(let proxyHost, let proxyPort) = host?.reach {
            _reachKind = State(initialValue: .socks)
            _proxyHost = State(initialValue: proxyHost)
            _proxyPort = State(initialValue: String(proxyPort))
        } else {
            _reachKind = State(initialValue: .direct)
            _proxyHost = State(initialValue: "127.0.0.1")
            _proxyPort = State(initialValue: "10808")
        }
    }

    /// Имя не обязательно: если его не задали, берём адрес — так карточка
    /// никогда не будет безымянной.
    private var resolvedName: String {
        name.trimmingCharacters(in: .whitespaces).isEmpty
            ? address.trimmingCharacters(in: .whitespaces)
            : name.trimmingCharacters(in: .whitespaces)
    }

    private var isValid: Bool {
        !address.trimmingCharacters(in: .whitespaces).isEmpty
            && !user.trimmingCharacters(in: .whitespaces).isEmpty
            && (Int(port).map { (1...65_535).contains($0) } ?? false)
            && (reachKind == .direct || Int(proxyPort).map { (1...65_535).contains($0) } ?? false)
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(existing == nil ? "новый хост" : "правка хоста")
                .font(style.font(15)).foregroundStyle(style.bright)

            VStack(alignment: .leading, spacing: 10) {
                field("адрес", text: $address, placeholder: "10.0.0.1 или example.com")
                HStack(spacing: 10) {
                    field("пользователь", text: $user)
                    field("порт", text: $port).frame(width: 110)
                }
                field("имя", text: $name, placeholder: "необязательно — возьмём адрес")
                field("теги", text: $tags, placeholder: "через запятую")
            }

            group
            reach

            Spacer(minLength: 0)

            HStack(spacing: 8) {
                Spacer()
                if let existing {
                    PhButton("удалить", kind: .danger) {
                        model.pendingHostRemoval = existing
                        model.editingHost = nil
                        model.isAddingHost = false
                    }
                    Spacer()
                }
                PhButton("отмена") { close() }
                PhButton(existing == nil ? "добавить" : "сохранить", kind: .primary) { save() }
                    .disabled(!isValid)
                    .opacity(isValid ? 1 : 0.4)
            }
        }
        .padding(22)
        .frame(width: 520, height: 480)
        .background(style.background)
    }

    private func field(
        _ title: String, text: Binding<String>, placeholder: String = ""
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Label2(title)
            TextField(placeholder, text: text)
                .textFieldStyle(.plain)
                .font(style.font(12.5))
                .foregroundStyle(style.text)
                .padding(.horizontal, 10).padding(.vertical, 6)
                .overlay(Rectangle().stroke(style.text.opacity(0.3), lineWidth: 1))
        }
    }

    private var group: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label2("группа — она несёт настройки: доступ, тему, режим ии")
            HStack(spacing: 6) {
                chip("без группы", selected: groupID == nil) { groupID = nil }
                ForEach(model.book.groups) { item in
                    chip(item.name, selected: groupID == item.id) { groupID = item.id }
                }
            }
        }
    }

    private var reach: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label2("как дотянуться")
            HStack(spacing: 6) {
                ForEach(ReachKind.allCases, id: \.self) { kind in
                    chip(kind.title, selected: reachKind == kind) { reachKind = kind }
                }
            }
            if reachKind == .socks {
                HStack(spacing: 10) {
                    field("хост прокси", text: $proxyHost)
                    field("порт", text: $proxyPort).frame(width: 110)
                }
            }
        }
    }

    private func chip(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(style.font(11))
                .padding(.horizontal, 9).padding(.vertical, 3)
                .foregroundStyle(selected ? style.background : style.muted)
                .background(selected ? style.accent : .clear)
                .overlay(
                    Rectangle().stroke(
                        selected ? style.accent : style.text.opacity(0.25), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private func close() {
        model.isAddingHost = false
        model.editingHost = nil
    }

    private func save() {
        let host = ServerHost(
            id: existing?.id ?? UUID(),
            name: resolvedName,
            address: address.trimmingCharacters(in: .whitespaces),
            port: Int(port) ?? 22,
            user: user.trimmingCharacters(in: .whitespaces),
            groupID: groupID,
            tags: tags.split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty },
            reach: reachKind == .socks
                ? .socks(host: proxyHost, port: Int(proxyPort) ?? 1080)
                : .direct
        )
        if existing == nil { model.addHost(host) } else { model.update(host) }
        close()
    }
}
