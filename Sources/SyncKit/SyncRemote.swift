public import Foundation
public import PhosphorCore

/// The shared folder on the person's own server, reached by running commands.
///
/// No network code here: `run` is handed in — ssh in the app, a local shell
/// in tests. The folder holds three things: `snapshot.json` (signed),
/// `revision` (a plain number for compare-and-swap, since a shell cannot read
/// JSON) and `requests/<id>.json` from machines asking to be let in.
public struct SyncRemote: Sendable {
    public typealias Run = @Sendable (_ command: String, _ input: Data?) async throws -> CommandResult

    /// What storage holds right now.
    public struct View: Sendable, Equatable {
        public var revision: UInt64
        public var snapshot: SignedSnapshot?
        public var requests: [SyncMachine]
    }

    /// Exit code of a write that lost the race: someone else wrote first.
    static let busyStatus: Int32 = 75

    private let run: Run
    private let folder: String

    /// - Parameter folder: relative to the home directory on the server.
    public init(folder: String = ".phosphor-sync", run: @escaping Run) {
        self.folder = folder
        self.run = run
    }

    private var root: String { "d=\"$HOME\"/\(Shell.quote(folder))" }

    public func read() async throws -> View {
        let command = """
            \(root); [ -d "$d" ] || { echo 'rev 0'; exit 0; }
            printf 'rev %s\\n' "$(cat "$d/revision" 2>/dev/null || echo 0)"
            [ -f "$d/snapshot.json" ] && { printf 'snap '; cat "$d/snapshot.json"; echo; }
            for f in "$d"/requests/*.json; do [ -f "$f" ] && { printf 'req '; cat "$f"; echo; }; done
            exit 0
            """
        return try Self.parse(try await checked(command, input: nil))
    }

    /// Writes a snapshot if storage still holds `expecting`; otherwise
    /// throws `busy` and the caller reads again and merges.
    ///
    /// The lock is a directory, since `mkdir` is atomic on every system and
    /// `flock` is missing on a Mac server. A lock left by a write that died
    /// halfway is taken over after two minutes.
    ///
    /// Two writers can both find the same stale lock and both go ahead. That
    /// costs one overwritten write, not lost data: the losing machine still
    /// has its records and their stamps, and its next round puts them back.
    ///
    /// The size is checked before the snapshot replaces the old one: a
    /// connection cut mid-upload ends `cat` as cleanly as a full one, and a
    /// truncated snapshot would stop sync on every machine.
    public func write(
        _ signed: SignedSnapshot, revision: UInt64, expecting: UInt64, consuming requests: [String] = []
    ) async throws {
        let body: Data
        do { body = try JSONEncoder().encode(signed) } catch { throw SyncError.malformed("snapshot") }
        let consumed = try requests.map { id throws(SyncError) in "\"$d/requests/\"\(try Self.fileName(id))" }
        let command = """
            \(root); umask 077; mkdir -p "$d/requests" || exit 1
            if [ -d "$d/lock" ] && [ -n "$(find "$d/lock" -maxdepth 0 -mmin +2 2>/dev/null)" ]; then
              rmdir "$d/lock" 2>/dev/null
            fi
            mkdir "$d/lock" 2>/dev/null || exit \(Self.busyStatus)
            if [ "$(cat "$d/revision" 2>/dev/null || echo 0)" != '\(expecting)' ]; then
              rmdir "$d/lock"; exit \(Self.busyStatus)
            fi
            cat > "$d/snapshot.tmp"
            if [ "$(wc -c < "$d/snapshot.tmp" | tr -d ' ')" != '\(body.count)' ]; then
              rm -f "$d/snapshot.tmp"; rmdir "$d/lock"; echo 'upload cut short' >&2; exit 1
            fi
            mv "$d/snapshot.tmp" "$d/snapshot.json" \\
              && printf '%s' '\(revision)' > "$d/revision.tmp" && mv "$d/revision.tmp" "$d/revision"
            s=$?
            \(consumed.isEmpty ? ":" : "rm -f " + consumed.joined(separator: " "))
            rmdir "$d/lock"; exit $s
            """
        _ = try await checked(command, input: body)
    }

    /// Leaves this machine's request to be let in.
    public func request(_ machine: SyncMachine) async throws {
        let body: Data
        do { body = try JSONEncoder().encode(machine) } catch { throw SyncError.malformed("request") }
        let file = try Self.fileName(machine.id)
        let command = """
            \(root); umask 077; mkdir -p "$d/requests" || exit 1
            cat > "$d/requests/.\(file).tmp" && mv "$d/requests/.\(file).tmp" "$d/requests/"\(file)
            """
        _ = try await checked(command, input: body)
    }

    /// Removes a request without letting the machine in.
    public func dismiss(_ id: String) async throws {
        _ = try await checked("\(root); rm -f \"$d/requests/\"\(try Self.fileName(id))", input: nil)
    }

    private func checked(_ command: String, input: Data?) async throws -> String {
        let result = try await run(command, input)
        if result.status == Self.busyStatus { throw SyncError.busy }
        guard result.succeeded else {
            throw SyncError.storage(result.stderr.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return result.stdout
    }

    /// Machine ids become file names on the server: only letters, digits and
    /// hyphens get through, so an id from a request cannot walk out of the folder.
    static func fileName(_ id: String) throws(SyncError) -> String {
        guard !id.isEmpty, id.count <= 64,
            id.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-") })
        else { throw .malformed("machine id") }
        return "\(id).json"
    }

    /// Reads the listing. Lines without a known prefix are skipped: a chatty
    /// shell profile on the server must not break sync.
    static func parse(_ output: String) throws(SyncError) -> View {
        var view = View(revision: 0, snapshot: nil, requests: [])
        for line in output.split(whereSeparator: \.isNewline) {
            if line.hasPrefix("rev ") {
                view.revision = UInt64(line.dropFirst(4).trimmingCharacters(in: .whitespaces)) ?? 0
            } else if line.hasPrefix("snap ") {
                do {
                    view.snapshot = try JSONDecoder().decode(
                        SignedSnapshot.self, from: Data(line.dropFirst(5).utf8))
                } catch {
                    throw .malformed("snapshot")
                }
            } else if line.hasPrefix("req ") {
                // Просьбу может оставить кто угодно с доступом к папке: битая
                // или с негодным id просто не показывается, остальным не мешает.
                guard
                    let machine = try? JSONDecoder().decode(
                        SyncMachine.self, from: Data(line.dropFirst(4).utf8)),
                    (try? fileName(machine.id)) != nil
                else { continue }
                view.requests.append(machine)
            }
        }
        return view
    }
}
