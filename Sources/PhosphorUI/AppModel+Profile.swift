public import AppKit
import AuthKit
public import Foundation
public import HostsKit
import Security

/// Экспорт и импорт всего профиля одним зашифрованным файлом.
///
/// Мастер-ключ привязан к этому Маку (`ThisDeviceOnly`) и не покидает Keychain —
/// на другом Маке профиль нечитаем. Этот файл, перешифрованный парольной фразой,
/// единственный мост на новый Мак и страховка от потери ключа (§8.6).
@MainActor
extension AppModel {
    /// Просит фразу и, если человек её ввёл, пишет зашифрованный файл.
    public func performExport(passphrase: String) async {
        do {
            let data = try await profiles.export(passphrase: passphrase, reason: strings("auth.reason"))
            let panel = NSSavePanel()
            panel.nameFieldStringValue = "phosphor-profile.phosphorprofile"
            panel.canCreateDirectories = true
            guard panel.runModal() == .OK, let url = panel.url else { return }
            try data.write(to: url)
            profileNote = strings("profile.exported")
        } catch {
            // Причину показываем, но без деталей крипты — они человеку ничего
            // не говорят, кроме «что-то пошло не так».
            profileNote = strings("profile.exportFailed")
        }
    }

    /// Открывает выбор файла; фразу спросим отдельным шагом.
    public func chooseImportFile() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        profilePrompt = .importFrom(url)
    }

    /// Ставит импортированный профиль на место текущего и перечитывает его.
    public func performImport(from url: URL, passphrase: String) async {
        do {
            let data = try Data(contentsOf: url)
            book = try await profiles.importProfile(
                data, as: HostBook.self, passphrase: passphrase, reason: strings("auth.saveReason"))
            // Профиль снова на диске и прочитан — писать в него безопасно.
            profileWritable = true
            saveError = nil
            syncForwardsFromBook()
            await syncMCPModesFromBook()
            profileNote = strings("profile.imported")
        } catch {
            profileNote = strings("profile.importFailed")
        }
    }

    /// Применяет новое окно повторной биометрии сразу и запоминает его.
    public func applyBiometricReuse(_ seconds: Double) {
        biometricReuseSeconds = seconds
        gate.reuseDuration = seconds
        saveAppearance()
    }
}

/// Запись профиля на диск.
@MainActor
extension AppModel {
    /// Записывает профиль сразу, не дожидаясь схлопывания правок.
    ///
    /// Для тех, кому нужен ответ: импорт стирает исходный файл только после
    /// того, как хосты действительно легли в профиль.
    func saveNow() async -> Bool {
        saveTask?.cancel()
        return await writeProfile()
    }

    /// Пускает в окно с непрочитанным профилем, но не даёт его затереть.
    ///
    /// Внутри окна лежит единственный выход — импорт экспорта в настройках,
    /// поэтому держать человека на экране входа нельзя.
    func holdWrites(_ reason: String) {
        book = HostBook()
        saveError = "\(reason). \(strings("vault.writesHeld"))"
    }

    @discardableResult
    func writeProfile() async -> Bool {
        // Профиль на диске не прочитан — значит в памяти не он, а пустышка.
        // Запись затёрла бы настоящие серверы; причина уже на плашке.
        guard profileWritable else { return false }
        do {
            try await profiles.save(book, reason: strings("auth.saveReason"))
            saveError = nil
            return true
        } catch SecretError.keychain(errSecMissingEntitlement) {
            // Сборка без подписи с доступом к связке ключей: macOS не заводит
            // запись под замком, сколько ни повторяй.
            saveError = strings("vault.saveUnsigned")
        } catch ProfileStoreError.enrollmentChanged {
            saveError = strings("vault.enrollmentChanged")
        } catch ProfileStoreError.keyLost {
            saveError = strings("vault.keyLost")
        } catch {
            saveError = "\(strings("vault.saveFailed")) \(strings.describe(error))"
        }
        return false
    }
}
