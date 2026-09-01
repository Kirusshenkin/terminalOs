public import CryptoKit
public import Foundation
public import PhosphorCore

/// One line of an `authorized_keys` file.
public struct AuthorizedKey: Identifiable, Hashable, Sendable {
    public var id: Int
    /// Options preceding the key, such as `command="…",no-pty`.
    public var options: String?
    public var algorithm: String
    public var base64: String
    public var comment: String?
    /// A line commented out by us counts as disabled rather than removed.
    public var isEnabled: Bool

    /// `SHA256:…` as OpenSSH prints it, computed locally.
    ///
    /// The fingerprint is the SHA-256 of the decoded blob, base64 without
    /// padding — no need to run `ssh-keygen` on the server to learn it.
    public var fingerprint: String {
        guard let blob = Data(base64Encoded: base64) else { return "SHA256:—" }
        let digest = SHA256.hash(data: blob)
        let encoded = Data(digest).base64EncodedString().replacingOccurrences(of: "=", with: "")
        return "SHA256:\(encoded)"
    }

    /// Key size in bits where it can be derived cheaply, else nil.
    public var bits: Int? {
        guard let blob = Data(base64Encoded: base64) else { return nil }
        switch algorithm {
        case "ssh-ed25519": return 256
        case "ecdsa-sha2-nistp256": return 256
        case "ecdsa-sha2-nistp384": return 384
        case "ecdsa-sha2-nistp521": return 521
        case "ssh-rsa":
            // SSH blob: length-prefixed fields; the modulus is the third.
            var offset = 0
            var field = 0
            let bytes = [UInt8](blob)
            while offset + 4 <= bytes.count {
                let length =
                    Int(bytes[offset]) << 24 | Int(bytes[offset + 1]) << 16
                    | Int(bytes[offset + 2]) << 8 | Int(bytes[offset + 3])
                offset += 4
                guard length >= 0, offset + length <= bytes.count else { return nil }
                field += 1
                if field == 3 {
                    var start = offset
                    while start < offset + length, bytes[start] == 0 { start += 1 }
                    return (offset + length - start) * 8
                }
                offset += length
            }
            return nil
        default: return nil
        }
    }

    /// Keys we would rather you replaced.
    public var weakness: String? {
        if algorithm == "ssh-dss" { return "DSA — устарел и небезопасен" }
        if algorithm == "ssh-rsa", let bits, bits < 3072 { return "RSA \(bits) бит — короче 3072" }
        return nil
    }
}

/// Parses and rewrites `authorized_keys` without losing anything it does not
/// understand.
public enum AuthorizedKeysFile {
    private static let knownAlgorithms: Set<String> = [
        "ssh-ed25519", "ssh-rsa", "ssh-dss",
        "ecdsa-sha2-nistp256", "ecdsa-sha2-nistp384", "ecdsa-sha2-nistp521",
        "sk-ssh-ed25519@openssh.com", "sk-ecdsa-sha2-nistp256@openssh.com",
    ]

    public static func parse(_ text: String) -> [AuthorizedKey] {
        var result: [AuthorizedKey] = []
        for (index, rawLine) in text.components(separatedBy: .newlines).enumerated() {
            var line = rawLine.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty else { continue }

            // A line we disabled earlier looks like `#phosphor-disabled <key>`.
            var enabled = true
            if line.hasPrefix("#phosphor-disabled ") {
                enabled = false
                line = String(line.dropFirst("#phosphor-disabled ".count))
            } else if line.hasPrefix("#") {
                continue
            }

            let fields = line.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
            guard let algorithmIndex = fields.firstIndex(where: { knownAlgorithms.contains($0) }),
                algorithmIndex + 1 < fields.count
            else { continue }

            let options =
                algorithmIndex > 0
                ? fields[0..<algorithmIndex].joined(separator: " ")
                : nil
            let comment =
                algorithmIndex + 2 < fields.count
                ? fields[(algorithmIndex + 2)...].joined(separator: " ")
                : nil

            result.append(
                AuthorizedKey(
                    id: index,
                    options: options,
                    algorithm: fields[algorithmIndex],
                    base64: fields[algorithmIndex + 1],
                    comment: comment,
                    isEnabled: enabled
                ))
        }
        return result
    }

    /// Renders keys back to file content, preserving disabled ones as comments.
    public static func render(_ keys: [AuthorizedKey]) -> String {
        keys.map { key in
            var line = ""
            if let options = key.options, !options.isEmpty { line += options + " " }
            line += key.algorithm + " " + key.base64
            if let comment = key.comment, !comment.isEmpty { line += " " + comment }
            return key.isEnabled ? line : "#phosphor-disabled " + line
        }.joined(separator: "\n") + "\n"
    }

    /// Whether removing these keys would leave no way back in.
    ///
    /// Locking yourself out of a server is the one mistake this panel must make
    /// impossible, so the check runs before the write, not after.
    public static func wouldLockOut(
        keys: [AuthorizedKey], removing ids: Set<Int>, currentFingerprint: String?
    ) -> Bool {
        let remaining = keys.filter { !ids.contains($0.id) && $0.isEnabled }
        if remaining.isEmpty { return true }
        if let currentFingerprint {
            return !remaining.contains { $0.fingerprint == currentFingerprint }
        }
        return false
    }

    /// The command that installs new content atomically, with a backup.
    public static func writeCommand(content: String, path: String = "~/.ssh/authorized_keys") -> String {
        let temporary = path + ".phosphor.tmp"
        let backup = path + ".phosphor.bak"
        return """
            cp \(Shell.quote(path)) \(Shell.quote(backup)) 2>/dev/null; \
            cat > \(Shell.quote(temporary)) <<'PHOSPHOR_EOF'
            \(content)
            PHOSPHOR_EOF
            chmod 600 \(Shell.quote(temporary)) && mv \(Shell.quote(temporary)) \(Shell.quote(path))
            """
    }
}
