import SwiftUI

/// Что можно запустить в новой панели: шелл или кодирующего агента.
///
/// Агенты запускаются своими CLI под подпиской человека — никаких ключей API
/// приложение не спрашивает и не хранит (план §23, «Нейронки в панелях»).
/// Список — данные: новая нейронка добавляется строкой.
public struct PaneLaunch: Sendable, Equatable, Identifiable {
    public let id: String
    public let title: String
    /// Что набрать в шелле. nil — сам шелл, набирать нечего.
    public let command: String?
    /// Как поставить, если агента на машине нет. Вставляется в шелл без
    /// Enter: ставить или нет, решает человек.
    public let install: String?

    public static let shell = PaneLaunch(id: "shell", title: "shell", command: nil, install: nil)

    public static let choices: [PaneLaunch] = [
        shell,
        PaneLaunch(
            id: "claude", title: "Claude Code", command: "claude",
            install: "npm install -g @anthropic-ai/claude-code"),
        PaneLaunch(id: "codex", title: "Codex", command: "codex", install: "npm install -g @openai/codex"),
        PaneLaunch(
            id: "gemini", title: "Gemini", command: "gemini", install: "npm install -g @google/gemini-cli"),
        PaneLaunch(
            id: "cursor", title: "Cursor", command: "cursor-agent",
            install: "curl https://cursor.com/install -fsS | bash"),
        PaneLaunch(
            id: "opencode", title: "opencode", command: "opencode", install: "npm install -g opencode-ai"),
    ]

    /// Одна команда, которая печатает имена найденных агентов, по одному в строке.
    ///
    /// Кроме обычного PATH смотрит туда, куда агенты ставятся сами: Homebrew,
    /// `~/.local/bin`, глобальные пакеты npm и bun — у неинтерактивного шелла
    /// этих путей часто нет.
    static func detectionCommand(_ choices: [PaneLaunch] = choices) -> String {
        let names = choices.compactMap(\.command).joined(separator: " ")
        return "PATH=\"$PATH:/opt/homebrew/bin:/usr/local/bin:$HOME/.local/bin:$HOME/.npm-global/bin:"
            + "$HOME/.bun/bin\"; for c in \(names); do command -v \"$c\" >/dev/null 2>&1 && echo \"$c\"; done"
    }

    /// Имена из вывода `detectionCommand`. Всё, чего нет в каталоге, отбрасывается:
    /// шумный профиль шелла на сервере не должен добавить в список чужое.
    static func installed(in output: String, choices: [PaneLaunch] = choices) -> Set<String> {
        let known = Set(choices.compactMap(\.command))
        return Set(
            output.split(whereSeparator: \.isNewline)
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { known.contains($0) })
    }
}

/// Строка выбора поверх новой панели: Tab и стрелки двигают, Enter запускает,
/// Esc оставляет шелл.
struct AgentPicker: View {
    @Environment(\.style) private var style
    let strings: Strings
    /// Какие команды есть на машине. nil — ещё не знаем: всё выглядит доступным.
    let installed: Set<String>?
    let onPick: (PaneLaunch) -> Void
    @State private var selection = 0
    @FocusState private var focused: Bool

    private var choices: [PaneLaunch] { PaneLaunch.choices }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(strings("term.launch")).font(style.font(12)).foregroundStyle(style.muted)
            FlowRow(spacing: 8) {
                ForEach(Array(choices.enumerated()), id: \.element.id) { index, choice in
                    chip(choice, selected: index == selection)
                        .onTapGesture {
                            selection = index
                            onPick(choice)
                        }
                }
            }
            Text(note).font(style.font(11)).foregroundStyle(style.muted)
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(style.background)
        .focusable()
        .focused($focused)
        .focusEffectDisabled()
        .onKeyPress(phases: .down) { press in handle(press) }
        // Окно — не системный лист, фокус само не забирает: без этого Tab ушёл
        // бы в терминал под ним.
        .onAppear { focused = true }
    }

    private var note: String {
        let choice = choices[selection]
        if let command = choice.command, isMissing(command), choice.install != nil {
            return strings("term.launchMissing")
        }
        return strings("term.launchHint")
    }

    private func isMissing(_ command: String) -> Bool {
        installed.map { !$0.contains(command) } ?? false
    }

    private func chip(_ choice: PaneLaunch, selected: Bool) -> some View {
        let missing = choice.command.map(isMissing) ?? false
        return Text(choice.id == PaneLaunch.shell.id ? strings("term.shell") : choice.title)
            .font(style.font(12.5))
            .foregroundStyle(selected ? style.background : (missing ? style.muted : style.bright))
            .padding(.horizontal, 10).padding(.vertical, 4)
            .background(selected ? style.accent : style.surface)
            .overlay(Rectangle().stroke(style.rule, lineWidth: selected ? 0 : 1))
            .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func handle(_ press: KeyPress) -> KeyPress.Result {
        switch press.key {
        case .tab:
            move(press.modifiers.contains(.shift) ? -1 : 1)
        case .rightArrow, .downArrow:
            move(1)
        case .leftArrow, .upArrow:
            move(-1)
        case .return:
            onPick(choices[selection])
        case .escape:
            onPick(.shell)
        default:
            return .ignored
        }
        return .handled
    }

    private func move(_ step: Int) {
        selection = (selection + step + choices.count) % choices.count
    }
}

