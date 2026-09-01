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
    public static func shellArguments(
        host: ServerHost, reach: Reach, controlPath: String
    ) -> [String] {
        arguments(host: host, reach: reach, controlPath: controlPath)
            + ["-t", "\(host.user)@\(host.address)"]
    }

    public static func target(_ host: ServerHost) -> String {
        "\(host.user)@\(host.address)"
    }
}
