public import Foundation

/// Formatting helpers shared across panels.
///
/// Kept dependency-free so parsing targets can use them without pulling in UI.
/// Unit names come from outside: the interface passes them from its strings
/// table, so numbers read in the language the person chose.
public enum ByteFormat {
    /// Unit names, smallest first for sizes.
    public struct Units: Sendable {
        public var sizes: [String]
        public var day, hour, minute, second: String

        public init(sizes: [String], day: String, hour: String, minute: String, second: String) {
            self.sizes = sizes
            self.day = day
            self.hour = hour
            self.minute = minute
            self.second = second
        }

        /// Русские единицы — их же видит ИИ-клиент в ответах моста.
        public static let russian = Units(
            sizes: ["Б", "КБ", "МБ", "ГБ", "ТБ", "ПБ"], day: "д", hour: "ч", minute: "м", second: "с")
    }

    /// Human readable size using binary steps, one decimal below 10.
    public static func size(_ bytes: Int64, units: Units = .russian) -> String {
        guard bytes > 0 else { return "0 \(units.sizes[0])" }
        var value = Double(bytes)
        var index = 0
        while value >= 1024, index < units.sizes.count - 1 {
            value /= 1024
            index += 1
        }
        let digits = (value < 10 && index > 0) ? 1 : 0
        return String(format: "%.\(digits)f %@", value, units.sizes[index])
    }

    /// Percentage clamped to 0...100 with no decimals.
    public static func percent(_ fraction: Double) -> String {
        let clamped = min(max(fraction, 0), 1)
        return "\(Int((clamped * 100).rounded())) %"
    }

    /// Compact duration: `41д 6ч`, `2ч 14м`, `48с`.
    public static func duration(seconds: Int, units: Units = .russian) -> String {
        let days = seconds / 86_400
        let hours = (seconds % 86_400) / 3_600
        let minutes = (seconds % 3_600) / 60
        let (d, h, m) = (units.day, units.hour, units.minute)
        if days > 0 { return hours > 0 ? "\(days)\(d) \(hours)\(h)" : "\(days)\(d)" }
        if hours > 0 { return minutes > 0 ? "\(hours)\(h) \(minutes)\(m)" : "\(hours)\(h)" }
        if minutes > 0 { return "\(minutes)\(m)" }
        return "\(seconds)\(units.second)"
    }
}
