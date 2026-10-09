import AppKit
import SwiftUI
import TerminalCore

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
    /// Как поставить, если агента на машине нет. Запускается по Enter в строке
    /// выбора: выбрать неустановленного агента и нажать Enter — это и есть
    /// согласие поставить.
    public let install: String?
    /// Вход, который агент сам при первом запуске не предлагает. nil — агент
    /// спросит вход сам, как только откроется.
    public let login: String?
    /// Чем запускать, если не голым `command`: другая модель в том же агенте.
    /// nil — просто `command`.
    public let start: String?

    public init(
        id: String, title: String, command: String?, install: String?, login: String? = nil,
        start: String? = nil
    ) {
        self.id = id
        self.title = title
        self.command = command
        self.install = install
        self.login = login
        self.start = start
    }

    public static let shell = PaneLaunch(id: "shell", title: "shell", command: nil, install: nil)

    public static let choices: [PaneLaunch] = [
        shell,
        // Свой установщик: Node не нужен, бинарь ложится в ~/.local/bin.
        PaneLaunch(
            id: "claude", title: "Claude Code", command: "claude",
            install: "curl -fsSL https://claude.ai/install.sh | bash"),
        PaneLaunch(id: "codex", title: "Codex", command: "codex", install: npmInstall("@openai/codex")),
        PaneLaunch(
            id: "gemini", title: "Gemini", command: "gemini", install: npmInstall("@google/gemini-cli")),
        PaneLaunch(
            id: "cursor", title: "Cursor", command: "cursor-agent",
            install: "curl https://cursor.com/install -fsS | bash", login: "cursor-agent login"),
        PaneLaunch(
            id: "opencode", title: "opencode", command: "opencode",
            install: "curl -fsSL https://opencode.ai/install | bash", login: "opencode auth login"),
        // GLM по подписке z.ai: своей программы у z.ai нет, модель живёт в
        // opencode. Ключ спрашивает и хранит сам opencode — у приложения его нет.
        PaneLaunch(
            id: "glm", title: "GLM (z.ai)", command: "opencode",
            install: "curl -fsSL https://opencode.ai/install | bash", start: glmStart),
    ]

    /// Провайдер подписки z.ai в каталоге моделей opencode (models.dev).
    static let glmProvider = "zai-coding-plan"

    /// Вход в z.ai — только если ключа ещё нет ни в окружении, ни в файле
    /// ключей opencode (`$XDG_DATA_HOME/opencode/auth.json`, по умолчанию
    /// `~/.local/share`). `-p` сразу спрашивает ключ, без списка провайдеров.
    static let glmStart =
        "{ [ -n \"$ZHIPU_API_KEY\" ] || grep -qs '\"\(glmProvider)\"' "
        + "\"${XDG_DATA_HOME:-$HOME/.local/share}/opencode/auth.json\" "
        + "|| opencode auth login -p \(glmProvider); } && opencode -m \(glmProvider)/glm-5.3"

    /// Куда агенты ставятся сами, мимо системного PATH: свои установщики
    /// (`~/.local/bin`, `~/.opencode/bin`), Homebrew, глобальные npm и bun.
    static let agentPaths =
        "/opt/homebrew/bin:/usr/local/bin:$HOME/.local/bin:$HOME/.opencode/bin:$HOME/.npm-global/bin:$HOME/.bun/bin"

    /// Глобальный пакет npm. Нет npm, но есть Homebrew — сперва ставится Node;
    /// нет и его — шелл скажет `brew: command not found`, и цепочка встанет.
    static func npmInstall(_ package: String) -> String {
        "{ command -v npm >/dev/null 2>&1 || brew install node; } && npm install -g \(package)"
    }

    /// Строка для панели, когда агента на машине нет: поставить, войти, если
    /// агент не спросит сам, и запустить. Каждый шаг — только после удачи
    /// предыдущего: упавшая установка остаётся на экране, а не уезжает под
    /// запущенным ничем. Чистая функция.
    ///
    /// - Parameter launch: строка запуска агента (с переездом в копию проекта).
    func installLine(then launch: String) -> String? {
        guard let install else { return nil }
        // Свежий бинарь лежит там, чего в PATH этого шелла могло не быть, а
        // `hash -r` забывает «не найдено», запомненное шеллом раньше.
        var parts = ["\(install)", "export PATH=\"$PATH:\(Self.agentPaths)\"", "hash -r"]
        if let login { parts.append(login) }
        return parts.joined(separator: " && ") + " && { " + launch + "; }"
    }

    /// Одна команда, которая печатает имена найденных агентов, по одному в строке.
    ///
    /// Кроме обычного PATH смотрит туда, куда агенты ставятся сами — у
    /// неинтерактивного шелла этих путей часто нет.
    static func detectionCommand(_ choices: [PaneLaunch] = choices) -> String {
        let names = choices.compactMap(\.command).joined(separator: " ")
        return "PATH=\"$PATH:\(agentPaths)\"; "
            + "for c in \(names); do command -v \"$c\" >/dev/null 2>&1 && echo \"$c\"; done"
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
        // Строка — не системный лист и фокус сама не забирает. Терминал под
        // ней, появившись, делает себя первым ответчиком (`TerminalSlot.show`),
        // и SwiftUI-фокус у NSView его не отнимает: Tab ушёл бы в шелл. Поэтому
        // на следующем витке, когда терминал уже встал, он отпускает клавиатуру
        // явно, и только потом фокус берёт строка.
        .onAppear {
            DispatchQueue.main.async {
                if NSApp.keyWindow?.firstResponder is TerminalSurface {
                    NSApp.keyWindow?.makeFirstResponder(nil)
                }
                focused = true
            }
        }
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
