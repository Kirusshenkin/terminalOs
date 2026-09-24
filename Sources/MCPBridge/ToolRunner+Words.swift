import DockerKit
import KeysKit
import PhosphorCore

/// Слова, которыми мост отвечает ИИ-клиенту.
///
/// Пакеты отдают причины типами, а не фразами; интерфейс подбирает слова по
/// своей таблице, мост — здесь.
extension ToolRunner {
    static func describe(_ weakness: KeyWeakness) -> String {
        switch weakness {
        case .dsa: "DSA — obsolete and insecure"
        case .shortRSA(let bits): "RSA \(bits) bits — shorter than 3072"
        }
    }

    static func describe(_ outcome: ActionOutcome) -> String {
        switch outcome.failure {
        case nil: "\(outcome.action.rawValue): done"
        case .docker(.noSocketAccess): "no access to docker socket — need sudo or docker group"
        case .docker(.gone): "container no longer exists"
        case .docker(.notRunning): "container not running"
        case .docker(.stopFirst): "stop first: cannot remove running docker container"
        case .docker(.inUse): "container in use"
        case .docker(.other(let text)): text
        case .connection(let failure): describe(failure)
        case .noSession: "no connection to host"
        }
    }

    static func describe(_ failure: ConnectionFailure) -> String {
        switch failure {
        case .proxyDown(let host, let port): "proxy \(host):\(port) not responding — is V2Box running?"
        case .denied(let host): "\(host) access denied — key not in authorized_keys?"
        case .hostKeyChanged(let host): "\(host) host key changed — connection blocked"
        case .unreachable(let address): "\(address) not responding"
        case .remote(let text): text
        case .other(let host): "failed to connect to \(host)"
        }
    }
}
