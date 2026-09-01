public import HostsKit
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
            navigation
            Rectangle().fill(style.rule).frame(width: 1)
            VStack(alignment: .leading, spacing: 16) {
                searchRow
                actionRow
                groups
                hosts
                Spacer(minLength: 0)
            }
        }
    }

    private var navigation: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label2("— \(strings("nav.hosts")) —")
                .padding(.bottom, 6)
            ForEach(
                ["nav.hosts", "nav.keys", "nav.forwarding", "nav.snippets", "nav.known", "nav.log"],
                id: \.self
            ) { key in
                HStack(spacing: 6) {
                    Text(key == "nav.hosts" ? "▸" : " ")
                    Text(strings(key))
                }
                .font(style.font(12.5))
                .foregroundStyle(key == "nav.hosts" ? style.bright : style.text)
            }
        }
        .frame(width: 168, alignment: .leading)
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

            PhButton(strings("hosts.connect"), kind: .primary) {}
        }
    }

    private var actionRow: some View {
        HStack(spacing: 10) {
            PhButton(strings("hosts.new")) {}
            PhButton(strings("hosts.import")) {}
            Spacer()
            Text(model.selectedGroup == nil ? strings("hosts.filterHint") : strings("hosts.clearFilter"))
                .font(style.font(11))
                .foregroundStyle(style.muted)
        }
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
        Button {
            model.selectedHost = host.id
            model.screen = .terminal
        } label: {
            HStack(spacing: 11) {
                Text(host.osBadge)
                    .font(style.font(10))
                    .foregroundStyle(style.muted)
                    .frame(width: 30, height: 30)
                    .overlay(Rectangle().stroke(style.text.opacity(0.35), lineWidth: 1))
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(host.name)
                            .font(style.font(12.5))
                            .foregroundStyle(style.bright)
                        // The badge stands next to the real uptime, never
                        // instead of it.
                        if let egg = model.eggs.unbreakableBadge(uptimeSeconds: 400 * 86_400),
                            host.name.hasSuffix("s2")
                        {
                            Text(strings(egg))
                                .font(style.font(10))
                                .foregroundStyle(style.warning)
                        }
                    }
                    Text(host.tags.joined(separator: ", "))
                        .font(style.font(11))
                        .foregroundStyle(style.muted)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12).padding(.vertical, 10)
            .background(style.surface)
            .overlay(
                Rectangle().stroke(
                    model.selectedHost == host.id ? style.accent : style.text.opacity(0.22),
                    lineWidth: 1
                ))
        }
        .buttonStyle(.plain)
    }
}
