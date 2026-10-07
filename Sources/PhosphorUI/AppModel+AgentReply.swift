public import AppKit
public import Foundation
import PhosphorCore

/// Ответ ждущему агенту, не заходя в его панель (план §23).
///
/// Enter и Esc, а не «да/нет»: у агентов это общий язык меню выбора —
/// Enter принимает подсвеченное, Esc отказывается, — а буквы у каждого свои.
public enum AgentReply: Sendable, Equatable {
    case accept
    case decline
    /// Строка текста, затем Enter.
    case text(String)
}

@MainActor
extension AppModel {
    /// Длинный ответ — это уже работа в самой панели, а не реплика из рейла.
    static let replyLimit = 2_000

    /// Отправляет ответ в tmux-сессию агента. `false` — не дошло: канала нет
    /// или tmux не ответил; человек тогда заходит в панель сам.
    ///
    /// Из фона приложение не логинится: чужой спейс отвечает только по уже
    /// открытому каналу, как и опрос.
    @discardableResult
    public func reply(_ reply: AgentReply, to place: AgentPlace) async -> Bool {
        let succeeded: Bool
        switch place {
        case .local(nil):
            // Простой шелл без tmux живёт только в своей панели — адреса нет.
            return false
        case .local(let name?):
            guard let tmux = localTmuxPath,
                let command = Self.replyCommand(reply, session: name, tmux: Shell.quote(tmux))
            else { return false }
            // `&&`, а не `;`: «отправлено» только если вся цепочка tmux прошла.
            succeeded = await LocalTmux.run("{ \(command); } && echo sent") == "sent\n"
        case .remote(let id, let name):
            // С путями пакетов: на Мак-сервере tmux в /opt/homebrew/bin, а
            // неинтерактивный ssh этого пути не знает.
            guard let bare = Self.replyCommand(reply, session: name) else { return false }
            let command = Shell.withPackagePaths + bare
            if id == selectedHost, let session {
                succeeded = (try? await session.run(command))?.succeeded == true
            } else {
                succeeded = await spaceTransport(for: id)?.runIfConnected(command)?.succeeded == true
            }
        }
        if succeeded {
            // Ответили — агент больше не ждёт; опрос подтвердит или вернёт метку.
            waitingAgents.remove(place)
            NSApp?.dockTile.badgeLabel = waitingAgents.isEmpty ? nil : String(waitingAgents.count)
        }
        return succeeded
    }

    /// Команда tmux для ответа. Чистая функция. nil — отвечать нечем: пустой
    /// после чистки текст.
    ///
    /// Текст идёт через буфер tmux, а не `send-keys`: аргумент, кончающийся
    /// на `;`, tmux прочёл бы как разделитель команд. Управляющие символы
    /// выбрасываются — перевод строки в тексте отправил бы ответ раньше
    /// времени, а escape-последовательность могла бы нажать что угодно.
    static func replyCommand(_ reply: AgentReply, session: String, tmux: String = "tmux") -> String? {
        let target = Shell.quote(session + ":")
        switch reply {
        case .accept:
            return "\(tmux) send-keys -t \(target) Enter"
        case .decline:
            return "\(tmux) send-keys -t \(target) Escape"
        case .text(let raw):
            let printable = raw.unicodeScalars.filter { $0.value >= 0x20 && $0 != "\u{7F}" }
            let text = String(String(String.UnicodeScalarView(printable)).prefix(replyLimit))
            guard !text.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
            let buffer = "phosphor-reply"
            return "printf %s \(Shell.quote(text)) | \(tmux) load-buffer -b \(buffer) - && "
                + "\(tmux) paste-buffer -d -b \(buffer) -t \(target) && \(tmux) send-keys -t \(target) Enter"
        }
    }
}
