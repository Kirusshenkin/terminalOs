public import HostsKit

/// Reads what `ssh` printed on failure and decides what went wrong — and where.
///
/// Through a bastion two ssh processes share one stderr: the nested one that
/// reaches the bastion and the outer one that reaches the host behind it.
/// "Permission denied" means a different fix depending on whose it is, so each
/// line is attributed by the address it names.
public enum SSHFailure {
    public static func classify(
        _ stderr: String, host: ServerHost, bastions: [ServerHost] = []
    ) -> TransportError? {
        for line in stderr.lowercased().split(whereSeparator: \.isNewline) {
            let line = String(line)
            guard let owner = owner(of: line, host: host, bastions: bastions),
                let failure = kind(of: line, address: owner.address)
            else { continue }
            return owner.id == host.id ? failure : .bastion(owner, failure)
        }
        return nil
    }

    /// What a single line reports, regardless of which host it is about.
    static func kind(of line: String, address: String) -> TransportError? {
        if line.contains("permission denied") { return .authenticationFailed }
        // «No ED25519 host key is known for …» — первый визит, а не подмена.
        if line.contains("host key is known") { return .hostKeyUnknown }
        if line.contains("host key") && line.contains("changed") { return .hostKeyChanged }
        let unreachable = ["could not resolve", "timed out", "connection refused", "no route to host"]
        if unreachable.contains(where: line.contains) { return .hostUnreachable(address) }
        return nil
    }

    /// The host a line is about. A bastion only when its address is named and
    /// the target's is not: lines without an address belong to the target, as
    /// they did before bastions existed.
    static func owner(of line: String, host: ServerHost, bastions: [ServerHost]) -> ServerHost? {
        if mentions(line, host.address) { return host }
        if let bastion = bastions.last(where: { mentions(line, $0.address) }) { return bastion }
        return host
    }

    /// Whole-token match, so `10.0.0.1` is not found inside `10.0.0.12`.
    static func mentions(_ line: String, _ address: String) -> Bool {
        let needle = address.lowercased()
        guard !needle.isEmpty else { return false }
        var searchStart = line.startIndex
        while let found = line.range(of: needle, range: searchStart..<line.endIndex) {
            let before =
                found.lowerBound == line.startIndex ? nil : line[line.index(before: found.lowerBound)]
            let after = found.upperBound == line.endIndex ? nil : line[found.upperBound]
            if !isAddressCharacter(before), !isAddressCharacter(after) { return true }
            searchStart = found.upperBound
        }
        return false
    }

    private static func isAddressCharacter(_ character: Character?) -> Bool {
        guard let character else { return false }
        return character.isLetter || character.isNumber || character == "." || character == "-"
    }
}
