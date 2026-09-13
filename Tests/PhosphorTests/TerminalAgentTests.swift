import Foundation
import Testing

@testable import PhosphorUI

@Suite("Распознавание кодирующих агентов")
struct TerminalAgentTests {
    @Test("самостоятельный бинарь узнаётся по имени команды")
    func binary() {
        #expect(CodingAgent.detect(commandLine: "claude")?.id == "claude")
        #expect(CodingAgent.detect(commandLine: "claude --resume")?.id == "claude")
        #expect(CodingAgent.detect(commandLine: "/opt/homebrew/bin/codex exec")?.id == "codex")
        #expect(CodingAgent.detect(commandLine: "cursor-agent")?.id == "cursor")
        #expect(CodingAgent.detect(commandLine: "opencode run")?.id == "opencode")
    }

    @Test("агент под интерпретатором: решает не node, а то, что он запустил")
    func interpreter() {
        #expect(CodingAgent.detect(commandLine: "node /usr/local/bin/aider")?.id == "aider")
        #expect(CodingAgent.detect(commandLine: "npx --yes gemini")?.id == "gemini")
        #expect(CodingAgent.detect(commandLine: "python3 -m aider")?.id == "aider")
        #expect(CodingAgent.detect(commandLine: "/usr/bin/env goose session")?.id == "goose")
    }

    @Test("безликий cli.js выдаёт себя путём установки")
    func marker() {
        let line = "node /usr/lib/node_modules/@anthropic-ai/claude-code/cli.js --print"
        #expect(CodingAgent.detect(commandLine: line)?.id == "claude")
        #expect(CodingAgent.detect(commandLine: "node /opt/gemini-cli/dist/index.js")?.id == "gemini")
    }

    @Test("обычная работа за агента не выдаётся")
    func notAnAgent() {
        #expect(CodingAgent.detect(commandLine: "zsh") == nil)
        #expect(CodingAgent.detect(commandLine: "-bash") == nil)
        #expect(CodingAgent.detect(commandLine: "vim Package.swift") == nil)
        #expect(CodingAgent.detect(commandLine: "docker compose up") == nil)
        // Упоминание в аргументах — не запуск: иначе так «агентом» стал бы
        // любой коммит.
        #expect(CodingAgent.detect(commandLine: "git commit -m 'ask claude'") == nil)
        #expect(CodingAgent.detect(commandLine: "") == nil)
    }

    @Test("имя исполняемого файла — без пути и без расширения")
    func executableName() {
        #expect(CodingAgent.executableName("/opt/bin/aider.py") == "aider")
        #expect(CodingAgent.executableName("Claude") == "claude")
        #expect(CodingAgent.executableName("") == "")
    }

    @Test("в списке нет двух агентов с одной и той же командой")
    func catalogue() {
        var seen: Set<String> = []
        for agent in CodingAgent.known {
            for command in agent.commands {
                #expect(!seen.contains(command), "команда \(command) занята дважды")
                seen.insert(command)
            }
            #expect(!agent.id.isEmpty && !agent.title.isEmpty)
        }
        // Список должен оставаться списком, а не парой примеров.
        #expect(CodingAgent.known.count >= 20)
    }
}
