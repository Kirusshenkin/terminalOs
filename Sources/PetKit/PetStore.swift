public import Foundation

/// The person's own pets: one validated `.json` file each, in a folder.
///
/// An actor because it is file work, and file work stays off the main thread.
/// Files are written atomically: a pet cut off halfway through a write would be
/// refused on the next launch, and the person would lose it.
public actor PetStore {
    private let directory: URL

    public init(directory: URL) {
        self.directory = directory
    }

    /// `~/Library/Application Support/Phosphor/pets`.
    public static func defaultDirectory() -> URL {
        let base =
            FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory() + "/Library/Application Support")
        return base.appendingPathComponent("Phosphor/pets", isDirectory: true)
    }

    /// Every pet in the folder, and the files that were refused with why.
    /// A broken file does not hide the good ones.
    public func load() -> (pets: [PetDefinition], problems: [String: PetFileError]) {
        let names: [String]
        do {
            names = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        } catch {
            // Папки ещё нет — своих питомцев просто нет; это не ошибка.
            return ([], [:])
        }
        var pets: [PetDefinition] = []
        var problems: [String: PetFileError] = [:]
        for name in names.sorted() where name.hasSuffix(".json") {
            do {
                pets.append(try PetFile.decode(Data(contentsOf: directory.appendingPathComponent(name))))
            } catch let error as PetFileError {
                problems[name] = error
            } catch {
                problems[name] = .cannotRead(error.localizedDescription)
            }
        }
        return (pets, problems)
    }

    /// Validates a file and copies it into the library under its id.
    public func importFile(at source: URL) throws(PetFileError) -> PetDefinition {
        let data: Data
        do {
            data = try Data(contentsOf: source)
        } catch {
            throw .cannotRead(error.localizedDescription)
        }
        return try add(data)
    }

    /// Validates pet JSON and stores it. What lands on disk is exactly what
    /// was checked.
    public func add(_ data: Data) throws(PetFileError) -> PetDefinition {
        let pet = try PetFile.decode(data)
        let target = directory.appendingPathComponent("\(pet.id).json")
        guard !FileManager.default.fileExists(atPath: target.path) else { throw .exists(pet.id) }
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try data.write(to: target, options: .atomic)
        } catch {
            throw .cannotWrite(error.localizedDescription)
        }
        return pet
    }

    public func delete(id: String) throws(PetFileError) {
        // Путь собирается только из безопасных символов: id приходит и от
        // агента через MCP, а `../` в нём вышел бы за пределы папки.
        guard id.range(of: PetFile.idPattern, options: .regularExpression) != nil else { throw .badID(id) }
        let target = directory.appendingPathComponent("\(id).json")
        guard FileManager.default.fileExists(atPath: target.path) else { throw .notFound(id) }
        do {
            try FileManager.default.removeItem(at: target)
        } catch {
            throw .cannotWrite(error.localizedDescription)
        }
    }
}
