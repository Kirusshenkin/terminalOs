public import Foundation
public import HostsKit

/// Правка, пришедшая снаружи: список хостов, даты ключей, свои питомцы.
///
/// Мост не трогает профиль и файлы сам: он описывает намерение, а применяет
/// его приложение — там же, где живёт запись на диск и шифрование.
public enum HostEdit: Sendable {
    case add(ServerHost)
    case update(ServerHost)
    case remove(ServerHost.ID)
    /// Ключ дописан в `authorized_keys`: приложение запоминает дату.
    case keyAdded(fingerprint: String, host: ServerHost.ID)
    /// Ключ убран с сервера: дата забывается, повторное добавление — новое.
    case keyRemoved(fingerprint: String, host: ServerHost.ID)
    /// JSON питомца, уже проверенный и подтверждённый человеком.
    case addPet(Data)
    case removePet(id: String)
}
