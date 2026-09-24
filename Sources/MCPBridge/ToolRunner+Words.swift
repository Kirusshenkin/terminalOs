import DockerKit
import KeysKit
import PhosphorCore

/// Слова, которыми мост отвечает ИИ-клиенту.
///
/// Пакеты отдают причины типами, а не фразами; интерфейс подбирает слова по
/// своей таблице, мост — здесь. Ответы моста пока только по-русски (#13).
extension ToolRunner {
    static func describe(_ weakness: KeyWeakness) -> String {
        switch weakness {
        case .dsa: "DSA — устарел и небезопасен"
        case .shortRSA(let bits): "RSA \(bits) бит — короче 3072"
        }
    }

    static func describe(_ outcome: ActionOutcome) -> String {
        switch outcome.failure {
        case nil: "\(outcome.action.rawValue): готово"
        case .docker(.noSocketAccess): "нет доступа к сокету docker — нужен sudo или группа docker"
        case .docker(.gone): "контейнера уже нет"
        case .docker(.notRunning): "контейнер не запущен"
        case .docker(.stopFirst): "сначала остановить: удалять работающий контейнер docker не даёт"
        case .docker(.inUse): "контейнер занят"
        case .docker(.other(let text)): text
        case .connection(let failure): describe(failure)
        case .noSession: "нет подключения к хосту"
        }
    }

    static func describe(_ failure: ConnectionFailure) -> String {
        switch failure {
        case .proxyDown(let host, let port): "прокси \(host):\(port) не отвечает — запущен ли V2Box?"
        case .denied(let host): "\(host) отказал в доступе — ключа нет в authorized_keys?"
        case .hostKeyChanged(let host): "ключ хоста \(host) изменился — подключение остановлено"
        case .unreachable(let address): "\(address) не отвечает"
        case .remote(let text): text
        case .other(let host): "не удалось подключиться к \(host)"
        }
    }
}
