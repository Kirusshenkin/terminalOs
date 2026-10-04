public import HostsKit
public import SwiftUI

/// Форма нового или существующего хоста.
public struct HostEditor: View {
    @Environment(\.style) private var style
    @Bindable var model: AppModel
    private var strings: Strings { model.strings }
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
    /// Путь к ключу. nil — ключ выбирает ssh: ключи по умолчанию и агент.
    @State private var identityFile: String?

    private enum ReachKind: String, CaseIterable {
        case direct, socks
        /// Ключ, а не готовая строка: enum не знает про язык интерфейса.
        var key: String {
            switch self {
            case .direct: "host.direct"
            case .socks: "host.viaProxy"
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
        _identityFile = State(initialValue: host?.identityFile)
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
            Text(existing == nil ? strings("host.new") : strings("host.edit"))
                .font(style.font(15)).foregroundStyle(style.bright)

            VStack(alignment: .leading, spacing: 10) {
                field(strings("host.address"), text: $address, placeholder: strings("host.addressHint"))
                HStack(spacing: 10) {
                    field(strings("host.user"), text: $user)
                    field(strings("host.port"), text: $port).frame(width: 110)
                }
                field(strings("host.name"), text: $name, placeholder: strings("host.nameHint"))
                field(strings("host.tags"), text: $tags, placeholder: strings("host.tagsHint"))
            }

            key
            group
            reach

            Spacer(minLength: 0)

            HStack(spacing: 8) {
                Spacer()
                if let existing {
                    PhButton(strings("common.delete"), kind: .danger) {
                        model.pendingHostRemoval = existing
                        model.editingHost = nil
                        model.isAddingHost = false
                    }
                    Spacer()
                }
                PhButton(strings("common.cancel")) { close() }
                PhButton(existing == nil ? strings("common.add") : strings("common.save"), kind: .primary) {
                    save()
                }
                .disabled(!isValid)
                .opacity(isValid ? 1 : 0.4)
            }
        }
        .padding(22)
        .frame(width: 520, height: 540)
        // Ключи Мака читаются при открытии формы: новый ключ, сделанный
        // минуту назад в терминале, должен уже быть в списке.
        .task { model.loadLocalKeys() }
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
            Label2(strings("host.groupNote"))
            HStack(spacing: 6) {
                chip(strings("host.noGroup"), selected: groupID == nil) { groupID = nil }
                ForEach(model.book.groups) { item in
                    chip(item.name, selected: groupID == item.id) { groupID = item.id }
                }
            }
        }
    }

    /// Каким ключом входить. Список — ключи из `~/.ssh` с приватной половиной:
    /// без неё войти нечем, и предлагать такой ключ значило бы обещать вход.
    private var key: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label2(strings("host.key"))
            Menu {
                Button(strings("host.keyAuto")) { identityFile = nil }
                Divider()
                ForEach(model.localKeys.filter(\.hasPrivate)) { local in
                    Button(local.name) { identityFile = Self.shortPath(local.id) }
                }
            } label: {
                Text(identityFile.map { ($0 as NSString).lastPathComponent } ?? strings("host.keyAuto"))
                    .font(style.font(12.5))
                    .foregroundStyle(style.text)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .overlay(Rectangle().stroke(style.text.opacity(0.3), lineWidth: 1))
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            if let identityFile, !FileManager.default.fileExists(atPath: Self.expanded(identityFile)) {
                // Ключ переименовали или удалили — говорим до подключения, а не
                // отказом сервера после.
                Text("\(strings("host.keyMissing")) \(identityFile)")
                    .font(style.font(11)).foregroundStyle(style.warning)
            }
        }
    }

    /// `~/.ssh/имя` вместо полного пути: профиль переезжает на другой Мак, где
    /// домашняя папка зовётся иначе. ssh раскрывает `~` в `-i` сам.
    static func shortPath(_ path: String) -> String {
        let home = NSHomeDirectory()
        return path.hasPrefix(home + "/") ? "~" + path.dropFirst(home.count) : path
    }

    static func expanded(_ path: String) -> String {
        (path as NSString).expandingTildeInPath
    }

    private var reach: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label2(strings("host.reach"))
            HStack(spacing: 6) {
                ForEach(ReachKind.allCases, id: \.self) { kind in
                    chip(strings(kind.key), selected: reachKind == kind) { reachKind = kind }
                }
            }
            if reachKind == .socks {
                HStack(spacing: 10) {
                    field(strings("host.proxyHost"), text: $proxyHost)
                    field(strings("host.port"), text: $proxyPort).frame(width: 110)
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
        .buttonStyle(PressFeedback())
    }

    private func close() {
        model.isAddingHost = false
        model.editingHost = nil
    }

    private func save() {
        // Правка начинается с того, что было: иначе форма молча сбрасывала бы
        // поля, которых в ней нет, — режим MCP, защиту, память о сервере.
        var host = existing ?? ServerHost(name: resolvedName, address: "")
        host.name = resolvedName
        host.address = address.trimmingCharacters(in: .whitespaces)
        host.port = Int(port) ?? 22
        host.user = user.trimmingCharacters(in: .whitespaces)
        host.groupID = groupID
        host.tags = tags.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        switch (reachKind, host.reach) {
        case (.socks, _):
            host.reach = .socks(host: proxyHost, port: Int(proxyPort) ?? 1080)
        case (.direct, .jump):
            // Бастион форма не показывает — и поэтому не трогает.
            break
        case (.direct, _):
            host.reach = .direct
        }
        host.identityFile = identityFile
        if existing == nil { model.addHost(host) } else { model.update(host) }
        close()
    }
}
