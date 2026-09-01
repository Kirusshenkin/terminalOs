public import Foundation
public import PhosphorCore

/// An RGB colour stored independently of any UI framework.
public struct RGBA: Codable, Hashable, Sendable {
    public var red: Double, green: Double, blue: Double, alpha: Double

    public init(red: Double, green: Double, blue: Double, alpha: Double = 1) {
        self.red = red; self.green = green; self.blue = blue; self.alpha = alpha
    }

    /// Parses `#rrggbb` or `#rrggbbaa`.
    public init?(hex string: String) {
        var text = string.trimmingCharacters(in: .whitespaces)
        if text.hasPrefix("#") { text.removeFirst() }
        guard text.count == 6 || text.count == 8, let value = UInt32(text, radix: 16) else { return nil }
        if text.count == 6 {
            self.init(
                red: Double((value >> 16) & 0xFF) / 255,
                green: Double((value >> 8) & 0xFF) / 255,
                blue: Double(value & 0xFF) / 255
            )
        } else {
            self.init(
                red: Double((value >> 24) & 0xFF) / 255,
                green: Double((value >> 16) & 0xFF) / 255,
                blue: Double((value >> 8) & 0xFF) / 255,
                alpha: Double(value & 0xFF) / 255
            )
        }
    }

    /// Цвет из литерала, известного на этапе написания кода.
    ///
    /// Существует, чтобы встроенные палитры не были усыпаны `!`: непарсящийся
    /// литерал — это опечатка автора, и она даёт видимый чёрный, а не падение
    /// у пользователя.
    public static func literal(_ hex: String) -> RGBA {
        RGBA(hex: hex) ?? RGBA(red: 0, green: 0, blue: 0)
    }

    public var hex: String {
        String(
            format: "#%02X%02X%02X",
            Int((red * 255).rounded()), Int((green * 255).rounded()), Int((blue * 255).rounded()))
    }
}

/// A colour scheme plus the glass on top of it.
public struct Theme: Codable, Identifiable, Hashable, Sendable {
    public var id: String
    public var name: String
    /// The sixteen ANSI colours — the unit of exchange between terminals.
    public var ansi: [RGBA]
    public var foreground: RGBA
    public var background: RGBA
    public var cursor: RGBA
    public var selection: RGBA
    /// Scanline, glow and vignette strength, 0…1.
    public var scanlines: Double
    public var glow: Double
    public var vignette: Double
    public var windowOpacity: Double

    public init(
        id: String, name: String, ansi: [RGBA],
        foreground: RGBA, background: RGBA, cursor: RGBA, selection: RGBA,
        scanlines: Double = 0, glow: Double = 0, vignette: Double = 0, windowOpacity: Double = 1
    ) {
        self.id = id
        self.name = name
        self.ansi = ansi
        self.foreground = foreground
        self.background = background
        self.cursor = cursor
        self.selection = selection
        self.scanlines = scanlines
        self.glow = glow
        self.vignette = vignette
        self.windowOpacity = windowOpacity
    }

    public var isValid: Bool { ansi.count == 16 }
}

/// Themes that ship with the app.
public enum BuiltInThemes {
    private static func palette(_ hexes: [String]) -> [RGBA] {
        hexes.map(RGBA.literal)
    }

    public static let phosphor = Theme(
        id: "phosphor", name: "Фосфор",
        ansi: palette([
            "#0B1A0F", "#C4703A", "#3E9E5A", "#C9A227", "#2E7A86", "#7C5FA0", "#2F8A86", "#8DB894",
            "#1E5C33", "#E0673F", "#5BE87F", "#E2C15A", "#4FA9C4", "#AC84C0", "#58ABA3", "#9DF7B4",
        ]),
        foreground: RGBA.literal("#5BE87F"), background: RGBA.literal("#071008"),
        cursor: RGBA.literal("#5BE87F"), selection: RGBA.literal("#1E5C33"),
        scanlines: 0.6, glow: 0.45, vignette: 0.7
    )

    public static let amber = Theme(
        id: "amber", name: "Янтарь",
        ansi: palette([
            "#1A1208", "#C4433A", "#7C8F3B", "#E8A33D", "#8A6A2E", "#A06A7C", "#8A8A3E", "#D9B98A",
            "#4A3410", "#E0673F", "#B0C060", "#F2BC6A", "#C09A5A", "#C08AA0", "#B0B060", "#F4E3C0",
        ]),
        foreground: RGBA.literal("#E8A33D"), background: RGBA.literal("#100B03"),
        cursor: RGBA.literal("#F2BC6A"), selection: RGBA.literal("#4A3410"),
        scanlines: 0.6, glow: 0.45, vignette: 0.7
    )

    public static let ice = Theme(
        id: "ice", name: "Лёд",
        ansi: palette([
            "#0C1522", "#C45A5A", "#5AAE8C", "#C4B26A", "#4F8FCC", "#8C7CC4", "#4FB0C4", "#A8C4D8",
            "#22354A", "#E07A7A", "#7AD4AE", "#E8D48C", "#7AB4EC", "#B0A0E8", "#7AD0E8", "#DCEEFF",
        ]),
        foreground: RGBA.literal("#8FC7E8"), background: RGBA.literal("#070B12"),
        cursor: RGBA.literal("#BFE3FF"), selection: RGBA.literal("#173048"),
        scanlines: 0.25, glow: 0.3, vignette: 0.5
    )

    /// Red on purpose: the window you are deleting a container in should be
    /// impossible to mistake for staging.
    public static let ruby = Theme(
        id: "ruby", name: "Рубин · прод",
        ansi: palette([
            "#1E0A10", "#E0483F", "#7CA05A", "#D9A03A", "#8A5F9E", "#B05A8C", "#6E8AA0", "#D8A8B0",
            "#4A1520", "#FF6B5C", "#A0C47A", "#F2C15A", "#B08ACC", "#D080B0", "#8AB0C4", "#FFD8DE",
        ]),
        foreground: RGBA.literal("#E88A9A"), background: RGBA.literal("#12060A"),
        cursor: RGBA.literal("#FFB3C0"), selection: RGBA.literal("#4A1520"),
        scanlines: 0.5, glow: 0.4, vignette: 0.7
    )

    /// Unbreakable's foil: translucent, blurred, purple. Hidden in plain sight.
    public static let glass = Theme(
        id: "glass", name: "Стекло",
        ansi: palette([
            "#150F1E", "#B4566E", "#6E9E7C", "#B8975A", "#6F63B8", "#9A63C4", "#5F9AA8", "#C6BEDA",
            "#2A2140", "#D4788E", "#8CC49A", "#DCBB7A", "#9186E0", "#C089E8", "#83C4D2", "#EDE6FA",
        ]),
        foreground: RGBA.literal("#C6BEDA"), background: RGBA.literal("#150F1E"),
        cursor: RGBA.literal("#C089E8"), selection: RGBA.literal("#2A2140"),
        scanlines: 0.1, glow: 0.25, vignette: 0.45, windowOpacity: 0.82
    )

    public static let all: [Theme] = [phosphor, amber, ice, ruby, glass]

    public static func theme(id: String) -> Theme {
        all.first { $0.id == id } ?? phosphor
    }
}

/// Imports colour schemes written for other terminals.
public enum ThemeImport {
    /// Reads an iTerm2 `.itermcolors` file: a plist of float components.
    public static func iTerm(data: Data, id: String, name: String) throws -> Theme? {
        guard
            let root = try PropertyListSerialization
                .propertyList(from: data, format: nil) as? [String: [String: Any]]
        else { return nil }

        func colour(_ key: String) -> RGBA? {
            guard let entry = root[key],
                let red = entry["Red Component"] as? Double,
                let green = entry["Green Component"] as? Double,
                let blue = entry["Blue Component"] as? Double
            else { return nil }
            return RGBA(red: red, green: green, blue: blue)
        }

        let ansi = (0..<16).compactMap { colour("Ansi \($0) Color") }
        guard ansi.count == 16,
            let foreground = colour("Foreground Color"),
            let background = colour("Background Color")
        else { return nil }

        return Theme(
            id: id, name: name, ansi: ansi,
            foreground: foreground, background: background,
            cursor: colour("Cursor Color") ?? foreground,
            selection: colour("Selection Color") ?? background
        )
    }
}
