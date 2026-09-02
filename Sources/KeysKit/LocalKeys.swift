public import CryptoKit
public import Foundation
public import HostsKit

/// A key pair sitting in `~/.ssh`, seen from its public half.
///
/// Only the `.pub` file is read: the private key never leaves disk and is
/// never parsed here. What the person calls "the key with the user" is the
/// comment OpenSSH wrote into the public file — usually `user@host` or a
/// deploy label — so that is surfaced as-is rather than invented.
public struct LocalKey: Identifiable, Hashable, Sendable {
    /// Path of the private key (the `.pub` is this plus `.pub`).
    public var id: String
    public var name: String
    public var algorithm: String
    public var comment: String?
    public var fingerprint: String
    public var bits: Int?
    /// Whether the private half is present next to the `.pub`.
    public var hasPrivate: Bool

    public init(
        id: String, name: String, algorithm: String, comment: String?,
        fingerprint: String, bits: Int?, hasPrivate: Bool
    ) {
        self.id = id
        self.name = name
        self.algorithm = algorithm
        self.comment = comment
        self.fingerprint = fingerprint
        self.bits = bits
        self.hasPrivate = hasPrivate
    }

    public var weakness: String? {
        if algorithm == "ssh-dss" { return "DSA — устарел и небезопасен" }
        if algorithm == "ssh-rsa", let bits, bits < 3072 { return "RSA \(bits) бит — короче 3072" }
        return nil
    }
}

public enum LocalKeys {
    public static func directory() -> String { NSHomeDirectory() + "/.ssh" }

    /// Turns one `.pub` file into a key. Pure: takes the contents, not a path,
    /// so it can be tested without touching disk.
    public static func parse(
        privatePath: String, publicText: String, hasPrivate: Bool
    ) -> LocalKey? {
        // A `.pub` file is a single authorized_keys line, so reuse that parser.
        guard let parsed = AuthorizedKeysFile.parse(publicText).first else { return nil }
        let name = (privatePath as NSString).lastPathComponent
        return LocalKey(
            id: privatePath,
            name: name,
            algorithm: parsed.algorithm,
            comment: parsed.comment,
            fingerprint: parsed.fingerprint,
            bits: parsed.bits,
            hasPrivate: hasPrivate
        )
    }

    /// Reads every `*.pub` under `~/.ssh`. The one place that does I/O; the work
    /// above is pure. Unreadable or unparseable files are skipped, not faked.
    public static func scan(in directory: String = directory()) -> [LocalKey] {
        let manager = FileManager.default
        guard let names = try? manager.contentsOfDirectory(atPath: directory) else { return [] }
        return names.filter { $0.hasSuffix(".pub") }.sorted().compactMap { pubName in
            let pubPath = directory + "/" + pubName
            // `try?` here is deliberate: a key we cannot read is simply not
            // shown — it is not an error the person needs to act on.
            guard let text = try? String(contentsOfFile: pubPath, encoding: .utf8) else {
                return nil
            }
            let privatePath = String(pubPath.dropLast(4))
            return parse(
                privatePath: privatePath,
                publicText: text,
                hasPrivate: manager.fileExists(atPath: privatePath)
            )
        }
    }
}

public extension KnownHost {
    /// A host we trusted once, offered as a host we could reconnect to.
    ///
    /// Hashed entries are refused: their name cannot be recovered, and a host
    /// without an address is not a host. Certificate-authority and revoked
    /// markers are refused too — they are trust rules, not machines.
    func asServerHost() -> ServerHost? {
        guard let host, marker == nil else { return nil }
        // A single line can list `name,1.2.3.4` — the first token is enough.
        let address = host.split(separator: ",").first.map(String.init) ?? host
        var name = address
        var port = 22
        // `[host]:2222` — a non-default port is worth keeping.
        if address.hasPrefix("["), let close = address.firstIndex(of: "]") {
            name = String(address[address.index(after: address.startIndex)..<close])
            let tail = address[address.index(after: close)...]
            if tail.hasPrefix(":"), let parsed = Int(tail.dropFirst()) { port = parsed }
        }
        return ServerHost(
            name: name, address: name, port: port, user: NSUserName(),
            tags: ["known-hosts"]
        )
    }
}

public extension KnownHostsFile {
    /// Known-hosts as a deduplicated host list. One machine has several keys —
    /// ed25519, rsa, ecdsa — and each is its own line, so the raw parse repeats
    /// every host; here they collapse to one, and hashed or revoked lines drop
    /// out via `asServerHost`.
    static func servers(_ text: String) -> [ServerHost] {
        var seen: Set<String> = []
        var result: [ServerHost] = []
        for host in parse(text) {
            guard let server = host.asServerHost() else { continue }
            let key = "\(server.address):\(server.port)"
            if seen.insert(key).inserted { result.append(server) }
        }
        return result
    }
}
