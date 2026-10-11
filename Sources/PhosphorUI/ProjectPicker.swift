import SwiftUI

/// Строка «проект» под «этот Мак»: в какой папке открываются локальные
/// сессии и агенты (план §23). Клик — последние проекты, выбор папки и
/// домашняя папка.
struct ProjectPicker: View {
    @Environment(\.style) private var style
    let model: AppModel

    @State private var showing = false

    var body: some View {
        Button {
            showing.toggle()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "folder").font(.system(size: 10))
                Text(title)
                    .font(style.font(11.5))
                    .lineLimit(1).truncationMode(.head)
                Image(systemName: "chevron.down").font(.system(size: 8, weight: .bold))
                Spacer(minLength: 0)
            }
            .foregroundStyle(model.localProject == nil ? style.muted : style.text)
            .padding(.horizontal, 8).padding(.vertical, 5)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressFeedback())
        .help(model.localProject ?? "")
        .accessibilityLabel(model.strings("term.project.label"))
        .accessibilityValue(title)
        .popover(isPresented: $showing, arrowEdge: .trailing) {
            PhMenu(items: items) { showing = false }
        }
    }

    private var title: String {
        model.localProject.map { LocalProjects.display($0) } ?? model.strings("term.project.none")
    }

    private var items: [MenuItem] {
        var items = model.recentProjects.map { path in
            MenuItem(LocalProjects.display(path)) { model.openProject(path) }
        }
        if !items.isEmpty { items.append(.separator) }
        items.append(MenuItem(model.strings("term.project.choose")) { model.chooseProjectFolder() })
        items.append(MenuItem(model.strings("term.project.home")) { model.openProject(NSHomeDirectory()) })
        return items
    }
}
