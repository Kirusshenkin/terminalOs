import Foundation
import PetKit

/// Питомцы через мост: посмотреть, добавить нарисованного, убрать своего.
///
/// Питомец — проверенная сетка из шести символов, а не код и не картинка, и
/// всё равно каждое добавление и удаление подтверждает человек: в его углу
/// не появляется ничего, чего он не видел.
extension ToolRunner {
    func managePets(tool: Tool, arguments: [String: String], mode: RunMode) async -> ToolResult {
        let custom = await pets()
        let intent: HostEdit
        let summary: String
        switch tool.name {
        case "list_pets":
            let lines =
                ["cat  (built-in)", "glider  (built-in)"]
                + custom.map { "\($0.id)  «\($0.name)»  \($0.summary)" }
            let result = ToolResult(text: lines.joined(separator: "\n"))
            await log(tool: tool, host: "—", arguments: arguments, decision: "allow", result: result)
            return result
        case "add_pet":
            guard let json = arguments["pet"], !json.isEmpty else {
                return ToolResult(text: "pet not specified", isError: true)
            }
            let data = Data(json.utf8)
            let pet: PetDefinition
            do {
                pet = try PetFile.decode(data)
            } catch {
                // Ошибка по полю: агент может поправить ровно этот кадр.
                return ToolResult(text: error.englishDescription, isError: true)
            }
            guard !custom.contains(where: { $0.id == pet.id }) else {
                return ToolResult(text: PetFileError.exists(pet.id).englishDescription, isError: true)
            }
            intent = .addPet(data)
            summary = "add pet «\(pet.name)» (\(pet.id)): \(pet.summary)"
        default:
            guard let id = arguments["pet"], let pet = custom.first(where: { $0.id == id }) else {
                return ToolResult(
                    text: PetFileError.notFound(arguments["pet"] ?? "").englishDescription, isError: true)
            }
            intent = .removePet(id: id)
            summary = "remove pet «\(pet.name)» (\(pet.id))"
        }

        guard mode == .live else { return ToolResult(text: "would: \(summary)") }
        guard await confirm("pets", summary) else {
            let refusal = ToolResult(text: "user declined", isError: true)
            await log(tool: tool, host: "—", arguments: arguments, decision: "deny", result: refusal)
            return refusal
        }
        await edit(intent)
        let result = ToolResult(text: "done: \(summary)")
        await log(tool: tool, host: "—", arguments: arguments, decision: "confirm", result: result)
        return result
    }
}
