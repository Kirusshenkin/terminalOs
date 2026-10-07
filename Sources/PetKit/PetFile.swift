public import Foundation

/// One animation of a pet: its frames and how long each one stays on screen.
public struct PetAnimation: Sendable, Equatable {
    public let frames: [PetSprite]
    public let frameSeconds: Double
    /// Widest frame in pixels, counted once: the walk keeps its stride by it.
    public let maxWidth: Int

    init(frames: [PetSprite], frameSeconds: Double) {
        self.frames = frames
        self.frameSeconds = frameSeconds
        self.maxWidth = frames.map(\.width).max() ?? 0
    }

    /// The frame at `elapsed` seconds into the animation, looping.
    public func frame(at elapsed: Double) -> PetSprite {
        frames[Int(max(0, elapsed) / frameSeconds) % frames.count]
    }

    public var duration: Double { Double(frames.count) * frameSeconds }
}

/// A pet someone drew: the same pixel grids as the built-in ones.
///
/// Colours are not part of it on purpose: an ink names a role, and the theme
/// paints it, so a pet drawn for one theme does not clash with another.
public struct PetDefinition: Sendable, Equatable, Identifiable {
    public let id: String
    public let name: String
    public let idle: PetAnimation
    public let walk: PetAnimation
    public let sleep: PetAnimation
    /// Played over `idle` every few seconds, if the pet has one.
    public let blink: PetAnimation?

    /// How many frames each state has, for lists and confirmations.
    public var summary: String {
        var parts = ["idle \(idle.frames.count)", "walk \(walk.frames.count)", "sleep \(sleep.frames.count)"]
        if let blink { parts.append("blink \(blink.frames.count)") }
        return parts.joined(separator: ", ")
    }
}

/// A pet as it is stored in a `.json` file.
///
/// ```json
/// {
///   "format": 1,
///   "id": "fox",
///   "name": "Fox",
///   "states": {
///     "idle":  { "frames": [["..r..", ".rbr.", "rbebr", ".rbr."]] },
///     "walk":  { "frameMs": 125, "frames": [[…], […]] },
///     "sleep": { "frames": [[…]] }
///   }
/// }
/// ```
public struct PetFile: Codable, Sendable, Equatable {
    public struct State: Codable, Sendable, Equatable {
        public var frameMs: Int?
        public var frames: [[String]]
    }

    public var format: Int
    public var id: String
    public var name: String
    public var states: [String: State]

    public static let currentFormat = 1
    /// Frames are at most this many pixels a side: two scene points each, so
    /// the pet still fits the 200×100 corner with room to walk.
    public static let maxSide = 32
    public static let maxFrames = 8
    public static let maxFileSize = 64 * 1024
    public static let required = ["idle", "walk", "sleep"]
    public static let optional = ["blink"]
    static let defaultMs = ["idle": 500, "walk": 125, "sleep": 1_000, "blink": 150]
    static let msRange = 60...2_000
    static let reservedIDs: Set = ["cat", "glider"]
    static let idPattern = #"^[a-z0-9][a-z0-9-]{0,39}$"#

    /// Reads and validates a pet file. Each error names the state and frame,
    /// so the person — or the agent — can fix exactly that part.
    public static func decode(_ data: Data) throws(PetFileError) -> PetDefinition {
        guard data.count <= maxFileSize else { throw .tooLarge }
        let file: PetFile
        do {
            file = try JSONDecoder().decode(PetFile.self, from: data)
        } catch {
            throw .notJSON(String(describing: error).prefix(200).description)
        }
        return try file.definition()
    }

    func definition() throws(PetFileError) -> PetDefinition {
        guard format == Self.currentFormat else { throw .unsupportedFormat(format) }
        guard id.range(of: Self.idPattern, options: .regularExpression) != nil else { throw .badID(id) }
        guard !Self.reservedIDs.contains(id) else { throw .reservedID(id) }
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name.count <= 40 else { throw .badName }
        if let unknown = states.keys.sorted().first(where: { !(Self.required + Self.optional).contains($0) })
        {
            throw .unknownState(unknown)
        }
        for state in Self.required where states[state] == nil { throw .missingState(state) }
        return PetDefinition(
            id: id, name: name,
            idle: try animation("idle"), walk: try animation("walk"), sleep: try animation("sleep"),
            blink: states["blink"] == nil ? nil : try animation("blink"))
    }

    private func animation(_ name: String) throws(PetFileError) -> PetAnimation {
        guard let state = states[name] else { throw .missingState(name) }
        guard (1...Self.maxFrames).contains(state.frames.count) else { throw .frameCount(name) }
        let ms = state.frameMs ?? Self.defaultMs[name] ?? 250
        guard Self.msRange.contains(ms) else { throw .badDuration(name) }
        var sprites: [PetSprite] = []
        for (index, rows) in state.frames.enumerated() {
            let place = "\(name) \(index + 1)"
            guard (1...Self.maxSide).contains(rows.count), rows.allSatisfy({ $0.count <= Self.maxSide })
            else { throw .frameSize(place) }
            switch PetSprite.parse("pet.\(id).\(name).\(index)", rows, place: place) {
            case .success(let sprite): sprites.append(sprite)
            case .failure(let error): throw error
            }
        }
        return PetAnimation(frames: sprites, frameSeconds: Double(ms) / 1_000)
    }
}

/// Why a pet file was refused. The `String` says where: a state, or a state
/// and a frame number.
public enum PetFileError: Error, Sendable, Equatable {
    case tooLarge
    case notJSON(String)
    case unsupportedFormat(Int)
    case badID(String)
    case reservedID(String)
    case badName
    case missingState(String)
    case unknownState(String)
    case frameCount(String)
    case frameSize(String)
    case ragged(String)
    case unknownInk(String, String)
    case badDuration(String)
    /// A pet with this id is already in the library.
    case exists(String)
    case notFound(String)
    case cannotRead(String)
    case cannotWrite(String)

    /// Plain English for the agent on the other end of MCP. People see the
    /// translated text from the app's string tables instead.
    public var englishDescription: String {
        switch self {
        case .tooLarge: "file is larger than \(PetFile.maxFileSize / 1024) KB"
        case .notJSON(let detail): "not valid pet JSON: \(detail)"
        case .unsupportedFormat(let version): "format \(version) is not supported, use 1"
        case .badID(let id): "id «\(id)»: lowercase latin letters, digits and hyphens, up to 40"
        case .reservedID(let id): "id «\(id)» belongs to a built-in pet"
        case .badName: "name must be 1–40 characters"
        case .missingState(let state): "state «\(state)» is required"
        case .unknownState(let state): "unknown state «\(state)»: use idle, walk, sleep, blink"
        case .frameCount(let state): "state «\(state)» needs 1–\(PetFile.maxFrames) frames"
        case .frameSize(let place): "frame «\(place)» is larger than \(PetFile.maxSide)×\(PetFile.maxSide)"
        case .ragged(let place): "frame «\(place)»: every row must have the same non-zero width"
        case .unknownInk(let place, let ink):
            "frame «\(place)»: unknown character «\(ink)», use . b r e s n"
        case .badDuration(let state): "state «\(state)»: frameMs must be 60–2000"
        case .exists(let id): "pet «\(id)» already exists"
        case .notFound(let id): "no custom pet «\(id)»"
        case .cannotRead(let detail): "cannot read: \(detail)"
        case .cannotWrite(let detail): "cannot write: \(detail)"
        }
    }
}
