public import HostsKit
public import SwiftUI

/// Имя группы — единственное, что у группы есть. Поэтому форма из одного поля,
/// а не диалог с вкладками.
public struct GroupEditor: View {
    @Environment(\.style) private var style
    @Environment(\.dismiss) private var dismiss
    @Bindable var model: AppModel
    private var strings: Strings { model.strings }
    private let editing: HostGroup?
    @State private var name: String

    public init(model: AppModel, editing: HostGroup? = nil) {
        self.model = model
        self.editing = editing
        _name = State(initialValue: editing?.name ?? "")
    }

    private var trimmed: String { name.trimmingCharacters(in: .whitespaces) }

    public var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(editing == nil ? strings("group.new") : strings("group.rename"))
                .font(style.font(15)).foregroundStyle(style.bright)
            TextField(strings("group.hint"), text: $name)
                .textFieldStyle(.plain)
                .font(style.font(13))
                .foregroundStyle(style.text)
                .padding(.horizontal, 10).padding(.vertical, 7)
                .overlay(Rectangle().stroke(style.text.opacity(0.3), lineWidth: 1))
                .onSubmit(save)
            HStack(spacing: 8) {
                Spacer()
                PhButton(strings("common.cancel")) { dismiss() }
                PhButton(strings("common.save"), kind: .primary, action: save)
                    .disabled(trimmed.isEmpty)
                    .opacity(trimmed.isEmpty ? 0.4 : 1)
            }
        }
        .padding(18)
        .frame(width: 360)
        .background(style.surface)
    }

    private func save() {
        guard !trimmed.isEmpty else { return }
        if let editing {
            model.renameGroup(editing, to: trimmed)
        } else {
            model.addGroup(named: trimmed)
        }
        dismiss()
    }
}
