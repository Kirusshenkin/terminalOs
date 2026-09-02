public import HostsKit
public import PhosphorCore
public import ProvisionKit
public import SwiftUI
public import ThemeKit

/// The hosts page: groups carry settings, tags carry search.
public struct HostsView: View {
    @Environment(\.style) private var style
    @Bindable var model: AppModel

    public init(model: AppModel) { self.model = model }

    private var strings: Strings { model.strings }

    public var body: some View {
        HStack(alignment: .top, spacing: 22) {
            SectionNav(title: strings("nav.hosts"), strings: strings, page: $model.page)
            Rectangle().fill(style.rule).frame(width: 1)
            page
        }
    }

    /// Содержимое выбранной страницы раздела.
    @ViewBuilder private var page: some View {
        switch model.page {
        case .hosts:
            VStack(alignment: .leading, spacing: 16) {
                searchRow
                actionRow
                groups
                hosts
                Spacer(minLength: 0)
            }
        case .keys: KeysView(model: model)
        case .forwarding: ForwardingView(model: model)
        case .snippets: SnippetsView(model: model)
        case .known: KnownHostsView(model: model).task { model.loadKnownHosts() }
        case .log: ConnectionLogView(model: model).task { await model.loadConnectionLog() }
        }
    }

    private var searchRow: some View {
        HStack(spacing: 10) {
            HStack(spacing: 8) {
                Text(">").foregroundStyle(style.muted)
                TextField(strings("hosts.search"), text: $model.query)
                    .textFieldStyle(.plain)
                    .font(style.font(12.5))
                    .foregroundStyle(style.text)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .overlay(Rectangle().stroke(style.text.opacity(0.3), lineWidth: 1))

            PhButton(strings("hosts.connect"), kind: .primary) {
                // Набрал user@host — подключился, ничего не сохраняя.
                if let host = model.parseQuickConnect(model.query) {
                    model.screen = .terminal
                    Task { await model.connect(to: host) }
                } else if let first = model.visibleHosts.first {
                    model.screen = .terminal
                    Task { await model.connect(to: first) }
                }
            }
        }
    }

    private var actionRow: some View {
        HStack(spacing: 10) {
            PhButton(strings("hosts.new")) { model.isAddingHost = true }
            PhButton(strings("hosts.import")) { model.importReport = model.importSSHConfig() }
            Spacer()
            if let report = model.importReport {
                Text(importSummary(report))
                    .font(style.font(11))
                    .foregroundStyle(report.skipped.isEmpty ? style.muted : style.warning)
            } else {
                Text(
                    model.selectedGroup == nil
                        ? strings("hosts.filterHint") : strings("hosts.clearFilter")
                )
                .font(style.font(11))
                .foregroundStyle(style.muted)
            }
        }
    }

    /// Итог импорта словами: сколько взяли и сколько не поняли.
    private func importSummary(_ report: AppModel.ImportReport) -> String {
        if report.added == 0, report.skipped.isEmpty { return "в ~/.ssh/config нечего импортировать" }
        var text = "добавлено \(report.added)"
        if !report.skipped.isEmpty { text += ", не распознано \(report.skipped.count)" }
        return text
    }

    private var groups: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label2(strings("hosts.groups"))
            let counts = model.book.counts()
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 4), spacing: 10) {
                ForEach(model.book.groups) { group in
                    Button {
                        model.selectedGroup = model.selectedGroup == group.id ? nil : group.id
                    } label: {
                        VStack(alignment: .leading, spacing: 3) {
                            HStack(spacing: 8) {
                                Rectangle()
                                    .fill(groupColour(group))
                                    .frame(width: 9, height: 9)
                                Text(group.name)
                                    .font(style.font(12.5))
                                    .foregroundStyle(style.bright)
                            }
                            Text("\(counts[group.id] ?? 0)")
                                .font(style.font(11))
                                .foregroundStyle(style.muted)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 12).padding(.vertical, 10)
                        .background(style.surface)
                        .overlay(
                            Rectangle().stroke(
                                model.selectedGroup == group.id ? style.accent : style.text.opacity(0.22),
                                lineWidth: 1
                            ))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    /// Мелкая деталь на карточке: значок и значение.
    private func detail(icon: String, text: String) -> some View {
        HStack(spacing: 3) {
            Text(icon).foregroundStyle(style.muted.opacity(0.7))
            Text(text).foregroundStyle(style.muted)
        }
    }

    private func groupColour(_ group: HostGroup) -> Color {
        guard let id = group.themeID else { return style.muted }
        return Color(BuiltInThemes.theme(id: id).ansi[9])
    }

    private var hosts: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label2("\(strings("hosts.all")) · \(model.visibleHosts.count)")
            if model.visibleHosts.isEmpty {
                Text(strings("hosts.empty"))
                    .font(style.font(12.5))
                    .foregroundStyle(style.muted)
            } else {
                LazyVGrid(
                    columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 10
                ) {
                    ForEach(model.visibleHosts) { host in
                        hostCard(host)
                    }
                }
            }
        }
    }

    private func hostCard(_ host: ServerHost) -> some View {
        let connected = model.selectedHost == host.id
        let profile = connected ? model.sessionState.profile : nil
        return Button {
            model.screen = .terminal
            Task { await model.connect(to: host) }
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                cardHeader(host, connected: connected, profile: profile)
                cardDetails(host, profile: profile)
                if !host.tags.isEmpty {
                    Text(host.tags.joined(separator: " · "))
                        .font(style.font(10.5)).foregroundStyle(style.muted).lineLimit(1)
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(style.surface)
            .overlay(
                Rectangle().stroke(
                    connected ? style.accent : style.text.opacity(0.22), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .contextMenu { cardMenu(host) }
    }

    private func cardHeader(
        _ host: ServerHost, connected: Bool, profile: HostProfile?
    ) -> some View {
        HStack(spacing: 11) {
            Text(host.osBadge)
                .font(style.font(10))
                .foregroundStyle(style.muted)
                .frame(width: 30, height: 30)
                .overlay(Rectangle().stroke(style.text.opacity(0.35), lineWidth: 1))
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(host.name).font(style.font(12.5)).foregroundStyle(style.bright)
                    if connected {
                        Text("●").font(style.font(9)).foregroundStyle(style.accent)
                    }
                    // Значок стоит рядом с настоящим аптаймом, а не вместо него.
                    if let uptime = profile?.uptimeSeconds,
                        let egg = model.eggs.unbreakableBadge(uptimeSeconds: uptime)
                    {
                        Text(strings(egg)).font(style.font(9.5)).foregroundStyle(style.warning)
                    }
                }
                Text("\(host.user)@\(host.address):\(host.port)")
                    .font(style.font(10.5)).foregroundStyle(style.muted).lineLimit(1)
            }
            Spacer(minLength: 0)
        }
    }

    /// Вторая строка живёт, только когда есть что сказать.
    private func cardDetails(_ host: ServerHost, profile: HostProfile?) -> some View {
        HStack(spacing: 10) {
            detail(icon: "→", text: model.book.reach(for: host).summary)
            if let group = model.book.group(for: host) {
                detail(icon: "■", text: group.name)
            }
            if let profile {
                detail(icon: "↑", text: ByteFormat.duration(seconds: profile.uptimeSeconds))
                if profile.containerCount > 0 {
                    detail(icon: "▣", text: "\(profile.containerCount)")
                }
                detail(icon: "⚿", text: "\(profile.authorizedKeyCount)")
            }
            Spacer(minLength: 0)
        }
        .font(style.font(10.5))
    }

    /// Правка и удаление живут здесь: сама карточка — это кнопка
    /// «подключиться», и путать одно с другим не стоит.
    @ViewBuilder private func cardMenu(_ host: ServerHost) -> some View {
        Button("подключиться") {
            model.screen = .terminal
            Task { await model.connect(to: host) }
        }
        Button("файлы") {
            model.screen = .files
            Task { await model.connect(to: host) }
        }
        Divider()
        Button("править…") { model.editingHost = host }
        Button("дублировать") { model.duplicate(host) }
        Divider()
        Button("удалить", role: .destructive) { model.pendingHostRemoval = host }
    }
}
