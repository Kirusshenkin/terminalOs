public import AppKit
public import Foundation
public import HostsKit

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
            try await profiles.importProfile(
                data, passphrase: passphrase, reason: strings("auth.saveReason"))
            book = try await profiles.load(HostBook.self, reason: strings("auth.reason"))
            syncForwardsFromBook()
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
