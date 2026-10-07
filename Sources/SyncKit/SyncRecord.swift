public import Foundation

/// When a change happened, in a way every machine agrees on.
///
/// Wall clocks on two Macs drift apart, and "the later edit wins" with plain
/// timestamps would let a machine with a fast clock win forever. A hybrid
/// logical clock stays close to wall time but never goes backwards and always
/// moves past anything it has seen, so causality is kept even when clocks lie.
public struct Stamp: Codable, Sendable, Hashable, Comparable {
    /// Milliseconds since 1970, or later if the machine has seen a later stamp.
    public var millis: Int64
    /// Orders events within the same millisecond.
    public var counter: UInt32
    /// Which machine made the change: the last tie-breaker, so two machines
    /// never produce equal stamps.
    public var machine: String

    public init(millis: Int64, counter: UInt32, machine: String) {
        self.millis = millis
        self.counter = counter
        self.machine = machine
    }

    public static func < (lhs: Stamp, rhs: Stamp) -> Bool {
        (lhs.millis, lhs.counter, lhs.machine) < (rhs.millis, rhs.counter, rhs.machine)
    }
}

/// A hybrid logical clock for one machine.
public struct HybridClock: Sendable {
    public let machine: String
    public private(set) var last: Stamp

    public init(machine: String, last: Stamp? = nil) {
        self.machine = machine
        self.last = last ?? Stamp(millis: 0, counter: 0, machine: machine)
    }

    /// A stamp for a change made here, now.
    public mutating func tick(now: Int64) -> Stamp {
        last =
            now > last.millis
            ? Stamp(millis: now, counter: 0, machine: machine)
            : Stamp(millis: last.millis, counter: last.counter + 1, machine: machine)
        return last
    }

    /// Moves past a stamp that came from another machine, so the next local
    /// change is ordered after it.
    public mutating func observe(_ remote: Stamp, now: Int64) {
        let millis = max(now, last.millis, remote.millis)
        let counter: UInt32 =
            switch (millis == last.millis, millis == remote.millis) {
            case (true, true): max(last.counter, remote.counter) + 1
            case (true, false): last.counter + 1
            case (false, true): remote.counter + 1
            case (false, false): 0
            }
        last = Stamp(millis: millis, counter: counter, machine: machine)
    }
}

/// One synced item: a host, a group, a snippet, a forward, a key date.
///
/// Items sync one by one, not as one profile blob: two machines editing
/// different hosts at the same time both keep their edit. The payload is the
/// item's own JSON; nil means it was deleted.
public struct SyncRecord: Codable, Sendable, Equatable {
    public enum Kind: String, Codable, Sendable, CaseIterable {
        case host, group, snippet, forward, addedKey
    }

    public var kind: Kind
    public var id: String
    public var stamp: Stamp
    public var payload: Data?

    public init(kind: Kind, id: String, stamp: Stamp, payload: Data?) {
        self.kind = kind
        self.id = id
        self.stamp = stamp
        self.payload = payload
    }

    /// A deletion mark: kept for a while so other machines learn about it
    /// instead of bringing the item back.
    public var isDeleted: Bool { payload == nil }

    public var key: String { "\(kind.rawValue)/\(id)" }
}

/// How two machines' records become one list.
public enum SyncMerge {
    /// How long a deletion mark is kept. A machine offline for longer than
    /// this can bring a deleted item back — the price of not keeping marks
    /// forever.
    public static let tombstoneLifetime: Int64 = 90 * 24 * 3_600 * 1_000

    /// The later change wins, item by item. Deletion marks older than
    /// `tombstoneLifetime` are dropped.
    public static func merge(_ local: [SyncRecord], _ remote: [SyncRecord], now: Int64) -> [SyncRecord] {
        var winners: [String: SyncRecord] = [:]
        for record in local + remote {
            if let current = winners[record.key], current.stamp >= record.stamp { continue }
            winners[record.key] = record
        }
        return winners.values
            .filter { !$0.isDeleted || now - $0.stamp.millis < tombstoneLifetime }
            .sorted { $0.key < $1.key }
    }
}
