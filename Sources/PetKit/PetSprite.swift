import Foundation

/// One frame of pixel art, parsed once from rows of characters.
///
/// A frame is drawn many times a second, so the text form is turned into a
/// flat list of pixels when the frame is created and never parsed again.
/// Colours are not stored: an ink names a role, and the theme decides what it
/// looks like.
public struct PetSprite: Sendable, Equatable, Identifiable {
    public enum Ink: Character, Sendable, CaseIterable {
        case body = "b"
        case rim = "r"
        case eye = "e"
        case stripe = "s"
        case nose = "n"
    }

    public struct Pixel: Sendable, Equatable {
        public let x: Int
        public let y: Int
        public let ink: Ink
    }

    /// Stable name, so the interface can cache what it builds from a frame.
    public let id: String
    public let width: Int
    public let height: Int
    public let pixels: [Pixel]

    /// `.` is empty; every other character must be an `Ink`. The rows are
    /// literals in this package, so a bad one is a programmer's mistake.
    init(_ id: String, _ rows: [String]) {
        switch Self.parse(id, rows) {
        case .success(let sprite): self = sprite
        case .failure(let error): fatalError("built-in sprite \(id) is malformed: \(error)")
        }
    }

    private init(id: String, width: Int, height: Int, pixels: [Pixel]) {
        self.id = id
        self.width = width
        self.height = height
        self.pixels = pixels
    }

    /// Reads a frame someone else drew. `place` names it in the error, so a
    /// person can find the broken frame without reading this code.
    static func parse(
        _ id: String, _ rows: [String], place: String = ""
    ) -> Result<PetSprite, PetFileError> {
        guard let width = rows.first?.count, width > 0, rows.allSatisfy({ $0.count == width }) else {
            return .failure(.ragged(place))
        }
        var pixels: [Pixel] = []
        for (y, row) in rows.enumerated() {
            for (x, character) in row.enumerated() where character != "." {
                guard let ink = Ink(rawValue: character) else {
                    return .failure(.unknownInk(place, String(character)))
                }
                pixels.append(Pixel(x: x, y: y, ink: ink))
            }
        }
        return .success(PetSprite(id: id, width: width, height: rows.count, pixels: pixels))
    }
}

/// Every frame the two built-in pets have, drawn from the corner sketch:
/// a dark silhouette, a lit rim and glowing eyes.
public enum PetFrames {
    // MARK: Котёнок

    static let catSitRows = [
        "...r.......r........",
        "..rbr.....rbr.......",
        "..rbbr...rbbr.......",
        "..rbbbrrrbbbr.......",
        "..rbbbbbbbbbr.......",
        ".rbbebbbbbebbr......",
        ".rbbebbbbbebbr......",
        ".rbbbbbnbbbbbr......",
        "..rbbbbbbbbbr.......",
        "...rbbbbbbbr........",
        "..rbbbbbbbbbr.......",
        ".rbbbbbbbbbbbr......",
        ".rbbbbbbbbbbbr...rr.",
        ".rbbbbbbbbbbbr..rbbr",
        ".rbbbbbbbbbbbr.rbbr.",
        ".rbbbbbbbbbbbrrbbr..",
        ".rbbrbbbbbrbbbbbr...",
        "..rr.rrrrr.rrrrr....",
    ]

    public static let catSit = PetSprite("cat.sit", catSitRows)
    /// Хвост в другую сторону: сидящий кот им поводит.
    public static let catSitTail = PetSprite(
        "cat.sit.tail",
        catSitRows.enumerated().map { index, row in
            let tail = ["..rr..", ".rbbr.", "rbbr..", "bbr..."]
            return (12...15).contains(index) ? String(row.prefix(14)) + tail[index - 12] : row
        })
    public static let catBlink = PetSprite(
        "cat.blink", catSitRows.map { $0.replacingOccurrences(of: "e", with: "b") })

    public static let catWalk = [
        PetSprite(
            "cat.walk.1",
            [
                "r...r.................",
                "rbrrbr................",
                "rbbbbbr...............",
                "rbebbbbr..............",
                "rnbbbbbbrrrrrrrrrr..r.",
                ".rbbbbbbbbbbbbbbbbrrbr",
                "..rbbbbbbbbbbbbbbbbbr.",
                "..rbbbbbbbbbbbbbbbbr..",
                "...rbbbbbbbbbbbbbbr...",
                "...rbbr.rrrrrr.rbbr...",
                "..rbr...........rbr...",
                "..rr.............rr...",
            ]),
        PetSprite(
            "cat.walk.2",
            [
                "r...r.................",
                "rbrrbr................",
                "rbbbbbr...............",
                "rbebbbbr..............",
                "rnbbbbbbrrrrrrrrrr....",
                ".rbbbbbbbbbbbbbbbbrr..",
                "..rbbbbbbbbbbbbbbbbbrr",
                "..rbbbbbbbbbbbbbbbbr.r",
                "...rbbbbbbbbbbbbbbr...",
                "....rbbrrrrrrrrrbbr...",
                "....rbr........rbr....",
                ".....rr........rr.....",
            ]),
    ]

    public static let catSleep = PetSprite(
        "cat.sleep",
        [
            "........rrrrrr......",
            ".....rrrbbbbbbrr....",
            "...rrbbbbbbbbbbbr...",
            "..rbbbbbbbbbbbbbbr..",
            ".rbr.rbbbbbbbbbbbbr.",
            ".rbbrbbbbbbbbbbbbbr.",
            "rbbbbbbbbbbbbbbbbr..",
            "rbrrbbbbbbbbbbbrrr..",
            ".rbbbbbbbbbbbbbbbr..",
            "..rrrrrrrrrrrrrrr...",
        ])

    // MARK: Сахарный поссум

    static let gliderSitRows = [
        "r..............r..",
        "rbr...........rbr.",
        ".rbrrrrrrrrrrrbr..",
        ".rbbbbbbsbbbbbbr..",
        "rbbbbbbbsbbbbbbbr.",
        "rbbeebbbsbbbeebbr.",
        "rbbeebbbsbbbeebbr.",
        "rbbbbbbbnbbbbbbbr.",
        ".rbbbbbbbbbbbbbr..",
        "..rbbbbbbbbbbbr...",
        "..rbbbbbbbbbbbr.rr",
        "..rbbbbbbbbbbbrrbr",
        "...rbbbbbbbbbrbbr.",
        "....rrrrrrrrr.rr..",
    ]

    public static let gliderSit = PetSprite("glider.sit", gliderSitRows)
    public static let gliderBlink = PetSprite(
        "glider.blink", gliderSitRows.map { $0.replacingOccurrences(of: "e", with: "b") })

    /// Перепонка расправлена и чуть подобрана: два кадра дают взмах.
    public static let gliderGlide = [
        PetSprite(
            "glider.glide.1",
            [
                "..........r....r..........",
                ".........rbrrrrbr.........",
                "rrr......rbebbebr......rrr",
                "rbbrrr...rbbsbbbr...rrrbbr",
                ".rbbbbrrrrbbsbbbrrrrbbbbr.",
                "..rbbbbbbbbbsbbbbbbbbbbr..",
                "...rbbbbbbbbsbbbbbbbbbr...",
                "....rbbbbbbbsbbbbbbbbr....",
                ".....rrbbbbbbbbbbbbrr.....",
                ".......rrbbbbbbbbrr.......",
                ".........rrbbbbrr.........",
                "...........rbbr...........",
                "...........rbbr...........",
                "............rr............",
            ]),
        PetSprite(
            "glider.glide.2",
            [
                "..........r....r..........",
                ".........rbrrrrbr.........",
                "..rr.....rbebbebr.....rr..",
                "..rbrrr..rbbsbbbr..rrrbr..",
                "...rbbbrrrbbsbbbrrrbbbr...",
                "...rbbbbbbbbsbbbbbbbbbr...",
                "....rbbbbbbbsbbbbbbbbr....",
                ".....rbbbbbbsbbbbbbbr.....",
                "......rrbbbbbbbbbbrr......",
                "........rrbbbbbbrr........",
                ".........rrbbbbrr.........",
                "...........rbbr...........",
                "...........rbbr...........",
                "............rr............",
            ]),
    ]

    /// В дупле видна только свёрнутая спина с ушами.
    public static let gliderSleep = PetSprite(
        "glider.sleep",
        [
            "..rrrrrrr..",
            ".rbbbbbbbr.",
            "rbbrrbrrbbr",
            "rbbbbbbbbbr",
            ".rbbbbbbbr.",
            "..rrrrrrr..",
        ])

    public static var all: [PetSprite] {
        [catSit, catSitTail, catBlink, catSleep, gliderSit, gliderBlink, gliderSleep]
            + catWalk + gliderGlide
    }
}
