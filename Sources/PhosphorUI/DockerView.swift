public import DockerKit
public import PhosphorCore
public import SessionKit
public import SwiftUI

/// Container list with the inspector beside it.
public struct DockerView: View {
    @Environment(\.style) private var style
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Bindable var model: AppModel
    @State private var tab = "docker.logs"

    public init(model: AppModel) { self.model = model }

    private var strings: Strings { model.strings }
    /// Только то, что действительно ответил сервер. Ни одной придуманной строки:
    /// пустой список честнее выдуманного.
    private var containers: [Container] { model.sessionState.containers }

    private var selected: Container? {
        containers.first { $0.id == model.selectedContainer } ?? containers.first
    }

    /// Одна строка о том, что сейчас с хостом. Разные причины — разные подсказки.
    private var connectionNote: String? {
        switch model.sessionState.phase {
        case .idle: strings("dock.noHost")
        case .connecting, .probing: strings("dock.connecting")
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

    @ViewBuilder private var list: some View {
        if model.session == nil {
            HostPicker(
                model: model,
                title: strings("docker.containers"),
                note: strings("dock.pickNote")
            )
            .frame(width: 250)
        } else {
            liveList
        }
    }

    private var liveList: some View {
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
        case "docker.overview": overviewPage(container)
        case "docker.env": environmentPage
        default: logsPage
        }
    }

    /// Двенадцать полей и предупреждение о порте наружу, если оно уместно.
    private func overviewPage(_ container: Container) -> some View {
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
                            .font(style.font(12)).foregroundStyle(style.bright).lineLimit(2)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12).padding(.vertical, 10)
                    .background(style.surface)
                }
            }
        }
    }

    private var environmentPage: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Значения переменных с секретными именами не покидают маску —
            // ни на экране, ни в ответе MCP.
            ForEach(model.containerEnvironment, id: \.name) { item in
                HStack(spacing: 0) {
                    Text(item.name).foregroundStyle(style.text)
                    Text("=").foregroundStyle(style.muted)
                    Text(item.value).foregroundStyle(style.bright)
                }
                .font(style.font(12))
            }
            if let note = model.containerEnvironmentNote {
                Text(note).font(style.font(11.5)).foregroundStyle(style.muted)
            }
            Text(strings("docker.secretsHidden"))
                .font(style.font(11)).foregroundStyle(style.muted).padding(.top, 6)
        }
        .task(id: selected?.id) {
            guard let selected else { return }
            await model.loadEnvironment(for: selected)
        }
    }

    @ViewBuilder private var logsPage: some View {
        let live = model.logs.elements
        ScrollView {
            VStack(alignment: .leading, spacing: 2) {
                if live.isEmpty {
                    Text(model.session == nil ? strings("dock.pickShort") : strings("dock.noLogs"))
                        .font(style.font(11.5)).foregroundStyle(style.muted)
                } else {
                    // Появление новой строки — по выбору человека: подъём,
                    // проявление или ничего. Двигается только сама строка.
                    ForEach(live) { line in
                        Text(line.text)
                            .font(style.font(12))
                            .foregroundStyle(colour(level: Self.level(of: line.text)))
                            .textSelection(.enabled)
                            .transition(arrival)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .animation(arrivalAnimation, value: live.last?.id)
        }
    }

    /// Как приходит новая строка.
    private var arrival: AnyTransition {
        guard !reduceMotion, model.motion != .off else { return .identity }
        switch model.logMotion {
        case .rise: return .opacity.combined(with: .offset(y: 5))
        case .fade: return .opacity
        case .none: return .identity
        }
    }

    private var arrivalAnimation: Animation? {
        guard !reduceMotion, model.motion != .off, model.logMotion != .none else { return nil }
        return .easeOut(duration: 0.18 * model.motion.scale)
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
        if upper.contains("ERROR") || upper.contains("FATAL") || upper.contains("PANIC") {
            return 2
        }
        if upper.contains("WARN") { return 1 }
        return 0
    }

    private func overview(_ container: Container) -> [(String, String)] {
        let stats = model.sessionState.stats[container.name]
        let memory: String =
            stats.map {
                $0.memoryLimit > 0
                    ? "\(ByteFormat.size($0.memoryUsed)) \(strings("common.of")) \(ByteFormat.size($0.memoryLimit))"
                    : ByteFormat.size($0.memoryUsed)
            } ?? "—"
        let share: String =
            stats.map {
                $0.memoryLimit > 0
                    ? ByteFormat.percent(Double($0.memoryUsed) / Double($0.memoryLimit)) : "—"
            } ?? "—"
        return [
            ("id", String(container.id.prefix(12))),
            (strings("dock.image"), container.image),
            (strings("dock.state"), container.state.title),
            (strings("dock.status"), container.status.isEmpty ? "—" : container.status),
            (strings("dock.ports"), container.ports.isEmpty ? strings("dock.noPorts") : container.ports),
            (strings("dock.stack"), container.project ?? strings("dock.noStack")),
            ("health", container.health ?? strings("dock.undeclared")),
            ("cpu", stats.map { ByteFormat.percent($0.cpu) } ?? "—"),
            (strings("mon.memory"), memory),
            (strings("dock.limitShare"), share),
            (strings("dock.processCount"), stats.map { String($0.pids) } ?? "—"),
            (strings("dock.host"), model.connectedHostName),
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
        return strings("dock.exposed") + published.joined(separator: ", ")
    }

}
