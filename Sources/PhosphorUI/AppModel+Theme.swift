public import AppKit
public import HostsKit
public import ThemeKit
public import UniformTypeIdentifiers

/// Темы: привязка к группам и импорт чужих схем.
@MainActor
extension AppModel {
    /// Привязывает тему к группе, повторный клик снимает привязку.
    public func bindTheme(_ id: String, to group: HostGroup) {
        guard let index = book.groups.firstIndex(where: { $0.id == group.id }) else { return }
        book.groups[index].themeID =
            (id.isEmpty || book.groups[index].themeID == id) ? nil : id
        scheduleSave()
    }

    /// Читает `.itermcolors` и добавляет схему к встроенным.
    ///
    /// Это XML plist, а не наш формат — поэтому даёт мгновенный доступ к сотням
    /// готовых схем ещё до того, как появится собственный редактор.
    public func importTheme() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [UTType(filenameExtension: "itermcolors") ?? .data]
        guard panel.runModal() == .OK, let url = panel.url else { return }

        let name = url.deletingPathExtension().lastPathComponent
        do {
            let data = try Data(contentsOf: url)
            guard let theme = try ThemeImport.iTerm(data: data, id: "imported-\(name)", name: name),
                theme.isValid
            else {
                themeImportNote = "в файле нет всех шестнадцати цветов ANSI"
                return
            }
            importedThemes.removeAll { $0.id == theme.id }
            importedThemes.append(theme)
            themeID = theme.id
            saveAppearance()
            themeImportNote = "добавлена тема «\(name)»"
        } catch {
            themeImportNote = "файл не читается: \(error.localizedDescription)"
        }
    }
}
