public import Foundation
public import HostsKit
public import SSHKit

/// Сниппеты и их выполнение.
@MainActor
extension AppModel {
    public var currentGroup: HostGroup? {
        guard let host = book.hosts.first(where: { $0.id == selectedHost }) else { return nil }
        return book.group(for: host)
    }

    public func addSnippet(name: String, command: String) {
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        let trimmedCommand = command.trimmingCharacters(in: .whitespaces)
        guard !trimmedCommand.isEmpty else { return }
        book.snippets.append(
            Snippet(
                name: trimmedName.isEmpty ? String(trimmedCommand.prefix(30)) : trimmedName,
                command: trimmedCommand
            ))
        scheduleSave()
    }

    public func removeSnippet(_ snippet: Snippet) {
        book.snippets.removeAll { $0.id == snippet.id }
        scheduleSave()
    }

    /// Выполняет сниппет на текущем хосте или на всей группе.
    ///
    /// Подстановки экранируются в `Snippet.expand`, поэтому значение из поля не
    /// может дописать вторую команду.
    public func runSnippet(_ snippet: Snippet, values: [String: String], onGroup: Bool) async {
        let command = snippet.expand(values)
        snippetOutput = ""
        snippetEgg = nil

        let targets: [ServerHost]
        if onGroup, let group = currentGroup {
            targets = book.hosts.filter { $0.groupID == group.id }
            snippetEgg = eggs.shadowClone(hostCount: targets.count)
        } else if let host = book.hosts.first(where: { $0.id == selectedHost }) {
            targets = [host]
        } else {
            targets = []
        }

        for host in targets {
            let transport = SystemSSHTransport(host: host, reach: book.reach(for: host))
            let text: String
            if let result = try? await transport.run(command, timeout: .seconds(120)) {
                text = result.succeeded ? result.stdout : result.stderr
            } else {
                text = strings("snip.noLink")
            }
            await transport.close()
            snippetOutput +=
                "── \(host.name) ──\n"
                + (text.isEmpty ? "\(strings("common.empty"))\n" : String(text.prefix(4_000)))
                + "\n"
        }
    }
}
