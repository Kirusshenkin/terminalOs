public import Foundation
public import HostsKit
public import PhosphorCore

/// Решение о вызове.
public enum Decision: Sendable, Equatable {
    /// Можно выполнять.
    case allow
    /// Нужно спросить человека, показав ему `command`.
    case confirm(String)
    /// Нельзя, с причиной для того, кто спрашивал.
    case deny(String)
}

/// Кто и что может делать с хостом через MCP.
///
/// Терминал в роли MCP-сервера означает, что у модели появляется shell на
/// боевых серверах. Поэтому здесь всё устроено запретительно: новый хост
/// выключен, чтение отделено от записи, а список запрещённых команд действует
/// **поверх любого режима**, включая полный.
public actor AccessPolicy {
    /// Как долго живёт одно разрешение, прежде чем спросить снова.
    ///
    /// Разрешение «навсегда» превращает подтверждение в формальность: один раз
    /// нажал — и дальше всё молча.
    public var grantLifetime: Duration = .seconds(900)
    /// Сколько пишущих вызовов допускается за окно.
    public var writeLimit = 20
    public var writeWindow: Duration = .seconds(60)

    private var modes: [ServerHost.ID: MCPMode] = [:]
    private var grants: [ServerHost.ID: ContinuousClock.Instant] = [:]
    private var writeTimes: [ContinuousClock.Instant] = []

    public init() {}

    /// Режим хоста. Не задан — значит выключено: новый сервер не должен
    /// становиться доступным оттого, что о нём забыли.
    public func mode(for host: ServerHost.ID) -> MCPMode {
        modes[host] ?? .disabled
    }

    public func setMode(_ mode: MCPMode, for host: ServerHost.ID) {
        modes[host] = mode
        if mode == .disabled { grants[host] = nil }
    }

    /// Запоминает согласие человека на ближайшее время.
    public func grant(for host: ServerHost.ID, now: ContinuousClock.Instant = .now) {
        grants[host] = now
    }

    public func revoke(for host: ServerHost.ID) {
        grants[host] = nil
    }

    /// Решает, что делать с вызовом.
    public func decide(
        tool: Tool,
        host: ServerHost.ID,
        command: String?,
        now: ContinuousClock.Instant = .now
    ) -> Decision {
        // 1. Запрещённые команды — раньше всего остального. Ни один режим,
        //    включая полный, их не открывает.
        if let command, let matched = DenyList.match(command) {
            return .deny("команда запрещена: \(matched)")
        }

        let mode = mode(for: host)
        switch mode {
        case .disabled:
            return .deny("для этого хоста MCP выключен")
        case .readOnly where tool.kind == .write:
            return .deny("хост доступен только для чтения")
        case .readOnly, .confirm, .full:
            break
        }

        guard tool.kind == .write else { return .allow }

        // 2. Ограничение частоты — до подтверждения: шквал запросов не должен
        //    превращаться в шквал диалогов.
        writeTimes.removeAll { now - $0 > writeWindow }
        guard writeTimes.count < writeLimit else {
            return .deny("слишком много пишущих вызовов подряд")
        }

        if mode == .full { return .allow }

        // 3. Свежее согласие действует ограниченное время.
        if let granted = grants[host], now - granted < grantLifetime { return .allow }
        return .confirm(command ?? tool.summary)
    }

    /// Отмечает состоявшийся пишущий вызов для счётчика частоты.
    public func recordWrite(now: ContinuousClock.Instant = .now) {
        writeTimes.append(now)
    }
}

/// Команды, которые не выполняются никогда.
///
/// Список короткий и грубый нарочно: он не пытается быть песочницей, он ловит
/// то, после чего сервера не остаётся.
public enum DenyList {
    private static let patterns: [(name: String, test: @Sendable (String) -> Bool)] = [
        ("rm -rf /", { $0.contains("rm ") && $0.contains(" -rf") && rootTarget($0) }),
        ("mkfs", { $0.contains("mkfs") }),
        ("dd на устройство", { $0.contains("dd ") && $0.contains("of=/dev/") }),
        (
            "перезагрузка",
            {
                $0.hasPrefix("reboot") || $0.contains("shutdown ") || $0.contains("halt ")
                    || $0.contains("init 0")
            }
        ),
        ("форк-бомба", { $0.replacingOccurrences(of: " ", with: "").contains(":(){:|:&};:") }),
        ("затирание диска", { $0.contains("> /dev/sd") || $0.contains("of=/dev/disk") }),
        ("chmod на корень", { $0.contains("chmod") && rootTarget($0) }),
        ("chown на корень", { $0.contains("chown") && rootTarget($0) }),
    ]

    /// Цель команды — корень файловой системы, а не что-то под ним.
    private static func rootTarget(_ command: String) -> Bool {
        let words = command.split(separator: " ").map(String.init)
        return words.contains { word in
            let cleaned = word.trimmingCharacters(in: CharacterSet(charactersIn: "'\""))
            return cleaned == "/" || cleaned == "/*" || cleaned.hasPrefix("/ ")
        }
    }

    /// Имя сработавшего правила, если команда запрещена.
    public static func match(_ command: String) -> String? {
        let normalised = command.lowercased()
        for pattern in patterns where pattern.test(normalised) { return pattern.name }
        return nil
    }
}
