public import DockerKit
public import PhosphorCore
public import SwiftUI

/// Container list with the inspector beside it.
public struct DockerView: View {
    @Environment(\.style) private var style
    @Bindable var model: AppModel
    @State private var tab = "docker.logs"

    public init(model: AppModel) { self.model = model }

    private var strings: Strings { model.strings }
    private var selected: Container? {
        model.containers.first { $0.id == model.selectedContainer } ?? model.containers.first
    }

    public var body: some View {
        HStack(alignment: .top, spacing: 22) {
            list
            Rectangle().fill(style.rule).frame(width: 1)
            inspector
        }
    }

    private var list: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label2("\(strings("docker.containers")) · \(model.containers.count)")
                .padding(.bottom, 6)
            // The eclipse banner sits above the true list, never in place of it.
            if let egg = model.eggs.eclipseBanner(
                total: model.containers.count,
                down: model.containers.filter { $0.state != .running }.count
            ) {
                Text(strings(egg).uppercased())
                    .font(style.font(10.5)).tracking(2)
                    .foregroundStyle(style.danger)
                    .padding(.bottom, 4)
            }
            ForEach(model.containers) { container in
                Button {
                    model.selectedContainer = container.id
                } label: {
                    HStack(spacing: 8) {
                        Text(container.state == .running ? "●" : "○")
                            .foregroundStyle(dot(container))
                        Text(container.name)
                            .foregroundStyle(container.id == selected?.id ? style.bright : style.text)
                            .lineLimit(1)
                        Spacer(minLength: 0)
                    }
                    .font(style.font(12))
                    .padding(.horizontal, 6).padding(.vertical, 4)
                    .background(container.id == selected?.id ? style.surface : .clear)
                }
                .buttonStyle(.plain)
            }
            Spacer(minLength: 0)
        }
        .frame(width: 240, alignment: .leading)
    }

    private func dot(_ container: Container) -> Color {
        if container.isUnhealthy { return style.warning }
        return container.state == .running ? style.accent : style.warning
    }

    @ViewBuilder private var inspector: some View {
        if let container = selected {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 14) {
                    Text(container.name).font(style.font(15)).foregroundStyle(style.bright)
                    Text(container.image).font(style.font(12)).foregroundStyle(style.muted)
                    Text(container.status).font(style.font(12))
                        .foregroundStyle(container.isUnhealthy ? style.warning : style.muted)
                    Spacer()
                    PhButton(strings("docker.restart")) {}
                    PhButton(strings("docker.stop")) {}
                    PhButton(strings("docker.remove"), kind: .danger) {}
                }
                HStack(spacing: 18) {
                    ForEach(["docker.overview", "docker.logs", "docker.env"], id: \.self) { key in
                        Button {
                            tab = key
                        } label: {
                            Text(strings(key).uppercased())
                                .font(style.font(11)).tracking(1.2)
                                .foregroundStyle(tab == key ? style.bright : style.muted)
                                .padding(.bottom, 3)
                                .overlay(alignment: .bottom) {
                                    Rectangle().fill(tab == key ? style.accent : .clear).frame(height: 1)
                                }
                        }
                        .buttonStyle(.plain)
                    }
                }
                content(for: container)
                Spacer(minLength: 0)
            }
        } else {
            Text(strings("hosts.empty")).font(style.font(12.5)).foregroundStyle(style.muted)
        }
    }

    @ViewBuilder private func content(for container: Container) -> some View {
        switch tab {
        case "docker.overview":
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 3), spacing: 12) {
                ForEach(overview(container), id: \.0) { item in
                    VStack(alignment: .leading, spacing: 5) {
                        Label2(item.0)
                        Text(item.1).font(style.font(12)).foregroundStyle(style.bright)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12).padding(.vertical, 10)
                    .background(style.surface)
                }
            }
        case "docker.env":
            VStack(alignment: .leading, spacing: 4) {
                // Values of secret-looking names never leave the mask, in the
                // interface or in an MCP answer.
                ForEach(Redaction.apply(to: Self.demoEnvironment), id: \.name) { item in
                    HStack(spacing: 0) {
                        Text(item.name).foregroundStyle(style.text)
                        Text("=").foregroundStyle(style.muted)
                        Text(item.value).foregroundStyle(style.bright)
                    }
                    .font(style.font(12))
                }
                Text(strings("docker.secretsHidden"))
                    .font(style.font(11)).foregroundStyle(style.muted).padding(.top, 6)
            }
        default:
            VStack(alignment: .leading, spacing: 2) {
                ForEach(Self.demoLogs, id: \.0) { line in
                    Text(line.0)
                        .font(style.font(12))
                        .foregroundStyle(
                            line.1 == 0
                                ? style.text.opacity(0.85)
                                : line.1 == 1 ? style.warning : style.danger)
                }
            }
        }
    }

    private func overview(_ container: Container) -> [(String, String)] {
        [
            ("id", String(container.id.prefix(12))),
            ("образ", container.image),
            ("состояние", container.state.title),
            ("порты", container.ports.isEmpty ? "—" : container.ports),
            ("стек", container.project ?? "—"),
            ("health", container.health ?? "—"),
        ]
    }

    private static let demoEnvironment: [(name: String, value: String)] = [
        ("NODE_ENV", "production"),
        ("BILLING_URL", "https://billing.internal"),
        ("CONCURRENCY", "8"),
        ("DATABASE_PASSWORD", "hunter2"),
        ("API_KEY", "sk-live-4471"),
    ]

    private static let demoLogs: [(String, Int)] = [
        ("11:41:02Z  INFO  job 88f1 charge 1 290 RUB ok 412ms", 0),
        ("11:41:05Z  INFO  job 88f2 charge 590 RUB ok 388ms", 0),
        ("11:41:09Z  WARN  upstream billing timeout, retry 1/3", 1),
        ("11:41:12Z  WARN  upstream billing timeout, retry 2/3", 1),
        ("11:41:15Z  ERROR upstream billing unreachable, job deferred", 2),
        ("11:42:15Z  INFO  healthcheck failed (3/3) → unhealthy", 1),
    ]
}
