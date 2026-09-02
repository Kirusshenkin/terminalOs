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

    private var current: String { model.terminalSession ?? "main" }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Спейсы: открытые хосты. Между ними переключаешься, tmux на каждом
            // продолжает работать — herdr-мысль «несколько рабочих мест сразу».
            HStack {
                Label2(model.strings("term.spaces"))
                Spacer()
                Button { model.screen = .hosts } label: {
                    Image(systemName: "plus").font(.system(size: 11, weight: .bold))
                        .foregroundStyle(style.muted)
                }
                .buttonStyle(.plain)
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
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(spaces) { host in
                        spaceRow(host)
                    }
                }
                .padding(.horizontal, 8)
            }

            // Сессии есть только у подключённого хоста: у локального шелла
            // серверных tmux-сессий нет.
            if model.session != nil {
                Rectangle().fill(style.rule.opacity(0.5)).frame(height: 1)
                    .padding(.horizontal, 12)

                HStack {
                    Label2(model.strings("term.sessions"))
                    Spacer()
                    Button { adding.toggle() } label: {
                        Image(systemName: "plus").font(.system(size: 11, weight: .bold))
                            .foregroundStyle(style.muted)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 12)

                if adding { editor }

                ScrollView {
                    VStack(alignment: .leading, spacing: 2) {
                        // «main» есть всегда: это сессия по умолчанию, даже если
                        // список с сервера ещё не пришёл.
                        ForEach(rows) { session in
                            row(session)
                        }
                    }
                    .padding(.horizontal, 8)
                }
            }
            Spacer(minLength: 0)

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
    }

    /// Открытые спейсы как хосты; неизвестные id (хост удалили) отсеиваем.
    private var spaces: [ServerHost] {
        model.spaces.compactMap { id in model.book.hosts.first { $0.id == id } }
    }

    private func spaceRow(_ host: ServerHost) -> some View {
        let active = host.id == model.selectedHost
        return Button {
            model.switchSpace(host.id)
        } label: {
            HStack(spacing: 8) {
                // Активный спейс — яркая точка; остальные откреплены, но их
                // tmux жив, поэтому не гаснут в ноль.
                Circle()
                    .fill(active ? style.bright : style.muted.opacity(0.6))
                    .frame(width: 7, height: 7)
                VStack(alignment: .leading, spacing: 1) {
                    Text(host.name)
                        .font(style.font(12.5))
                        .foregroundStyle(active ? style.bright : style.text)
                        .lineLimit(1)
                    Text("\(host.user)@\(host.address)")
                        .font(style.font(10)).foregroundStyle(style.muted).lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8).padding(.vertical, 6)
            .background(active ? style.text.opacity(0.08) : .clear)
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button(model.strings("term.closeSpace")) { model.closeSpace(host.id) }
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

    private func row(_ session: AppModel.TmuxSession) -> some View {
        let active = session.name == current
        return Button {
            model.attachSession(session.name)
        } label: {
            HStack(spacing: 8) {
                // Цвет точки — статус сессии: работа/покой/ждёт ввода.
                Circle()
                    .fill(statusColour(session.status))
                    .frame(width: 7, height: 7)
                VStack(alignment: .leading, spacing: 1) {
                    Text(session.name)
                        .font(style.font(12.5))
                        .foregroundStyle(active ? style.bright : style.text)
                        .lineLimit(1)
                    Text("\(statusLabel(session.status)) · \(windowsLabel(session.windows))")
                        .font(style.font(10)).foregroundStyle(style.muted)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8).padding(.vertical, 6)
            .background(active ? style.text.opacity(0.08) : .clear)
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button(model.strings("term.killSession"), role: .destructive) {
                Task { await model.killSession(session.name) }
            }
        }
    }

    private var editor: some View {
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
            .buttonStyle(.plain)
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
