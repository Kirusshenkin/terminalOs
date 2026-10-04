public import HostsKit
public import SwiftUI

/// Рейл постоянных сессий во вкладке «Терминал».
///
/// По духу herdr: сессии живут на сервере в tmux, а здесь виден их список со
/// статусом — к какой подключиться, какую завести, какую снять. Отключиться от
/// сессии не значит убить её: она продолжает работать на хосте.
struct SessionRail: View {
    @Environment(\.style) private var style
    @Bindable var model: AppModel
    @State private var adding = false
    @State private var addingLocal = false

    private var current: String { model.terminalSession ?? "main" }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Этот Мак — такое же рабочее место, как сервер, и стоит в том же
            // списке: у herdr локальные пространства не отдельная сущность.
            localGroup
            Rectangle().fill(style.rule.opacity(0.5)).frame(height: 1)
                .padding(.horizontal, 12)

            // Спейсы: открытые хосты. Между ними переключаешься, tmux на каждом
            // продолжает работать — herdr-мысль «несколько рабочих мест сразу».
            HStack {
                Label2(model.strings("term.spaces"))
                Spacer()
                Button {
                    model.screen = .hosts
                } label: {
                    Image(systemName: "plus").font(.system(size: 11, weight: .bold))
                        .foregroundStyle(style.muted)
                }
                .buttonStyle(PressFeedback())
                .accessibilityLabel(model.strings("nav.addHost"))
            }
            .padding(.horizontal, 12).padding(.top, 12)

            if spaces.isEmpty {
                // Ни одного открытого спейса: подсказываем, откуда они берутся,
                // а не оставляем пустоту, в которой непонятно, что делать.
                Text(model.strings("term.noSpaces"))
                    .font(style.font(11)).foregroundStyle(style.muted)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 12)
            } else {
                // Сессии живут под своим хостом, и видны у всех спейсов сразу:
                // herdr-пульт — это все агенты на одном экране, а не только те,
                // в чей хост сейчас смотришь.
                ScrollView {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(spaces) { host in
                            spaceRow(host)
                            spaceSessions(host)
                        }
                    }
                    .padding(.horizontal, 8)
                }
            }
            Spacer(minLength: 0)

            // Питомец живёт в пустом низу рейла, а не поверх вывода терминала:
            // там он закрывал строки. Выбрать или выключить — в настройках.
            if model.petVisible {
                PetCorner(pet: $model.pet, showsPicker: false)
                    .frame(maxWidth: .infinity)
                    .clipped()
            }

            // Тумблер постоянства — рядом с сессиями, где он и осмыслен.
            Toggle(isOn: $model.persistentSessions) {
                Text(model.strings("term.persist"))
                    .font(style.font(11)).foregroundStyle(style.muted)
            }
            .toggleStyle(.switch)
            .tint(style.bright)
            .padding(.horizontal, 12).padding(.bottom, 12)
        }
        .frame(width: 210)
        .background(style.surface.opacity(0.4))
        .task(id: model.selectedHost) { await model.loadSessions() }
        .task(id: model.terminalSession) { await model.loadSessions() }
        // Сессии этого Мака — сразу при входе, дальше их обновляет слежение.
        .task { await model.loadLocalSessions() }
        .task { model.startSessionWatch() }
    }

    // MARK: - Этот Мак

    /// Локальное рабочее место: постоянные сессии этого Мака, если здесь есть
    /// tmux, и обычный шелл, если нет.
    @ViewBuilder private var localGroup: some View {
        HStack {
            Label2(model.strings("term.thisMac"))
            Spacer()
            if model.localTmuxPath != nil {
                Button {
                    addingLocal.toggle()
                } label: {
                    Image(systemName: "plus").font(.system(size: 11, weight: .bold))
                        .foregroundStyle(style.muted)
                }
                .buttonStyle(PressFeedback())
                .accessibilityLabel(model.strings("nav.newSession"))
            }
        }
        .padding(.horizontal, 12).padding(.top, 12)

        if model.localTmuxPath == nil {
            // Без tmux локальная сессия не переживёт даже закрытия вкладки.
            // Говорим это прямо и сразу даём, что сделать.
            Text(model.strings("term.noLocalTmux"))
                .font(style.font(11)).foregroundStyle(style.warning)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 12)
        }

        if addingLocal { editor(create: createLocal) }

        VStack(alignment: .leading, spacing: 2) {
            // Обычный шелл есть всегда: он не переживает перезапуск, но он и
            // не обещает этого.
            localRow(
                name: nil, title: model.strings("term.plainShell"), status: model.plainShell?.status,
                agent: model.plainShell?.agent)
            ForEach(model.localSessions) { session in
                localRow(
                    name: session.name, title: session.name, status: session.status,
                    agent: session.agent)
            }
        }
        .padding(.horizontal, 8)
    }

    private func localRow(
        name: String?, title: String, status: AppModel.SessionStatus?, agent: CodingAgent?
    ) -> some View {
        SessionLine(
            model: model, place: .local(name), title: title,
            subtitle: status.map { status in
                agent.map { "\($0.title) · \(statusLabel(status))" } ?? statusLabel(status)
            },
            dot: status.map(statusColour) ?? style.muted.opacity(0.5),
            active: model.localFocused && model.localSession == name
        ) {
            model.focusLocal(name)
        }
        .contextMenu {
            if let name {
                Button(model.strings("term.killSession"), role: .destructive) {
                    Task { await model.killLocalSession(name) }
                }
            }
        }
    }

    private func createLocal() {
        guard !model.newSessionName.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        model.createLocalSession()
        addingLocal = false
    }

    // MARK: - Спейсы

    /// Открытые спейсы как хосты; неизвестные id (хост удалили) отсеиваем.
    private var spaces: [ServerHost] {
        model.spaces.compactMap { id in model.book.hosts.first { $0.id == id } }
    }

    /// Спейс, в который смотрит терминал и с которым есть живое соединение.
    private func isLive(_ host: ServerHost) -> Bool {
        host.id == model.selectedHost && model.session != nil
    }

    private func spaceRow(_ host: ServerHost) -> some View {
        let active = host.id == model.selectedHost && !model.localFocused
        let offline = !isLive(host) && model.spaceSnapshots[host.id] == .offline
        return HStack(spacing: 0) {
            Button {
                model.switchSpace(host.id)
            } label: {
                HStack(spacing: 8) {
                    // Активный спейс — яркая точка; остальные откреплены, но их
                    // tmux жив, поэтому не гаснут в ноль.
                    Circle()
                        .fill(active ? style.bright : style.muted.opacity(offline ? 0.25 : 0.6))
                        .frame(width: 7, height: 7)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(host.name)
                            .font(style.font(12.5))
                            .foregroundStyle(active ? style.bright : style.text)
                            .lineLimit(1)
                        // Без связи говорим, что делать, а не показываем адрес:
                        // из фона мы не логинимся, подключает клик.
                        Text(offline ? model.strings("term.offline") : "\(host.user)@\(host.address)")
                            .font(style.font(10)).foregroundStyle(style.muted).lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 8).padding(.vertical, 6)
                .contentShape(Rectangle())
            }
            .buttonStyle(PressFeedback())
            // Новая сессия заводится в живом спейсе: в чужой хост без
            // соединения её не завести.
            if isLive(host) {
                Button {
                    adding.toggle()
                } label: {
                    Image(systemName: "plus").font(.system(size: 11, weight: .bold))
                        .foregroundStyle(style.muted)
                        .padding(.horizontal, 6)
                }
                .buttonStyle(PressFeedback())
                .accessibilityLabel(model.strings("nav.newSession"))
            }
        }
        .background(active ? style.text.opacity(0.08) : .clear)
        .contextMenu {
            Button(model.strings("term.closeSpace")) { model.closeSpace(host.id) }
        }
    }

    /// Сессии спейса под его строкой: у живого — свежий список и поле новой
    /// сессии, у остальных — снимок фонового опроса.
    @ViewBuilder private func spaceSessions(_ host: ServerHost) -> some View {
        if isLive(host) {
            if !model.hasTmux {
                // Без tmux постоянных сессий не бывает: шелл каждый раз
                // начинается с нуля. Говорим это словами и сразу даём, что
                // сделать, — иначе пустой список выглядит поломкой.
                Text(model.strings("term.noTmux"))
                    .font(style.font(11)).foregroundStyle(style.warning)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.leading, 22).padding(.trailing, 4)
            }
            if adding { editor(create: create) }
            ForEach(rows) { session in
                row(session, host: host.id, active: session.name == current && !model.localFocused)
            }
        } else if case .sessions(let list) = model.spaceSnapshots[host.id] {
            ForEach(list) { session in
                row(session, host: host.id, active: false)
            }
        }
    }

    /// Сессии с сервера плюс гарантированная текущая, без повторов.
    private var rows: [AppModel.TmuxSession] {
        var seen = Set(model.liveSessions.map(\.name))
        var result = model.liveSessions
        if !seen.contains(current) {
            result.insert(
                AppModel.TmuxSession(name: current, windows: 1, attached: true), at: 0)
            seen.insert(current)
        }
        return result
    }

    private func row(_ session: AppModel.TmuxSession, host: ServerHost.ID, active: Bool) -> some View {
        SessionLine(
            model: model, place: .remote(host, session.name), title: session.name,
            subtitle: subtitle(session), dot: statusColour(session.status), active: active
        ) {
            model.jump(to: .remote(host, session.name))
        }
        .padding(.leading, 14)
        .contextMenu {
            // Снять сессию можно только там, куда есть живое соединение.
            if host == model.selectedHost, model.session != nil {
                Button(model.strings("term.killSession"), role: .destructive) {
                    Task { await model.killSession(session.name) }
                }
            }
        }
    }

    /// Поле ввода имени новой сессии. Одно на оба списка: заводится сессия
    /// там, откуда нажали «+», а выглядеть по-разному этому незачем.
    private func editor(create: @escaping () -> Void) -> some View {
        HStack(spacing: 6) {
            TextField(model.strings("term.sessionName"), text: $model.newSessionName)
                .textFieldStyle(.plain)
                .font(style.font(12))
                .foregroundStyle(style.text)
                .onSubmit(create)
            Button(action: create) {
                Image(systemName: "return").font(.system(size: 10, weight: .bold))
                    .foregroundStyle(style.bright)
            }
            .buttonStyle(PressFeedback())
            .accessibilityLabel(model.strings("nav.createSession"))
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .overlay(Rectangle().stroke(style.text.opacity(0.3), lineWidth: 1))
        .padding(.horizontal, 12)
    }

    private func create() {
        guard !model.newSessionName.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        model.createSession()
        adding = false
    }

    /// Вторая строка сессии. Если в ней живёт кодирующий агент — пишем его имя
    /// и состояние: «Claude Code ждёт» говорит больше, чем «работает · 2 окна».
    private func subtitle(_ session: AppModel.TmuxSession) -> String {
        if let agent = session.agent {
            return "\(agent.title) · \(statusLabel(session.status))"
        }
        return "\(statusLabel(session.status)) · \(windowsLabel(session.windows))"
    }

    private func windowsLabel(_ count: Int) -> String {
        "\(count) \(model.strings(count == 1 ? "term.window" : "term.windows"))"
    }

    private func statusColour(_ status: AppModel.SessionStatus) -> Color {
        switch status {
        case .working: style.bright
        case .blocked: style.warning
        case .idle: style.muted.opacity(0.5)
        }
    }

    private func statusLabel(_ status: AppModel.SessionStatus) -> String {
        model.strings("term.status.\(status.rawValue)")
    }
}

/// Строка сессии в рейле: точка статуса, имя, агент — и превью экрана при
/// наведении, чтобы понять, о чём агент спрашивает, не подключаясь к нему.
private struct SessionLine: View {
    @Environment(\.style) private var style
    let model: AppModel
    let place: AppModel.AgentPlace
    let title: String
    let subtitle: String?
    let dot: Color
    let active: Bool
    let action: () -> Void

    @State private var preview: [String]?
    @State private var showing = false
    @State private var hover: Task<Void, Never>?

    /// Сколько держать курсор, прежде чем показать превью. Это порог
    /// намерения, а не ожидание готовности: проведённая мимо мышь не должна
    /// дёргать сервер и открывать всплывашку.
    private static let hoverDelay = Duration.milliseconds(450)

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Circle().fill(dot).frame(width: 7, height: 7)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(style.font(12.5))
                        .foregroundStyle(active ? style.bright : style.text)
                        .lineLimit(1)
                    if let subtitle {
                        Text(subtitle)
                            .font(style.font(10)).foregroundStyle(style.muted).lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8).padding(.vertical, 6)
            .background(active ? style.text.opacity(0.08) : .clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressFeedback())
        .onHover { inside in
            hover?.cancel()
            guard inside, !active else {
                showing = false
                return
            }
            hover = Task {
                // Отмена — это ушедший курсор: показывать уже нечего.
                guard (try? await Task.sleep(for: Self.hoverDelay)) != nil else { return }
                let lines = await model.preview(place)
                guard !Task.isCancelled, let lines, !lines.isEmpty else { return }
                preview = lines
                showing = true
            }
        }
        .popover(isPresented: $showing, arrowEdge: .trailing) {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array((preview ?? []).enumerated()), id: \.offset) { _, line in
                    Text(line.isEmpty ? " " : line)
                        .font(style.font(11))
                        .foregroundStyle(style.text)
                        .lineLimit(1)
                }
            }
            .padding(12)
            .frame(width: 460, alignment: .leading)
            .background(style.surface)
        }
    }
}
