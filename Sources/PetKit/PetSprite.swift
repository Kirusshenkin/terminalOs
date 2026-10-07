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
        guard let width = rows.first?.count, rows.allSatisfy({ $0.count == width }) else {
            fatalError("sprite \(id): every row must have the same width")
        }
        var pixels: [Pixel] = []
        for (y, row) in rows.enumerated() {
            for (x, character) in row.enumerated() where character != "." {
                guard let ink = Ink(rawValue: character) else {
                    fatalError("sprite \(id): unknown ink \(character) at \(x),\(y)")
                }
                pixels.append(Pixel(x: x, y: y, ink: ink))
            }
        }
        self.id = id
        self.width = width
        self.height = rows.count
        self.pixels = pixels
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
