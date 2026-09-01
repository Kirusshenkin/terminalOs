public import Foundation

/// Quoting for values that reach a remote shell.
///
/// Every parameter that leaves the app for a server goes through here.
/// String interpolation into a command line is a defect, not a shortcut.
public enum Shell {
    /// Wraps `value` in single quotes, escaping any single quotes it contains.
    public static func quote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: #"'\''"#) + "'"
    }

    /// Joins pre-quoted arguments into one command line.
    public static func line(_ parts: [String]) -> String {
        parts.joined(separator: " ")
    }
}

/// Validation for values used to build remote commands.
public enum Validate {
    private static let labelCharacters = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789-")

    /// A fully qualified domain name, lowercased. Rejects anything a shell or
    /// certificate authority would refuse anyway.
    public static func domain(_ raw: String) -> String? {
        let value = raw.trimmingCharacters(in: .whitespaces).lowercased()
        guard value.count >= 4, value.count <= 253, !value.hasPrefix("-"), !value.hasSuffix(".") else {
            return nil
        }
        let labels = value.split(separator: ".", omittingEmptySubsequences: false)
        guard labels.count >= 2 else { return nil }
        for label in labels {
            guard (1...63).contains(label.count),
                !label.hasPrefix("-"), !label.hasSuffix("-"),
                label.unicodeScalars.allSatisfy(labelCharacters.contains)
            else { return nil }
        }
        return value
    }

    /// A conservative e-mail check: enough to catch typos before certbot does.
    public static func email(_ raw: String) -> String? {
        let value = raw.trimmingCharacters(in: .whitespaces)
        let parts = value.split(separator: "@", omittingEmptySubsequences: false)
        guard parts.count == 2, !parts[0].isEmpty, parts[0].count <= 64,
            domain(String(parts[1])) != nil,
            !value.contains(where: { $0.isWhitespace })
        else { return nil }
        return value
    }

    /// A POSIX host name, used for `hostnamectl`.
    public static func hostname(_ raw: String) -> String? {
        let value = raw.trimmingCharacters(in: .whitespaces).lowercased()
        guard (1...63).contains(value.count), !value.hasPrefix("-"),
            value.unicodeScalars.allSatisfy(labelCharacters.contains)
        else { return nil }
        return value
    }
}
