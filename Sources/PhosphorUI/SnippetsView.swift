public import HostsKit
public import SwiftUI

/// Сниппеты: сохранённые команды с подстановками.
public struct SnippetsView: View {
    @Environment(\.style) private var style
    @Bindable var model: AppModel

    @State private var name = ""
    @State private var command = ""
    @State private var values: [String: String] = [:]
    @State private var selected: Snippet.ID?

    public init(model: AppModel) { self.model = model }

    private var current: Snippet? {
        model.book.snippets.first { $0.id == selected } ?? model.book.snippets.first
    }

    public var body: some View {
        HStack(alignment: .top, spacing: 22) {
            list
            Rectangle().fill(style.rule).frame(width: 1)
            detail
        }
    }

    private var list: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label2("сниппеты · \(model.book.snippets.count)")
            ForEach(model.book.snippets) { snippet in
                Button {
                    selected = snippet.id; values = [:]
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(snippet.name)
                            .foregroundStyle(snippet.id == current?.id ? style.bright : style.text)
                        Text(snippet.command)
                            .font(style.font(10.5)).foregroundStyle(style.muted).lineLimit(1)
                    }
                    .font(style.font(12))
                    .padding(.vertical, 4).padding(.horizontal, 6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(snippet.id == current?.id ? style.surface : .clear)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            Rule().padding(.vertical, 6)
            Label2("новый")
            TextField("название", text: $name)
                .textFieldStyle(.plain).font(style.font(12))
                .padding(.horizontal, 8).padding(.vertical, 5)
                .overlay(Rectangle().stroke(style.text.opacity(0.3), lineWidth: 1))
            TextField("docker logs --tail 200 {{container}}", text: $command)
                .textFieldStyle(.plain).font(style.font(12))
                .padding(.horizontal, 8).padding(.vertical, 5)
                .overlay(Rectangle().stroke(style.text.opacity(0.3), lineWidth: 1))
            PhButton("сохранить") {
                model.addSnippet(name: name, command: command)
                name = ""
                command = ""
            }
            Spacer(minLength: 0)
        }
        .frame(width: 300, alignment: .leading)
    }

    @ViewBuilder private var detail: some View {
        if let snippet = current {
            VStack(alignment: .leading, spacing: 12) {
                Text(snippet.name).font(style.font(15)).foregroundStyle(style.bright)
                Text(snippet.command)
                    .font(style.font(12)).foregroundStyle(style.text.opacity(0.85))
                    .textSelection(.enabled)

                if !snippet.placeholders.isEmpty {
                    Label2("подстановки")
                    ForEach(snippet.placeholders, id: \.self) { key in
                        HStack(spacing: 8) {
                            Text(key).font(style.font(12)).foregroundStyle(style.muted)
                                .frame(width: 110, alignment: .leading)
                            TextField(
                                "",
                                text: Binding(
                                    get: { values[key] ?? "" },
                                    set: { values[key] = $0 }
                                )
                            )
                            .textFieldStyle(.plain).font(style.font(12))
                            .padding(.horizontal, 8).padding(.vertical, 4)
                            .overlay(Rectangle().stroke(style.text.opacity(0.3), lineWidth: 1))
                        }
                    }
                }

                Label2("что уйдёт на сервер")
                Text(snippet.expand(values))
                    .font(style.font(12)).foregroundStyle(style.bright)
                    .textSelection(.enabled)
                    .padding(.horizontal, 10).padding(.vertical, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(style.surface)

                HStack(spacing: 8) {
                    PhButton("выполнить здесь", kind: .primary) {
                        Task { await model.runSnippet(snippet, values: values, onGroup: false) }
                    }
                    .disabled(model.session == nil)
                    if let group = model.currentGroup {
                        PhButton("на всех в «\(group.name)»") {
                            Task { await model.runSnippet(snippet, values: values, onGroup: true) }
                        }
                    }
                    PhButton("удалить", kind: .danger) { model.removeSnippet(snippet) }
                }

                if let egg = model.snippetEgg {
                    Text(model.strings(egg).uppercased())
                        .font(style.font(11)).tracking(2).foregroundStyle(style.accent)
                }

                if !model.snippetOutput.isEmpty {
                    Label2("вывод")
                    ScrollView {
                        Text(model.snippetOutput)
                            .font(style.font(11.5)).foregroundStyle(style.text.opacity(0.85))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                Spacer(minLength: 0)
            }
        } else {
            Text("сниппетов ещё нет").font(style.font(12)).foregroundStyle(style.muted)
        }
    }
}
