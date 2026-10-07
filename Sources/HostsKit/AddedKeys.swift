public import Foundation

/// A key that Phosphor itself added to a server's `authorized_keys`.
///
/// The file has no dates, so "when was this key added" can only be answered
/// for keys that went through us. The comment on the server is left alone: it
/// is the person's text, and rewriting it would be a hidden change.
public struct AddedKey: Codable, Hashable, Sendable {
    public var fingerprint: String
    public var hostID: ServerHost.ID
    public var addedAt: Date

    public init(fingerprint: String, hostID: ServerHost.ID, addedAt: Date) {
        self.fingerprint = fingerprint
        self.hostID = hostID
        self.addedAt = addedAt
    }
}

extension HostBook {
    /// Ceiling on the record: every buffer is bounded. Hundreds of keys added
    /// by hand is already far beyond how the app is used.
    public static let addedKeysLimit = 500

    public mutating func recordKeyAdded(fingerprint: String, host: ServerHost.ID, at date: Date = Date()) {
        addedKeys.removeAll { $0.fingerprint == fingerprint && $0.hostID == host }
        addedKeys.append(AddedKey(fingerprint: fingerprint, hostID: host, addedAt: date))
        if addedKeys.count > Self.addedKeysLimit {
            addedKeys.removeFirst(addedKeys.count - Self.addedKeysLimit)
        }
    }

    /// A removed key forgets its date: added again later, it is a new addition.
    public mutating func forgetKey(fingerprint: String, host: ServerHost.ID) {
        addedKeys.removeAll { $0.fingerprint == fingerprint && $0.hostID == host }
    }

    public func keyAddedDate(fingerprint: String, host: ServerHost.ID) -> Date? {
        addedKeys.last { $0.fingerprint == fingerprint && $0.hostID == host }?.addedAt
    }
}
