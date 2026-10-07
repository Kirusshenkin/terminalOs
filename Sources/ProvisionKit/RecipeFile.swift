public import Foundation

/// A recipe written by a person, as it is stored in a `.json` file.
///
/// The format is deliberately small: a name, which systems it is for, and
/// steps made of plain shell commands. Everything is validated before the
/// recipe is accepted, and an accepted recipe is still someone else's text —
/// the app shows every command before running any of them.
///
/// ```json
/// {
///   "format": 1,
///   "id": "node",
///   "name": "Node.js 22",
///   "requires": { "os": ["linux"], "packageManager": ["apt"] },
///   "steps": [
///     { "title": "Node.js", "check": "command -v node",
///       "commands": ["curl -fsSL https://deb.nodesource.com/setup_22.x | bash -",
///                    "apt-get install -y nodejs"] }
///   ]
/// }
/// ```
public struct RecipeFile: Codable, Sendable, Equatable {
    public struct Requires: Codable, Sendable, Equatable {
        public var os: [String]?
        public var packageManager: [String]?
    }

    public struct Step: Codable, Sendable, Equatable {
        public var title: String
        public var commands: [String]
        /// Exit 0 means the step is already done and is skipped.
        public var check: String?
        /// Run as the connecting user instead of root. Default: root.
        public var asUser: Bool?
    }

    public var format: Int
    public var id: String
    public var name: String
    public var requires: Requires?
    public var steps: [Step]

    /// The only version so far. A newer file is refused, not half-understood.
    public static let currentFormat = 1

    static let maxSteps = 40
    static let maxCommands = 50
    static let maxCommandLength = 4_000
    static let maxTitleLength = 80
    static let maxFileSize = 256 * 1024
    static let packageManagers: Set = ["apt", "dnf", "brew"]
    static let reservedIDs: Set = ["base", "docker", "keys"]

    /// Reads and validates a recipe file. The message of each error names the
    /// field, so a person can fix the file without reading this code.
    public static func decode(_ data: Data) throws(RecipeFileError) -> Recipe {
        guard data.count <= maxFileSize else { throw .tooLarge }
        let file: RecipeFile
        do {
            file = try JSONDecoder().decode(RecipeFile.self, from: data)
        } catch {
            throw .notJSON(String(describing: error).prefix(200).description)
        }
        return try file.recipe()
    }

    func recipe() throws(RecipeFileError) -> Recipe {
        guard format == Self.currentFormat else { throw .unsupportedFormat(format) }
        guard id.range(of: #"^[a-z0-9][a-z0-9-]{0,39}$"#, options: .regularExpression) != nil else {
            throw .badID(id)
        }
        guard !Self.reservedIDs.contains(id) else { throw .reservedID(id) }
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name.count <= Self.maxTitleLength else { throw .badName }
        guard (1...Self.maxSteps).contains(steps.count) else { throw .stepCount(steps.count) }
        var built: [RecipeStep] = []
        for (index, step) in steps.enumerated() {
            built.append(try step.recipeStep(number: index + 1, recipeID: id))
        }
        return Recipe(id: id, name: name, steps: built, requirement: try requirement(), origin: .file)
    }

    private func requirement() throws(RecipeFileError) -> RecipeRequirement {
        var families: [HostProfile.OSFamily] = []
        for os in requires?.os ?? [] {
            guard let family = HostProfile.OSFamily(rawValue: os), family != .other else {
                throw .unknownOS(os)
            }
            families.append(family)
        }
        let managers = requires?.packageManager ?? []
        if let unknown = managers.first(where: { !Self.packageManagers.contains($0) }) {
            throw .unknownPackageManager(unknown)
        }
        return RecipeRequirement(families: families, packageManagers: managers)
    }
}

extension RecipeFile.Step {
    func recipeStep(number: Int, recipeID: String) throws(RecipeFileError) -> RecipeStep {
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, title.count <= RecipeFile.maxTitleLength else { throw .badStepTitle(number) }
        guard (1...RecipeFile.maxCommands).contains(commands.count) else { throw .commandCount(number) }
        for command in commands + [check].compactMap({ $0 }) {
            let trimmed = command.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, command.count <= RecipeFile.maxCommandLength, !command.contains("\0")
            else {
                throw .badCommand(number)
            }
        }
        return RecipeStep(
            id: "\(recipeID).\(number)", title: title, commands: commands, check: check,
            asUser: asUser ?? false)
    }
}

/// Why a recipe file was refused.
public enum RecipeFileError: Error, Sendable, Equatable {
    case tooLarge
    case notJSON(String)
    case unsupportedFormat(Int)
    case badID(String)
    case reservedID(String)
    case badName
    case stepCount(Int)
    case unknownOS(String)
    case unknownPackageManager(String)
    case badStepTitle(Int)
    case commandCount(Int)
    case badCommand(Int)
    /// A recipe with this id is already in the library.
    case exists(String)
    case cannotRead(String)
    case cannotWrite(String)
}
