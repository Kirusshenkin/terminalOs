/// Кодирующий агент, живущий внутри сессии терминала.
///
/// Смысл ровно тот же, что у herdr: сессия — это не «какой-то процесс», а
/// конкретный агент, у которого есть имя и состояние. Знать имя нужно, чтобы
/// в рейле было написано «Claude Code ждёт», а не «что-то работает».
///
/// Это чистые данные: ни сети, ни интерфейса. Имена агентов — имена продуктов,
/// они не переводятся, поэтому их нет в таблице строк.
public struct CodingAgent: Sendable, Equatable, Identifiable {
    /// Короткий устойчивый идентификатор — он же ключ в раскладке на диске.
    public let id: String
    /// Как агент называется у своих авторов.
    public let title: String
    /// Имена, под которыми он виден в списке процессов (`comm` или argv[0]).
    public let commands: [String]
    /// Куски пути, выдающие агента, когда его запускает чужой интерпретатор:
    /// `node …/@anthropic-ai/claude-code/cli.js` — это claude, хотя процесс
    /// зовётся node, а файл — cli.js.
    public let markers: [String]

    public init(id: String, title: String, commands: [String], markers: [String] = []) {
        self.id = id
        self.title = title
        self.commands = commands
        self.markers = markers
    }
}

extension CodingAgent {
    /// Известные агенты. Список — данные, и дописывается строкой, а не кодом.
    ///
    /// Порядок важен только для чтения человеком: поиск идёт по точному имени
    /// команды, поэтому пересечений между записями быть не должно.
    public static let known: [CodingAgent] = [
        CodingAgent(
            id: "claude", title: "Claude Code", commands: ["claude"],
            markers: ["claude-code", "anthropic-ai/claude"]),
        CodingAgent(
            id: "codex", title: "Codex CLI", commands: ["codex"], markers: ["codex-cli"]),
        CodingAgent(
            id: "cursor", title: "Cursor Agent", commands: ["cursor-agent"],
            markers: ["cursor-agent"]),
        CodingAgent(id: "opencode", title: "opencode", commands: ["opencode"]),
        CodingAgent(
            id: "aider", title: "Aider", commands: ["aider"], markers: ["aider-chat", "aider_chat"]),
        CodingAgent(id: "goose", title: "Goose", commands: ["goose"]),
        CodingAgent(id: "crush", title: "Crush", commands: ["crush"]),
        CodingAgent(
            id: "amp", title: "Amp", commands: ["amp"], markers: ["sourcegraph/amp"]),
        CodingAgent(
            id: "gemini", title: "Gemini CLI", commands: ["gemini"], markers: ["gemini-cli"]),
        CodingAgent(id: "grok", title: "Grok CLI", commands: ["grok"], markers: ["grok-cli"]),
        CodingAgent(
            id: "copilot", title: "GitHub Copilot CLI", commands: ["copilot"],
            markers: ["copilot-cli"]),
        CodingAgent(id: "droid", title: "Factory Droid", commands: ["droid"]),
        CodingAgent(id: "qwen", title: "Qwen Code", commands: ["qwen"], markers: ["qwen-code"]),
        CodingAgent(id: "cline", title: "Cline", commands: ["cline"]),
        CodingAgent(id: "plandex", title: "Plandex", commands: ["plandex", "pdx"]),
        CodingAgent(
            id: "openhands", title: "OpenHands", commands: ["openhands"], markers: ["openhands"]),
        CodingAgent(
            id: "continue", title: "Continue CLI", commands: ["cn"], markers: ["continue-cli"]),
        CodingAgent(id: "auggie", title: "Augment CLI", commands: ["auggie"]),
        CodingAgent(id: "codebuff", title: "Codebuff", commands: ["codebuff"]),
        CodingAgent(id: "gptme", title: "gptme", commands: ["gptme"]),
        CodingAgent(id: "sgpt", title: "ShellGPT", commands: ["sgpt", "shell-gpt"]),
        CodingAgent(id: "amazonq", title: "Amazon Q", commands: ["q"], markers: ["amazon-q"]),
        CodingAgent(id: "kilocode", title: "Kilo Code", commands: ["kilocode"]),
    ]

    /// Чем агента запускают, когда он не самостоятельный бинарь. Такой процесс
    /// сам по себе ничего не говорит: решает то, что идёт за ним в argv.
    static let interpreters: Set<String> = [
        "node", "nodejs", "bun", "deno", "python", "python2", "python3", "ruby", "perl",
        "uv", "uvx", "npx", "pnpm", "pnpx", "yarn", "npm", "env", "sh", "bash", "zsh",
        "java", "dotnet", "poetry", "pipx", "tsx", "ts-node", "bunx",
    ]

    /// Расширения, которые не несут смысла в имени запускаемого файла.
    static let strippedSuffixes = [".js", ".mjs", ".cjs", ".ts", ".py", ".rb", ".sh", ".exe"]

    /// Поиск по точному имени команды: строится один раз, а не на каждый пакет
    /// строк с сервера.
    static let byCommand: [String: CodingAgent] = {
        var index: [String: CodingAgent] = [:]
        for agent in known {
            for command in agent.commands { index[command] = agent }
        }
        return index
    }()

    /// Узнаёт агента в командной строке процесса. Чистая функция: фикстура
    /// вместо сервера, поэтому её и можно проверить тестом.
    ///
    /// - Parameter commandLine: `comm` из tmux или целиком argv из `ps`.
    /// - Returns: агент либо nil, если это обычная команда.
    public static func detect(commandLine: String) -> CodingAgent? {
        let tokens = commandLine.split(whereSeparator: \.isWhitespace).map(String.init)
        for token in tokens {
            // Флаги пропускаем: `npx --yes claude` — это всё ещё claude.
            if token.hasPrefix("-") { continue }
            let name = executableName(token)
            if name.isEmpty { continue }
            // Интерпретатор ничего не решает: за ним идёт то, что он запускает.
            if interpreters.contains(name) { continue }
            // Первая настоящая команда и есть ответ. Дальше не идём: иначе
            // `git commit -m "спроси claude"` притворился бы агентом.
            return byCommand[name] ?? byMarker(in: commandLine)
        }
        return nil
    }

    /// Имя исполняемого файла без пути и без расширения: `/opt/bin/aider.py`
    /// и `aider` — один и тот же агент.
    static func executableName(_ token: String) -> String {
        var name = String(token.split(separator: "/").last ?? "")
        for suffix in strippedSuffixes where name.hasSuffix(suffix) {
            name.removeLast(suffix.count)
            break
        }
        return name.lowercased()
    }

    /// Запасной путь: агента выдаёт путь установки, когда процесс зовётся
    /// именем интерпретатора или безликим `cli.js`.
    static func byMarker(in commandLine: String) -> CodingAgent? {
        let line = commandLine.lowercased()
        for agent in known {
            for marker in agent.markers where line.contains(marker) { return agent }
        }
        return nil
    }
}
