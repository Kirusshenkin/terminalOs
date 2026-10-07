public import HostsKit

/// Правка профиля, пришедшая снаружи.
///
/// Мост не трогает профиль сам: он описывает намерение, а применяет его
/// приложение — там же, где живёт запись на диск и шифрование.
public enum HostEdit: Sendable {
    case add(ServerHost)
    case update(ServerHost)
    case remove(ServerHost.ID)
    /// Ключ дописан в `authorized_keys`: приложение запоминает дату.
    case keyAdded(fingerprint: String, host: ServerHost.ID)
    /// Ключ убран с сервера: дата забывается, повторное добавление — новое.
    case keyRemoved(fingerprint: String, host: ServerHost.ID)
}
