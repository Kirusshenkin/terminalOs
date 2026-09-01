public import Foundation
public import HostsKit

/// Hidden nods that never replace information.
///
/// Each one sits *beside* the real figure it reacts to: the badge stands next
/// to the true uptime, the eclipse banner above the true list of dead
/// containers. All of them are local, and one switch turns the lot off.
public struct EasterEggs: Sendable {
    public var enabled: Bool

    public init(enabled: Bool = true) { self.enabled = enabled }

    /// A server that has been up for over a year has earned the title.
    public func unbreakableBadge(uptimeSeconds: Int) -> String? {
        guard enabled, uptimeSeconds > 365 * 86_400 else { return nil }
        return "egg.unbreakable"
    }

    /// Split's Horde is twenty-three personalities; the twenty-third tab.
    public func hordeNotice(tabCount: Int) -> String? {
        guard enabled, tabCount == 23 else { return nil }
        return "egg.horde"
    }

    /// Berserk's Eclipse: when most of a host's containers fall at once.
    public func eclipseBanner(total: Int, down: Int) -> String? {
        guard enabled, total >= 4, down * 2 > total else { return nil }
        return "egg.eclipse"
    }

    /// Running one snippet across every host in a group.
    public func shadowClone(hostCount: Int) -> String? {
        guard enabled, hostCount > 1 else { return nil }
        return "egg.shadowClone"
    }

    /// After the recipe closes password authentication.
    public func firstRule(stepID: String) -> String? {
        guard enabled, stepID == "passwords" else { return nil }
        return "egg.firstRule"
    }

    /// Barney's line, split across the last step and its completion.
    public func waitForIt(isLastStep: Bool) -> String? {
        guard enabled, isLastStep else { return nil }
        return "egg.waitForIt"
    }

    public func legendary(recipeFinished: Bool) -> String? {
        guard enabled, recipeFinished else { return nil }
        return "egg.legendary"
    }
}

/// The Konami code, watched on the lock screen.
public struct KonamiWatcher: Sendable {
    public enum Key: Equatable, Sendable { case up, down, left, right, a, b }

    private static let sequence: [Key] = [.up, .up, .down, .down, .left, .right, .left, .right, .b, .a]
    private var progress: [Key] = []

    public init() {}

    /// Feeds a key; returns true on the final match.
    public mutating func accept(_ key: Key) -> Bool {
        progress.append(key)
        if progress.count > Self.sequence.count { progress.removeFirst() }
        guard progress == Self.sequence else {
            // Keep the longest suffix that could still lead somewhere.
            while !progress.isEmpty, !Self.sequence.starts(with: progress) {
                progress.removeFirst()
            }
            return false
        }
        progress.removeAll()
        return true
    }
}
