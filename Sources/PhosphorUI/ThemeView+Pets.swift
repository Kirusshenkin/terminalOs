import AppKit
import PetKit
import SwiftUI
import UniformTypeIdentifiers

/// Выбор питомца: встроенные, свои из папки, импорт и «выключить».
extension ThemeView {
    var petChooser: some View {
        VStack(alignment: .leading, spacing: 8) {
            FlowRow(spacing: 8) {
                ForEach(Pet.builtIn + model.customPets.map { Pet.custom($0.id) }, id: \.self) { pet in
                    toggleChip(model.petName(pet).lowercased(), on: model.petVisible && model.pet == pet) {
                        model.choosePet(pet)
                    }
                    .help(pet.isCustom ? strings("pet.fromFile") : "")
                    .contextMenu {
                        if case .custom(let id) = pet {
                            Button(strings("pet.delete")) { Task { await model.deletePet(id) } }
                        }
                    }
                }
                toggleChip(strings("set.off"), on: !model.petVisible) {
                    model.petVisible.toggle()
                    model.saveAppearance()
                }
                toggleChip(strings("pet.import"), on: false) { pickPetFile() }
            }
            Text(strings("pet.howTo"))
                .font(style.font(11)).foregroundStyle(style.muted)
                .fixedSize(horizontal: false, vertical: true)
            if let message = model.petMessage {
                Text(message)
                    .font(style.font(11)).foregroundStyle(style.muted)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }
            if !model.petProblems.isEmpty {
                // Сломанный файл не прячет остальных, но и сам не исчезает молча.
                Text(
                    ([strings("pet.brokenFiles")]
                        + model.petProblems.sorted { $0.key < $1.key }
                        .map { "\($0.key): \(strings.petFileError($0.value))" })
                        .joined(separator: "\n")
                )
                .font(style.font(11)).foregroundStyle(style.warning)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
            }
        }
        .task { await model.loadPets() }
    }

    private func pickPetFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task { await model.importPet(from: url) }
    }
}

extension Pet {
    var isCustom: Bool {
        if case .custom = self { return true }
        return false
    }
}
