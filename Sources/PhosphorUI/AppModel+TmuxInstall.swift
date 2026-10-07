public import AppKit
public import Foundation
public import HostsKit
public import PhosphorCore
import SSHKit

/// Установка tmux одной кнопкой — там, где подсказка говорит, что его нет.
///
/// Скрытых действий нет: команда показывается до запуска, и ставится ровно
/// она. Если нужен пароль sudo, ввести его может только человек, поэтому
/// команда не запускается, а ложится в буфер обмена — вставить в терминал.
public struct TmuxInstall: Identifiable, Equatable, Sendable {
    public enum Target: Equatable, Sendable {
        case local
        case remote(ServerHost.ID)
    }

    /// Итог для рейла: что получилось и что делать дальше.
    public enum Note: Equatable, Sendable {
        case installed
        case copied
        case failed(String)
        /// Команда прошла, а tmux так и не нашёлся — например, ушёл не в PATH.
        case stillMissing
        case noHomebrew
    }

    /// Итог, привязанный к месту: под «этим Маком» или под спейсом сервера.
    public struct Outcome: Equatable, Sendable {
        public let target: Target
        public let note: Note
    }

    public let id = UUID()
    public let target: Target
    /// То, что видит человек и что будет запущено (или скопировано).
    public let command: String
    /// sudo спросит пароль: запускать самим нельзя, только отдать человеку.
    public let needsPassword: Bool
}

@MainActor
extension AppModel {
    /// Установка пакета — минуты, а не секунды: apt тянет списки, brew собирает.
    static let tmuxInstallTimeout: Duration = .seconds(600)

    /// Готовит установку и показывает команду на согласие.
    public func offerTmuxInstall(_ target: TmuxInstall.Target) {
        tmuxInstallNote = nil
        switch target {
        case .local:
            guard let brew = Self.localHomebrew() else {
                tmuxInstallNote = .init(target: .local, note: .noHomebrew)
                return
            }
            pendingTmuxInstall = TmuxInstall(
                target: .local, command: "\(brew) install tmux", needsPassword: false)
        case .remote:
            guard let profile, let shown = profile.installCommand(for: "tmux") else { return }
            // brew от root не работает и sudo ему не нужен; остальным пароль
            // нужен, только если sudo без пароля не пускает.
            let needsPassword = !profile.isRoot && !profile.canSudo && profile.packageManager != "brew"
            let command =
                needsPassword ? shown : profile.installCommand(for: "tmux", interactive: false) ?? shown
            pendingTmuxInstall = TmuxInstall(target: target, command: command, needsPassword: needsPassword)
        }
    }

    /// Человек согласился: ставим сами или отдаём команду ему.
    public func confirmTmuxInstall(_ install: TmuxInstall) async {
        pendingTmuxInstall = nil
        if install.needsPassword {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(install.command, forType: .string)
            tmuxInstallNote = .init(target: install.target, note: .copied)
            return
        }
        tmuxInstalling = install.target
        defer { tmuxInstalling = nil }
        let note =
            switch install.target {
            case .local: await installLocalTmux()
            case .remote: await installRemoteTmux(install.command)
            }
        tmuxInstallNote = .init(target: install.target, note: note)
    }

    private func installRemoteTmux(_ command: String) async -> TmuxInstall.Note {
        guard let session else { return .failed(strings("err.noSession")) }
        do {
            let result = try await session.run(
                Shell.withPackagePaths + command, timeout: Self.tmuxInstallTimeout)
            guard result.succeeded else { return .failed(Self.reason(result)) }
        } catch {
            return .failed(strings.describe(error))
        }
        // Успех — это найденный tmux, а не нулевой код выхода.
        await loadSessions()
        return hasTmux ? .installed : .stillMissing
    }

    private func installLocalTmux() async -> TmuxInstall.Note {
        guard let brew = Self.localHomebrew() else { return .noHomebrew }
        do {
            let result = try await Subprocess.run(
                executable: brew, arguments: ["install", "tmux"], timeout: Self.tmuxInstallTimeout)
            guard result.succeeded else { return .failed(Self.reason(result)) }
        } catch {
            return .failed(strings.describe(error))
        }
        localTmuxPath = LocalTmux.find()
        guard localTmuxPath != nil else { return .stillMissing }
        await loadLocalSessions()
        return .installed
    }

    /// Хвост вывода: причина отказа почти всегда в последних строках, а весь
    /// лог apt в рейл не помещается.
    nonisolated static func reason(_ result: CommandResult) -> String {
        let text = result.stderr.isEmpty ? result.stdout : result.stderr
        return text.split(whereSeparator: \.isNewline).suffix(3).joined(separator: "\n")
    }

    /// Homebrew на этом Маке, если он есть. Приложению из Finder `PATH` его не
    /// показывает, поэтому ищем по известным местам.
    nonisolated static func localHomebrew() -> String? {
        ["/opt/homebrew/bin/brew", "/usr/local/bin/brew"]
            .first { FileManager.default.isExecutableFile(atPath: $0) }
    }
}
