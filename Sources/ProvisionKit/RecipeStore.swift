public import Foundation

/// The person's own recipes: one validated `.json` file each, in a folder.
///
/// An actor because it is file work, and file work stays off the main thread.
/// Files are written atomically: a recipe cut off halfway through a write
/// would be refused on the next launch, and the person would lose it.
public actor RecipeStore {
    private let directory: URL

    public init(directory: URL) {
        self.directory = directory
    }

    /// `~/Library/Application Support/Phosphor/recipes`.
    public static func defaultDirectory() -> URL {
        let base =
            FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory() + "/Library/Application Support")
        return base.appendingPathComponent("Phosphor/recipes", isDirectory: true)
    }

    /// Every recipe in the folder, and the files that were refused with why.
    /// A broken file does not hide the good ones.
    public func load() -> (recipes: [Recipe], problems: [String: RecipeFileError]) {
        let names: [String]
        do {
            names = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        } catch {
            // Папки ещё нет — своих рецептов просто нет; это не ошибка.
            return ([], [:])
        }
        var recipes: [Recipe] = []
        var problems: [String: RecipeFileError] = [:]
        for name in names.sorted() where name.hasSuffix(".json") {
            let url = directory.appendingPathComponent(name)
            do {
                let data = try Data(contentsOf: url)
                recipes.append(try RecipeFile.decode(data))
            } catch let error as RecipeFileError {
                problems[name] = error
            } catch {
                problems[name] = .cannotRead(error.localizedDescription)
            }
        }
        return (recipes, problems)
    }

    /// Validates a file and copies it into the library under its id.
    public func importFile(at source: URL) throws(RecipeFileError) -> Recipe {
        let data: Data
        do {
            data = try Data(contentsOf: source)
        } catch {
            throw .cannotRead(error.localizedDescription)
        }
        let recipe = try RecipeFile.decode(data)
        let target = directory.appendingPathComponent("\(recipe.id).json")
        guard !FileManager.default.fileExists(atPath: target.path) else { throw .exists(recipe.id) }
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try data.write(to: target, options: .atomic)
        } catch {
            throw .cannotWrite(error.localizedDescription)
        }
        return recipe
    }

    public func delete(id: String) throws(RecipeFileError) {
        // id прошёл проверку формата при импорте, но удаление не должно
        // доверять ему вслепую: путь собирается только из безопасных символов.
        guard id.range(of: #"^[a-z0-9][a-z0-9-]{0,39}$"#, options: .regularExpression) != nil else {
            throw .badID(id)
        }
        do {
            try FileManager.default.removeItem(at: directory.appendingPathComponent("\(id).json"))
        } catch {
            throw .cannotWrite(error.localizedDescription)
        }
    }
}
