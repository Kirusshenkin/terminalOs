public import HostsKit
public import MCPBridge
public import SwiftUI

/// Что делал ИИ и что ему разрешено.
///
/// Экран существует не для красоты: MCP-сервер над терминалом означает, что у
/// модели есть shell на боевых серверах, и единственный честный ответ на это —
/// показывать каждое её действие и держать переключатели на виду.
public struct ActivityView: View {
    @Environment(\.style) private var style
    @Bindable var model: AppModel
    private var strings: Strings { model.strings }

    public init(model: AppModel) { self.model = model }

    public var body: some View {
        HStack(alignment: .top, spacing: 22) {
            SectionNav(
                title: model.strings("tab.activity"),
                strings: model.strings, page: $model.activityPage)
            Rectangle().fill(style.rule).frame(width: 1)
            switch model.activityPage {
            case .journal: journal
            case .access: access
            case .tools: tools
            }
        }
        .task { await model.loadAudit() }
    }

    /// Что вообще может быть вызвано: список закрытый и короткий намеренно.
    private var tools: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label2("\(strings("act.tools")) · \(ToolCatalog.all.count)")
            Text(strings("act.toolsNote"))
                .font(style.font(11)).foregroundStyle(style.muted)
            HStack(spacing: 10) {
                Label2(strings("host.name")).frame(width: 210, alignment: .leading)
                Label2(strings("act.what")).frame(maxWidth: .infinity, alignment: .leading)
                Label2(strings("act.class")).frame(width: 90, alignment: .leading)
            }
            .padding(.top, 6).padding(.bottom, 4)
            .overlay(alignment: .bottom) { Rule() }

            ForEach(ToolCatalog.all) { tool in
                HStack(spacing: 10) {
                    Text(tool.name)
                        .foregroundStyle(style.text).frame(width: 210, alignment: .leading)
                    Text(tool.summary)
                        .foregroundStyle(style.muted)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text(tool.kind == .write ? strings("act.write") : strings("act.read"))
                        .foregroundStyle(tool.kind == .write ? style.warning : style.accent)
                        .frame(width: 90, alignment: .leading)
                }
                .font(style.font(12))
                .padding(.vertical, 4)
                .overlay(alignment: .bottom) {
                    Rectangle().fill(style.rule.opacity(0.4)).frame(height: 1)
                }
            }
            Spacer(minLength: 0)
        }
    }

    private var access: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label2(strings("act.perHost"))
            Text(strings("act.newHostOff"))
                .font(style.font(11)).foregroundStyle(style.muted)

            ForEach(model.book.hosts) { host in
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 8) {
                        Text(host.name).font(style.font(12.5)).foregroundStyle(style.bright)
                        Spacer()
                    }
                    HStack(spacing: 4) {
                        ForEach(MCPMode.allCases, id: \.self) { mode in
                            Button {
                                Task { await model.setMCPMode(mode, for: host) }
                            } label: {
                                Text(mode.title)
                                    .font(style.font(10))
                                    .padding(.horizontal, 7).padding(.vertical, 2)
                                    .foregroundStyle(
                                        model.mcpModes[host.id] == mode ? style.background : style.muted
                                    )
                                    .background(
                                        model.mcpModes[host.id] == mode ? tint(mode) : .clear
                                    )
                                    .overlay(
                                        Rectangle().stroke(
                                            model.mcpModes[host.id] == mode
                                                ? tint(mode)
                                                : style.text.opacity(0.25),
                                            lineWidth: 1))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(.vertical, 4)
            }

            Spacer(minLength: 0)

            VStack(alignment: .leading, spacing: 5) {
                Label2(strings("act.howToConnect"))
                // Три шага, а не одна команда: без режима на хосте мост
                // отвечает отказом, и человек считает, что он сломан.
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(["act.step1", "act.step2", "act.step3"], id: \.self) { key in
                        Text(strings(key))
                            .font(style.font(11.5))
                            .foregroundStyle(style.text)
                    }
                }
                .padding(.bottom, 4)
                Text(model.bridgeError ?? strings("act.bridgeUp"))
                    .font(style.font(11))
                    .foregroundStyle(model.bridgeError == nil ? style.muted : style.warning)
                Text(model.bridgeCommand)
                    .font(style.font(10.5))
                    .foregroundStyle(style.text.opacity(0.8))
                    .textSelection(.enabled)
                    .padding(.horizontal, 8).padding(.vertical, 6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(style.surface)
            }

            Text(strings("act.denyNote"))
                .font(style.font(11))
                .foregroundStyle(style.warning)
                .padding(.horizontal, 12).padding(.vertical, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(style.surface)
                .overlay(Rectangle().stroke(style.warning.opacity(0.4), lineWidth: 1))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Чем опаснее режим, тем заметнее цвет.
    private func tint(_ mode: MCPMode) -> Color {
        switch mode {
        case .disabled: style.muted
        case .readOnly: style.accent
        case .confirm: style.warning
        case .full: style.danger
        }
    }

    private var journal: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label2(strings("act.journal"))
                Spacer()
                Text(strings("act.appendOnly"))
                    .font(style.font(10.5)).foregroundStyle(style.muted)
            }
            if model.auditEntries.isEmpty {
                Text(strings("act.empty"))
                    .font(style.font(12)).foregroundStyle(style.muted)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(model.auditEntries.reversed()) { entry in
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 8) {
                                Text(entry.succeeded ? "✓" : "✗")
                                    .foregroundStyle(entry.succeeded ? style.accent : style.warning)
                                Text(entry.tool).foregroundStyle(style.bright)
                                Text(entry.hostName).foregroundStyle(style.muted)
                                Spacer()
                                Text(entry.time.formatted(date: .omitted, time: .standard))
                                    .foregroundStyle(style.muted)
                            }
                            .font(style.font(12))
                            if !entry.arguments.isEmpty {
                                Text(entry.arguments)
                                    .font(style.font(11)).foregroundStyle(style.text.opacity(0.7))
                            }
                            Text("\(entry.decision) · \(entry.summary)")
                                .font(style.font(11)).foregroundStyle(style.muted)
                        }
                        .padding(.bottom, 4)
                        .overlay(alignment: .bottom) {
                            Rectangle().fill(style.rule.opacity(0.5)).frame(height: 1)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}
