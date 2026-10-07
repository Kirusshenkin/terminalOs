public import AppKit
public import HostsKit
public import KeysKit
public import ProvisionKit
public import SwiftUI
public import UniformTypeIdentifiers

/// Выбор рецепта над списком шагов: встроенные, свои из файлов, импорт.
///
/// Рецепт, который не подходит этой системе, виден, но приглушён и с
/// причиной: спрятанный, он выглядел бы потерянным.
struct RecipePicker: View {
    @Environment(\.style) private var style
    @Bindable var model: AppModel
    private var strings: Strings { model.strings }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            chips
            if let recipe = model.selectedRecipe {
                if recipe.origin == .file {
                    Text(strings("prov.foreign"))
                        .font(style.font(11)).foregroundStyle(style.warning)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if recipe.id == "keys" { keyChooser }
                groupLine(recipe)
            }
            if let message = model.recipeMessage {
                Text(message)
                    .font(style.font(11)).foregroundStyle(style.muted)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }
            if !model.recipeProblems.isEmpty {
                // Сломанный файл не прячет остальные, но и сам не исчезает молча.
                Text(problemsText)
                    .font(style.font(11)).foregroundStyle(style.warning)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }
        }
    }

    private var chips: some View {
        FlowRow(spacing: 6) {
            ForEach(model.availableRecipes) { recipe in
                let fits = model.profile.map(recipe.applies) ?? true
                chip(
                    strings.recipeName(recipe) + (recipe.origin == .file ? " ·" : ""),
                    selected: model.selectedRecipeID == recipe.id, dimmed: !fits
                ) { model.selectedRecipeID = recipe.id }
                .help(
                    fits ? (recipe.origin == .file ? strings("prov.fromFile") : "") : strings("prov.notForOS")
                )
                .contextMenu {
                    if recipe.origin == .file {
                        Button(strings("prov.deleteRecipe")) { Task { await model.deleteRecipe(recipe) } }
                    }
                }
            }
            chip(strings("prov.import"), selected: false, dimmed: false) { pickFile() }
        }
    }

    /// Какие ключи из `~/.ssh` положить на сервер. Только с приватной
    /// половиной: ключ, которым нечем войти, добавлять бессмысленно.
    private var keyChooser: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label2(strings("prov.keysToAdd"))
            FlowRow(spacing: 6) {
                ForEach(model.localKeys.filter(\.hasPrivate)) { key in
                    chip(key.name, selected: model.provisionKeyIDs.contains(key.id), dimmed: false) {
                        if model.provisionKeyIDs.contains(key.id) {
                            model.provisionKeyIDs.remove(key.id)
                        } else {
                            model.provisionKeyIDs.insert(key.id)
                        }
                    }
                }
            }
            Toggle(strings("prov.removeOthers"), isOn: $model.removeOtherKeys)
                .toggleStyle(.checkbox)
                .font(style.font(11.5))
        }
    }

    @ViewBuilder private func groupLine(_ recipe: Recipe) -> some View {
        if let group = model.provisionGroup {
            HStack(spacing: 8) {
                let current = group.recipeID ?? "base"
                let name =
                    model.availableRecipes.first { $0.id == current }.map(strings.recipeName) ?? current
                Text(
                    strings("prov.groupRecipe").replacingOccurrences(of: "%@", with: group.name) + ": " + name
                )
                .font(style.font(11)).foregroundStyle(style.muted)
                if current != recipe.id {
                    Button(strings("prov.makeGroupRecipe")) { model.makeSelectedRecipeGroupDefault() }
                        .buttonStyle(PressFeedback())
                        .font(style.font(11)).foregroundStyle(style.accent)
                }
            }
        }
    }

    private var problemsText: String {
        let lines = model.recipeProblems.sorted { $0.key < $1.key }
            .map { "\($0.key): \(strings.recipeFileError($0.value))" }
        return ([strings("prov.brokenFiles")] + lines).joined(separator: "\n")
    }

    private func pickFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task { await model.importRecipe(from: url) }
    }

    private func chip(
        _ title: String, selected: Bool, dimmed: Bool, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(title)
                .font(style.font(11))
                .padding(.horizontal, 9).padding(.vertical, 3)
                .foregroundStyle(selected ? style.background : style.muted)
                .background(selected ? style.accent : .clear)
                .overlay(Rectangle().stroke(selected ? style.accent : style.text.opacity(0.25), lineWidth: 1))
                .opacity(dimmed ? 0.45 : 1)
        }
        .buttonStyle(PressFeedback())
    }
}
