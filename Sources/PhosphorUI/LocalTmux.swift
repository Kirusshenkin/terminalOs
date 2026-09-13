public import Foundation

import SSHKit

/// tmux на этом Маке.
///
/// У herdr локальные рабочие пространства стоят в одном списке с серверными, и
/// живут они по тем же правилам: закрыл приложение — сессия продолжает идти.
/// Единственный способ дать это локально — тот же tmux, что и на сервере,
/// только запущенный здесь.
///
/// Наличие tmux проверяется фактом — файл есть и он исполняемый, — а не
/// предположением: в бандле приложения `PATH` куцый, и `/opt/homebrew/bin`
/// в него не входит.
public enum LocalTmux {
    /// Где tmux оказывается на Маке, если о нём не знает `PATH` приложения.
    static let candidates = [
        "/opt/homebrew/bin/tmux",  // Apple silicon, Homebrew
        "/usr/local/bin/tmux",  // Intel, Homebrew
        "/opt/local/bin/tmux",  // MacPorts
        "/usr/bin/tmux",
    ]

    /// Путь к tmux или nil, если его тут нет.
    public static func find() -> String? {
        let manager = FileManager.default
        let fromPath = (ProcessInfo.processInfo.environment["PATH"] ?? "")
            .split(separator: ":")
            .map { "\($0)/tmux" }
        for path in candidates + fromPath where manager.isExecutableFile(atPath: path) {
            return path
        }
        return nil
    }

    /// Выполняет команду локальным шеллом и отдаёт то, что она напечатала.
    ///
    /// Пустая строка — это и «команда ничего не нашла», и «команда не
    /// запустилась»: разница здесь не важна, потому что смысл один — сессий
    /// показать нечего.
    static func run(_ command: String) async -> String {
        let result = try? await Subprocess.run(
            executable: "/bin/sh", arguments: ["-c", command], timeout: .seconds(5))
        return result?.stdout ?? ""
    }

    /// Окружение для локального шелла внутри терминала.
    ///
    /// Берём окружение приложения и поправляем то, без чего эмулятор и tmux
    /// ведут себя неверно: тип терминала и локаль. Всё остальное подтянет
    /// логин-шелл, который tmux запустит внутри себя.
    static func environment() -> [String] {
        var values = ProcessInfo.processInfo.environment
        values["TERM"] = "xterm-256color"
        if values["LANG"] == nil { values["LANG"] = "en_US.UTF-8" }
        // Приложение запущено из бандла — этим переменным там делать нечего:
        // внутри они означали бы не то, что означают в шелле.
        values.removeValue(forKey: "XPC_SERVICE_NAME")
        values.removeValue(forKey: "XPC_FLAGS")
        return values.map { "\($0.key)=\($0.value)" }
    }
}
