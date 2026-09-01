public import Foundation

/// Formatting helpers shared across panels.
///
/// Kept dependency-free so parsing targets can use them without pulling in UI.
public enum ByteFormat {
    private static let units = ["Б", "КБ", "МБ", "ГБ", "ТБ", "ПБ"]

    /// Human readable size using binary steps, one decimal below 10.
    public static func size(_ bytes: Int64) -> String {
        guard bytes > 0 else { return "0 Б" }
        var value = Double(bytes)
        var index = 0
        while value >= 1024, index < units.count - 1 {
            value /= 1024
            index += 1
        }
        let digits = (value < 10 && index > 0) ? 1 : 0
        return String(format: "%.\(digits)f %@", value, units[index])
    }

    /// Percentage clamped to 0...100 with no decimals.
    public static func percent(_ fraction: Double) -> String {
        let clamped = min(max(fraction, 0), 1)
        return "\(Int((clamped * 100).rounded())) %"
    }

    /// Compact duration: `41д 6ч`, `2ч 14м`, `48с`.
    public static func duration(seconds: Int) -> String {
        let days = seconds / 86_400
        let hours = (seconds % 86_400) / 3_600
        let minutes = (seconds % 3_600) / 60
        if days > 0 { return hours > 0 ? "\(days)д \(hours)ч" : "\(days)д" }
        if hours > 0 { return minutes > 0 ? "\(hours)ч \(minutes)м" : "\(hours)ч" }
        if minutes > 0 { return "\(minutes)м" }
        return "\(seconds)с"
    }
}
