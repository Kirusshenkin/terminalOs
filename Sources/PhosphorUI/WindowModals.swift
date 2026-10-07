import SwiftUI

/// Формы поверх окна.
struct WindowModals: ViewModifier {
    @Bindable var model: AppModel

    func body(content: Content) -> some View {
        content
            // Все окна — `LightModal` (#27): клик мимо закрывает, если терять
            // нечего; с несохранённым вводом — напоминает про «сохранить» и
            // «отмена». Esc и крестик закрывают всегда.
            .lightModal(isPresented: $model.isAddingHost, strings: model.strings) {
                HostEditor(model: model)
            }
            .lightModal(item: $model.editingHost, strings: model.strings) { host in
                HostEditor(model: model, editing: host).id(host.id)
            }
            .lightModal(isPresented: $model.isAddingGroup, strings: model.strings) {
                GroupEditor(model: model)
            }
            .lightModal(item: $model.editingGroup, strings: model.strings) { group in
                GroupEditor(model: model, editing: group).id(group.id)
            }
            .lightModal(item: $model.profilePrompt, strings: model.strings) { prompt in
                PassphraseSheet(model: model, prompt: prompt)
            }
            .lightModal(isPresented: $model.isQuickConnectOpen, strings: model.strings) {
                QuickConnect(model: model)
            }
            .lightModal(isPresented: $model.showsPlannedCommands, strings: model.strings) {
                PlannedCommands(model: model)
            }
    }
}

extension AppModel {
    /// Открыто ли окно поверх интерфейса. Пока открыто, команды меню молчат:
    /// иначе ⌘N открыл бы вторую форму поверх первой.
    var isModalOpen: Bool {
        isAddingHost || editingHost != nil || isAddingGroup || editingGroup != nil || profilePrompt != nil
            || isQuickConnectOpen || showsPlannedCommands
    }
}
