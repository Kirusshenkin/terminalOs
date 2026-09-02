public import HostsKit

/// Правка списка хостов, пришедшая снаружи.
///
/// Мост не трогает профиль сам: он описывает намерение, а применяет его
/// приложение — там же, где живёт запись на диск и шифрование.
public enum HostEdit: Sendable {
    case add(ServerHost)
    case update(ServerHost)
    case remove(ServerHost.ID)
}
