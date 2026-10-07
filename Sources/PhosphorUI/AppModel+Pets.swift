public import Foundation
public import PetKit

/// Свои питомцы: папка, импорт, удаление и выбор.
@MainActor
extension AppModel {
    /// Свой питомец, если выбран он и он есть в папке. nil — встроенный.
    public var customPet: PetDefinition? {
        guard case .custom(let id) = pet else { return nil }
        return customPets.first { $0.id == id }
    }

    /// Имя для подписей: встроенные — на языке интерфейса, свои — как назвал автор.
    public func petName(_ pet: Pet) -> String {
        switch pet {
        case .cat: strings("pet.cat")
        case .glider: strings("pet.glider")
        case .custom(let id): customPets.first { $0.id == id }?.name ?? id
        }
    }

    public func loadPets() async {
        let loaded = await petStore.load()
        PetPaths.forgetCustom()
        customPets = loaded.pets
        petProblems = loaded.problems
    }

    public func importPet(from url: URL) async {
        do {
            let added = try await petStore.importFile(at: url)
            await loadPets()
            choosePet(.custom(added.id))
            petMessage = strings.format("pet.imported", added.name)
        } catch {
            petMessage = strings.petFileError(error)
        }
    }

    public func deletePet(_ id: String) async {
        do {
            try await petStore.delete(id: id)
            petMessage = nil
            // Выбранный питомец ушёл — в угол возвращается котёнок, а не пустота.
            // Не удалился — остаётся и выбор: питомец по-прежнему в списке.
            if pet == .custom(id) { choosePet(.cat) }
        } catch {
            petMessage = strings.petFileError(error)
        }
        await loadPets()
    }

    public func choosePet(_ chosen: Pet) {
        pet = chosen
        petVisible = true
        saveAppearance()
    }

    /// Питомец, присланный агентом через MCP. Человек уже подтвердил.
    func addPetFromBridge(_ data: Data) async {
        do {
            let added = try await petStore.add(data)
            await loadPets()
            petMessage = strings.format("pet.imported", added.name)
        } catch {
            petMessage = strings.petFileError(error)
        }
    }
}
