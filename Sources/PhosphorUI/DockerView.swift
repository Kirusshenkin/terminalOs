public import DockerKit
public import PhosphorCore
public import SessionKit
public import SwiftUI

/// Container list with the inspector beside it.
public struct DockerView: View {
    @Environment(\.style) private var style
    @Bindable var model: AppModel
    @State private var tab = "docker.logs"

    public init(model: AppModel) { self.model = model }

    private var strings: Strings { model.strings }
    private var containers: [Container] {
        model.sessionState.containers.isEmpty ? Self.demoContainers : model.sessionState.containers
    }

    private var selected: Container? {
        containers.first { $0.id == model.selectedContainer } ?? containers.first
    }

    /// Одна строка о том, что сейчас с хостом. Разные причины — разные подсказки.
    private var connectionNote: String? {
        switch model.sessionState.phase {
        case .idle: "нет подключения — показаны примерные данные"
        case .connecting, .probing: "подключаюсь…"
        case .ready: nil
        case .failed(let reason): reason
        }
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
            Label2("\(strings("docker.containers")) · \(containers.count)")
                .padding(.bottom, 6)
            if let connectionNote {
                Text(connectionNote)
                    .font(style.font(10.5))
                    .foregroundStyle(isFailure ? style.warning : style.muted)
                    .padding(.bottom, 4)
            }
            // The eclipse banner sits above the true list, never in place of it.
            if let egg = model.eggs.eclipseBanner(
                total: containers.count,
                down: containers.filter { $0.state != .running }.count
            ) {
                Text(strings(egg).uppercased())
                    .font(style.font(10.5)).tracking(2)
                    .foregroundStyle(style.danger)
                    .padding(.bottom, 4)
            }
            ForEach(containers) { container in
                Button {
                    model.selectedContainer = container.id
                } label: {
                    VStack(alignment: .leading, spacing: 1) {
                        HStack(spacing: 8) {
                            Text(container.state == .running ? "●" : "○")
                                .foregroundStyle(dot(container))
                            Text(container.name)
                                .foregroundStyle(
                                    container.id == selected?.id ? style.bright : style.text
                                )
                                .lineLimit(1)
                            Spacer(minLength: 0)
                            if let stats = model.sessionState.stats[container.name] {
                                Text(ByteFormat.percent(stats.cpu))
                                    .font(style.font(10.5))
                                    .foregroundStyle(stats.cpu > 0.5 ? style.warning : style.muted)
                            }
                        }
                        HStack(spacing: 6) {
                            Text(container.image).lineLimit(1)
                            if let stats = model.sessionState.stats[container.name] {
                                Text("· \(ByteFormat.size(stats.memoryUsed))")
                            }
                        }
                        .font(style.font(10))
                        .foregroundStyle(style.muted)
                        .padding(.leading, 16)
                    }
                    .font(style.font(12))
                    .padding(.horizontal, 6).padding(.vertical, 4)
                    .background(container.id == selected?.id ? style.surface : .clear)
                }
                .buttonStyle(.plain)
            }
            Spacer(minLength: 0)
        }
        .frame(width: 270, alignment: .leading)
    }

    private var isFailure: Bool {
        if case .failed = model.sessionState.phase { return true }
        return false
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
                    // Предлагаем только то, что имеет смысл в этом состоянии:
                    // команда, которую демон всё равно отвергнет, — это не кнопка.
                    ForEach(ContainerAction.available(for: container.state), id: \.self) { action in
                        PhButton(action.title, kind: action.isDestructive ? .danger : .normal) {
                            model.request(action, on: container)
                        }
                    }
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
                if let outcome = model.lastOutcome {
                    Text(outcome.message)
                        .font(style.font(11.5))
                        .foregroundStyle(outcome.succeeded ? style.muted : style.warning)
                }
                Spacer(minLength: 0)
            }
        } else {
            Text(strings("hosts.empty")).font(style.font(12.5)).foregroundStyle(style.muted)
        }
    }

    @ViewBuilder private func content(for container: Container) -> some View {
        switch tab {
        case "docker.overview":
            VStack(alignment: .leading, spacing: 12) {
                if let warning = exposedWarning(container) {
                    Text(warning)
                        .font(style.font(11.5)).foregroundStyle(style.warning)
                        .padding(.horizontal, 12).padding(.vertical, 8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(style.surface)
                        .overlay(Rectangle().stroke(style.warning.opacity(0.45), lineWidth: 1))
                }
                LazyVGrid(
                    columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 4),
                    spacing: 12
                ) {
                    ForEach(overview(container), id: \.0) { item in
                        VStack(alignment: .leading, spacing: 5) {
                            Label2(item.0)
                            Text(item.1)
                                .font(style.font(12)).foregroundStyle(style.bright)
                                .lineLimit(2)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 12).padding(.vertical, 10)
                        .background(style.surface)
                    }
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

    private func colour(level: Int) -> Color {
        switch level {
        case 1: style.warning
        case 2: style.danger
        default: style.text.opacity(0.85)
        }
    }

    /// Подсветка по уровню, без разбора формата: строки бывают любые.
    private static func level(of line: String) -> Int {
        let upper = line.uppercased()
        if upper.contains("ERROR") || upper.contains("FATAL") || upper.contains("PANIC") { return 2 }
        if upper.contains("WARN") { return 1 }
        return 0
    }

    private func overview(_ container: Container) -> [(String, String)] {
        let stats = model.sessionState.stats[container.name]
        let memory: String =
            stats.map {
                $0.memoryLimit > 0
                    ? "\(ByteFormat.size($0.memoryUsed)) из \(ByteFormat.size($0.memoryLimit))"
                    : ByteFormat.size($0.memoryUsed)
            } ?? "—"
        let share: String =
            stats.map {
                $0.memoryLimit > 0
                    ? ByteFormat.percent(Double($0.memoryUsed) / Double($0.memoryLimit)) : "—"
            } ?? "—"
        return [
            ("id", String(container.id.prefix(12))),
            ("образ", container.image),
            ("состояние", container.state.title),
            ("статус", container.status.isEmpty ? "—" : container.status),
            ("порты", container.ports.isEmpty ? "не опубликованы" : container.ports),
            ("стек", container.project ?? "вне стека"),
            ("health", container.health ?? "не объявлен"),
            ("cpu", stats.map { ByteFormat.percent($0.cpu) } ?? "—"),
            ("память", memory),
            ("доля лимита", share),
            ("процессов", stats.map { String($0.pids) } ?? "—"),
            ("хост", model.connectedHostName),
        ]
    }

    /// Порты, опубликованные наружу без привязки к 127.0.0.1, — это дыра мимо
    /// UFW: докер пишет правила в iptables сам. Показываем это прямо здесь.
    private func exposedWarning(_ container: Container) -> String? {
        guard !container.ports.isEmpty else { return nil }
        let published = container.ports
            .components(separatedBy: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { $0.contains("->") && !$0.contains("127.0.0.1") }
        guard !published.isEmpty else { return nil }
        return "порт открыт наружу мимо UFW: " + published.joined(separator: ", ")
    }

    private static let demoEnvironment: [(name: String, value: String)] = [
        ("NODE_ENV", "production"),
        ("BILLING_URL", "https://billing.internal"),
        ("CONCURRENCY", "8"),
        ("DATABASE_PASSWORD", "hunter2"),
        ("API_KEY", "sk-live-4471"),
    ]

    /// Показывается, пока нет подключения, чтобы окно не было пустым.
    /// Живые данные всегда важнее: как только сессия отвечает, витрина исчезает.
    private static let demoContainers: [Container] = [
        Container(
            id: "3f9a2c7e11b0", name: "api-gateway", image: "api:2.14", state: .running,
            status: "Up 6 days", ports: "127.0.0.1:8080->8080", project: "prod",
            health: "healthy"),
        Container(
            id: "77aa31ff90de", name: "worker-billing", image: "wrk:2.1", state: .running,
            status: "Up 2 hours (unhealthy)", project: "prod", health: "unhealthy"),
        Container(
            id: "1c0de55ab332", name: "migrator", image: "api:2.14", state: .exited,
            status: "Exited (0) 6 days ago", project: "prod"),
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
