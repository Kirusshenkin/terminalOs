public import Foundation
public import HostsKit

/// Как именно вызывается `ssh`.
///
/// Одно место на всё приложение: команды транспорта и интерактивный шелл
/// терминала обязаны идти одинаково и по одному соединению. Разъехавшиеся
/// настройки — это второй логин, второй Touch ID и разное поведение там, где
/// пользователь ждёт одинакового.
public enum SSHInvocation {
    public static let executable = "/usr/bin/ssh"

    public static func arguments(
        host: ServerHost, reach: Reach, controlPath: String
    ) -> [String] {
        var arguments = [
            // Мультиплексирование: первый вызов логинится, остальные едут по
            // тому же сокету.
            "-o", "ControlMaster=auto",
            "-o", "ControlPath=\(controlPath)",
            "-o", "ControlPersist=120",
            // Смена ключа хоста — блок, а не вопрос.
            "-o", "StrictHostKeyChecking=yes",
            "-o", "ConnectTimeout=8",
            // Terrapin (CVE-2023-48795) применим к ChaCha20-Poly1305 и к CBC с
            // Encrypt-then-MAC. AES-GCM впереди обходит его на серверах, где он
            // поддерживается.
            "-o", "Ciphers=aes256-gcm@openssh.com,aes128-gcm@openssh.com,aes256-ctr,aes128-ctr",
            // Проброс агента выключен: на скомпрометированном хосте им
            // подписывают что угодно от твоего имени.
            "-o", "ForwardAgent=no",
            "-p", String(host.port),
        ]
        if case .socks(let proxyHost, let proxyPort) = reach {
            // Имя хоста уходит прокси целиком, чтобы DNS резолвился на его
            // стороне: ни утечки, ни «у меня этот домен не резолвится».
            arguments += [
                "-o",
                "ProxyCommand=/usr/bin/nc -x \(proxyHost):\(proxyPort) -X 5 %h %p",
            ]
        }
        return arguments
    }

    /// Аргументы для интерактивного шелла: то же самое плюс запрос PTY.
    ///
    /// Если задано имя tmux-сессии — шелл открывается внутри неё: `-A` значит
    /// «подключиться к существующей или создать». Так сессия живёт на сервере и
    /// переживает закрытие приложения или обрыв сети: при следующем заходе мы
    /// подключаемся к той же живой сессии, а не начинаем с нуля. Если tmux на
    /// сервере нет — молча откатываемся на обычный логин-шелл, а не падаем.
    public static func shellArguments(
        host: ServerHost, reach: Reach, controlPath: String, tmuxSession: String? = nil
    ) -> [String] {
        var result =
            arguments(host: host, reach: reach, controlPath: controlPath)
            + ["-t", "\(host.user)@\(host.address)"]
        if let tmuxSession, let name = tmuxSessionName(tmuxSession) {
            // exec, чтобы tmux (или откат) стал самим шеллом, а не его ребёнком.
            result.append(
                "command -v tmux >/dev/null 2>&1 && exec tmux new-session -A -s \(name) "
                    + "|| exec \"${SHELL:-/bin/sh}\" -l")
        }
        return result
    }

    /// Имя tmux-сессии из произвольной строки: tmux запрещает точки и двоеточия
    /// в именах, поэтому оставляем только безопасные символы. Пусто — значит имя
    /// негодное, и tmux лучше не запускать, чем запускать с мусором.
    public static func tmuxSessionName(_ raw: String) -> String? {
        let allowed = CharacterSet(charactersIn:
            "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_")
        let cleaned = String(raw.unicodeScalars.map { allowed.contains($0) ? Character($0) : "-" })
            .prefix(60)
        let trimmed = cleaned.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return trimmed.isEmpty ? nil : trimmed
    }

    public static func target(_ host: ServerHost) -> String {
        "\(host.user)@\(host.address)"
    }
}
