public import Foundation

/// Hides values that must never reach the screen, the log or an MCP answer.
public enum Redaction {
    /// Environment variable names holding secrets are recognised by these
    /// fragments. Matching is on the name; values are never inspected.
    private static let secretMarkers = ["PASS", "SECRET", "TOKEN", "KEY", "CREDENTIAL", "PRIVATE", "AUTH"]

    /// Whether a variable of this name should have its value hidden.
    public static func isSecret(name: String) -> Bool {
        let upper = name.uppercased()
        return secretMarkers.contains { upper.contains($0) }
    }

    /// The value to display in place of a secret.
    public static let mask = "••••••••"

    /// Masks the values of secret-looking variables in a name/value list.
    public static func apply(to variables: [(name: String, value: String)]) -> [(name: String, value: String)]
    {
        variables.map { isSecret(name: $0.name) ? ($0.name, mask) : $0 }
    }
}
