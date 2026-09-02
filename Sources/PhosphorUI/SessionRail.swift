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
            HStack {
                Label2(model.strings("term.sessions"))
                Spacer()
                Button { adding.toggle() } label: {
                    Image(systemName: "plus").font(.system(size: 11, weight: .bold))
                        .foregroundStyle(style.muted)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12).padding(.top, 12)

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
                Circle()
                    .fill(session.attached ? style.bright : style.muted.opacity(0.5))
                    .frame(width: 7, height: 7)
                VStack(alignment: .leading, spacing: 1) {
                    Text(session.name)
                        .font(style.font(12.5))
                        .foregroundStyle(active ? style.bright : style.text)
                        .lineLimit(1)
                    Text(windowsLabel(session.windows))
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
}
