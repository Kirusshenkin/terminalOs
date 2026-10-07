public import Foundation
public import HostsKit
import PhosphorCore

/// Как именно вызывается `ssh`.
///
/// Одно место на всё приложение: команды транспорта и интерактивный шелл
/// терминала обязаны идти одинаково и по одному соединению. Разъехавшиеся
/// настройки — это второй логин, второй Touch ID и разное поведение там, где
/// пользователь ждёт одинакового.
public enum SSHInvocation {
    public static let executable = "/usr/bin/ssh"

    /// Управляющий сокет хоста. Один на хост, чтобы и сам хост, и прыжок через
    /// него как через бастион ехали по одному соединению.
    public static func controlPath(for host: ServerHost) -> String {
        // Socket names have a hard length limit, so the identifier is hashed.
        NSTemporaryDirectory() + "phosphor-\(host.id.uuidString.prefix(8)).sock"
    }

    public static func arguments(
        host: ServerHost, route: Route, controlPath: String
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
        if let key = host.identityFile, !key.isEmpty {
            // Только названный ключ: без `IdentitiesOnly` ssh сперва перебрал бы
            // агент и ключи по умолчанию, и сервер с жёстким `MaxAuthTries`
            // закрыл бы дверь раньше, чем дошла очередь до нужного.
            arguments += ["-i", key, "-o", "IdentitiesOnly=yes"]
        }
        if route.problem != nil {
            // Сломанная цепочка бастионов закрывается, а не обходится: без
            // ProxyCommand ssh пошёл бы напрямую, мимо выбранного пути.
            arguments += ["-o", "ProxyCommand=/usr/bin/false"]
        } else if let bastion = route.bastions.last {
            arguments += ["-o", "ProxyCommand=\(jumpCommand(through: bastion, route: route))"]
        } else if case .socks(let proxyHost, let proxyPort) = route.entry {
            // Имя хоста уходит прокси целиком, чтобы DNS резолвился на его
            // стороне: ни утечки, ни «у меня этот домен не резолвится».
            arguments += [
                "-o",
                "ProxyCommand=/usr/bin/nc -x \(proxyHost):\(proxyPort) -X 5 %h %p",
            ]
        }
        return arguments
    }

    /// Вложенный ssh до бастиона, который отдаёт свой stdio как канал к цели.
    ///
    /// Не `-J`: тот не умеет передать бастиону его ключ, его прокси и его
    /// сокет. Здесь бастион собирается тем же `arguments`, что и прямой вход
    /// на него, — с остатком цепочки, если бастионов несколько. `ControlMaster=no`
    /// стоит первым: открытое соединение с бастионом переиспользуется, но
    /// новое мастером не становится — его жизнь привязана к цели.
    static func jumpCommand(through bastion: ServerHost, route: Route) -> String {
        let rest = Route(entry: route.entry, bastions: Array(route.bastions.dropLast()))
        let nested =
            [executable, "-o", "ControlMaster=no"]
            + arguments(host: bastion, route: rest, controlPath: controlPath(for: bastion))
        // ssh раскрывает %-токены в ProxyCommand один раз, поэтому % внутри
        // вложенных аргументов удваивается: их %h и %p — для вложенного ssh.
        let quoted = nested.map { Shell.quote($0).replacingOccurrences(of: "%", with: "%%") }
        let target = Shell.quote(self.target(bastion)).replacingOccurrences(of: "%", with: "%%")
        return Shell.line(quoted + ["-W", "%h:%p", target])
    }

    /// Аргументы для интерактивного шелла: то же самое плюс запрос PTY.
    ///
    /// Если задано имя tmux-сессии — шелл открывается внутри неё: `-A` значит
    /// «подключиться к существующей или создать». Так сессия живёт на сервере и
    /// переживает закрытие приложения или обрыв сети: при следующем заходе мы
    /// подключаемся к той же живой сессии, а не начинаем с нуля. Если tmux на
    /// сервере нет — молча откатываемся на обычный логин-шелл, а не падаем.
    public static func shellArguments(
        host: ServerHost, route: Route, controlPath: String, tmuxSession: String? = nil
    ) -> [String] {
        var result =
            arguments(host: host, route: route, controlPath: controlPath)
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
        let allowed = CharacterSet(
            charactersIn:
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
