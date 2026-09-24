public import SwiftUI

extension FocusedValues {
    /// Модель окна для меню: у меню нет своего окна, и без этого ему не до
    /// чего дотянуться.
    @Entry public var appModel: AppModel?
}

/// Горячие клавиши — пунктами меню, а не невидимыми кнопками.
///
/// Так каждое сочетание видно в строке меню рядом с действием, находится без
/// инструкции и не спорит с терминалом: ⌃-сочетания, ⌥ как Meta и ⌘←/→ сюда
/// не заняты и уходят в шелл. Раскладка — §28 плана.
public struct PhosphorCommands: Commands {
    @FocusedValue(\.appModel) private var model

    public init() {}

    /// За замком модели нет, но меню всё равно подписано — на языке системы.
    private var strings: Strings { model?.strings ?? Strings() }

    public var body: some Commands {
        CommandGroup(replacing: .appSettings) {
            item("cmd.settings", ",") { $0.screen = .theme }
        }
        // Документов у приложения нет: «Сохранить» и «Закрыть окно» только
        // отняли бы ⌘W у панели терминала.
        CommandGroup(replacing: .saveItem) {}
        CommandGroup(replacing: .newItem) {
            item("cmd.newSession", "t") { $0.newSessionFromKeyboard() }
            item("cmd.newHost", "n") {
                $0.screen = .hosts
                $0.isAddingHost = true
            }
            item("cmd.quickConnect", "o", [.command, .shift]) { $0.isQuickConnectOpen = true }
            Divider()
            item("cmd.closePane", "w", enabled: model?.extraSessions.isEmpty == false) {
                $0.closeFocusedPane()
            }
        }
        CommandMenu(strings("cmd.terminalMenu")) {
            item("cmd.splitSide", "d", enabled: model?.canSplit == true) { $0.split(sideBySide: true) }
            item("cmd.splitBelow", "d", [.command, .shift], enabled: model?.canSplit == true) {
                $0.split(sideBySide: false)
            }
            item(
                "cmd.nextPane", .rightArrow, [.command, .option], enabled: model?.extraPanes.isEmpty == false
            ) {
                $0.focusPane(step: 1)
            }
            item(
                "cmd.previousPane", .leftArrow, [.command, .option],
                enabled: model?.extraPanes.isEmpty == false
            ) {
                $0.focusPane(step: -1)
            }
            Divider()
            item("cmd.clear", "k") { $0.clearFocusedTerminal() }
            item("cmd.find", "f") { $0.terminalFind(.showFindInterface) }
            item("cmd.findNext", "g") { $0.terminalFind(.nextMatch) }
            item("cmd.findPrevious", "g", [.command, .shift]) { $0.terminalFind(.previousMatch) }
            Divider()
            item("cmd.biggerText", "=") { $0.stepFontSize(1) }
            item("cmd.smallerText", "-") { $0.stepFontSize(-1) }
            item("cmd.actualSize", "0") { $0.resetFontSize() }
            Divider()
            item("cmd.reconnect", "r", [.command, .shift], enabled: model?.selectedHost != nil) {
                $0.reconnect()
            }
        }
        CommandMenu(strings("cmd.hostMenu")) {
            item("cmd.editHost", "e", enabled: model?.currentHost != nil) {
                $0.editingHost = $0.currentHost
            }
            item("cmd.removeHost", .delete, enabled: model?.currentHost != nil) {
                $0.pendingHostRemoval = $0.currentHost
            }
            Divider()
            item("cmd.lock", "l", [.command, .control]) { $0.lock() }
        }
    }

    /// Пункт меню с сочетанием. Без открытого окна пункт гаснет: действовать
    /// не на что.
    private func item(
        _ key: String, _ shortcut: KeyEquivalent, _ modifiers: EventModifiers = .command,
        enabled: Bool = true, action: @escaping @MainActor (AppModel) -> Void
    ) -> some View {
        Button(strings(key)) {
            if let model { action(model) }
        }
        .keyboardShortcut(shortcut, modifiers: modifiers)
        .disabled(model == nil || !enabled)
    }
}
