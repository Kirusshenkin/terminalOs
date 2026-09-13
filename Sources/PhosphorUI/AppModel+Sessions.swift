public import Foundation
public import HostsKit
public import PhosphorCore
public import SSHKit

/// Постоянные tmux-сессии на сервере: список, подключение, создание, снятие.
///
/// tmux — это и есть «сервер, который всё время работает»: шелл живёт внутри
/// него на хосте, а приложение лишь подключается к живой сессии и отключается,
/// ничего не убивая. Закрыл ноутбук, потерял сеть — сессия и всё, что в ней
/// запущено (сборка, агент, лог), продолжают идти.
@MainActor
extension AppModel {
    /// Читает живые сессии выбранного хоста. Пустой список — не ошибка: значит
    /// сессий ещё нет либо tmux на сервере не установлен.
    public func loadSessions() async {
        guard let session else {
            liveSessions = []
            hasTmux = true
            return
        }
        let result = try? await session.run(Self.pollCommand())
        let output = result?.stdout ?? ""
        // Команда не дошла — это про связь, а не про tmux: прежний ответ не
        // опровергнут, и пугать отсутствием tmux не за что.
        if result != nil { hasTmux = !output.contains(Self.noTmuxMarker) }
        liveSessions = Self.parseSessions(output)
    }

    /// Один заход за всем сразу: время сервера (чтобы «свежесть» считать по его
    /// часам, а не по нашим), панели каждой сессии и передние процессы их
    /// терминалов целиком с аргументами.
    ///
    /// Аргументы нужны ради агентов: `claude` из npm виден в списке процессов
    /// как `node`, и по одному имени процесса его не отличить от сборки.
    /// Список передних процессов ограничен сверху — на занятом сервере их
    /// сотни, а нам интересны только те, что стоят в панелях tmux.
    ///
    /// Пустой список сессий — это ноль строк, а не ошибка, поэтому `|| true`
    /// стоит внутри группы: иначе отсутствие сессий читалось бы как отсутствие
    /// tmux.
    static func pollCommand(tmux: String = "tmux") -> String {
        "command -v \(tmux) >/dev/null 2>&1 && { echo \"NOW $(date +%s)\"; "
            + "echo \(panesMarker); "
            + "\(tmux) list-panes -a -F "
            + "'#{session_name}\t#{pane_active}\t#{pane_current_command}\t"
            + "#{session_windows}\t#{session_attached}\t#{session_activity}\t#{pane_tty}' 2>/dev/null "
            + "|| true; echo \(procsMarker); "
            + "ps -eo tty=,stat=,args= 2>/dev/null | awk '$2 ~ /\\+/' | head -\(foregroundLimit) "
            + "|| true; } || echo \(noTmuxMarker)"
    }

    /// Что печатает сервер, на котором tmux не нашёлся.
    static let noTmuxMarker = "NOTMUX"
    /// Заголовки разделов в ответе: сначала панели, потом передние процессы.
    static let panesMarker = "PANES"
    static let procsMarker = "PROCS"
    /// Потолок на список передних процессов: буфер без границы — это утечка
    /// с отложенным сроком, а панелей tmux всё равно единицы.
    static let foregroundLimit = 80

    /// Шеллы, при которых сессия считается покоящейся (idle).
    static let shellCommands: Set<String> = [
        "zsh", "-zsh", "bash", "-bash", "sh", "-sh", "fish", "-fish", "dash",
        "tmux", "login", "ksh", "csh", "tcsh",
    ]
    /// Насколько недавней должна быть активность, чтобы сессия считалась рабочей.
    static let workingWindowSeconds = 15

    /// Разбирает вывод опроса в объекты. Чистая функция — проверяется на
    /// фикстуре, без сервера.
    ///
    /// Ответ идёт разделами: `NOW`, затем `PANES` со строками панелей, затем
    /// `PROCS` со строками `ps`. Без заголовков всё читается как панели: так
    /// фикстура старого формата остаётся годной.
    public static func parseSessions(_ output: String) -> [TmuxSession] {
        var now = 0
        var paneLines: [String] = []
        var procLines: [String] = []
        var inProcs = false

        for rawLine in output.split(separator: "\n") {
            let line = String(rawLine)
            if line.hasPrefix("NOW ") {
                now = Int(line.dropFirst(4).trimmingCharacters(in: .whitespaces)) ?? 0
            } else if line == panesMarker {
                inProcs = false
            } else if line == procsMarker {
                inProcs = true
            } else if inProcs {
                procLines.append(line)
            } else {
                paneLines.append(line)
            }
        }
        return assemble(paneLines, foreground: foreground(procLines), now: now)
    }

    /// Собирает сессии из строк панелей.
    ///
    /// Строка: `session \t paneActive \t command \t windows \t attached \t
    /// activity \t tty`. Для каждой сессии статус решает активная панель, а имя
    /// агента — та, в которой он нашёлся: агент часто сидит не в активной.
    /// Порядок первого появления сохраняем.
    static func assemble(
        _ lines: [String], foreground: [String: [String]], now: Int
    ) -> [TmuxSession] {
        var order: [String] = []
        var byName: [String: TmuxSession] = [:]
        var activePicked: Set<String> = []

        for line in lines {
            let parts = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
            guard parts.count >= 6, !parts[0].isEmpty else { continue }
            let name = parts[0]
            let isActivePane = parts[1] == "1"
            let command = parts[2]
            let activity = Int(parts[5]) ?? 0
            let tty = parts.count > 6 ? parts[6] : ""

            if byName[name] == nil {
                order.append(name)
                byName[name] = TmuxSession(
                    name: name, windows: Int(parts[3]) ?? 1, attached: parts[4] == "1",
                    status: .idle)
            }
            // Статус берём с активной панели; если её не встретили — с первой.
            if isActivePane || !activePicked.contains(name) {
                byName[name]?.status = status(command: command, activity: activity, now: now)
                if isActivePane { activePicked.insert(name) }
            }
            // Агент — первый найденный в сессии: он и есть то, ради чего
            // на эту сессию смотрят.
            if byName[name]?.agent == nil {
                byName[name]?.agent = agent(command: command, tty: tty, foreground: foreground)
            }
        }
        return order.compactMap { byName[$0] }
    }

    /// Кто стоит в панели: сначала смотрим на полные командные строки с её
    /// терминала, и только если там ничего не узнали — на имя процесса от tmux.
    static func agent(
        command: String, tty: String, foreground: [String: [String]]
    ) -> CodingAgent? {
        for line in foreground[normalisedTTY(tty)] ?? [] {
            if let found = CodingAgent.detect(commandLine: line) { return found }
        }
        return CodingAgent.detect(commandLine: command)
    }

    /// Передние процессы по терминалам: `tty stat args…` из `ps`.
    ///
    /// Одному терминалу принадлежит несколько передних процессов (агент и всё,
    /// что он запустил), поэтому список, а не одна строка.
    ///
    /// Сами командные строки никуда не показываются и не пишутся: из них
    /// берётся только имя агента. В argv попадают пароли и токены — им не
    /// место ни в интерфейсе, ни в логе, ни в аудите.
    static func foreground(_ lines: [String]) -> [String: [String]] {
        var byTTY: [String: [String]] = [:]
        for line in lines {
            let parts = line.split(whereSeparator: \.isWhitespace).map(String.init)
            // tty, stat и хоть что-то от команды: без них строка бесполезна.
            guard parts.count >= 3 else { continue }
            let tty = normalisedTTY(parts[0])
            guard tty != "?", !tty.isEmpty else { continue }
            byTTY[tty, default: []].append(parts.dropFirst(2).joined(separator: " "))
        }
        return byTTY
    }

    /// Одно написание терминала для обеих сторон: tmux печатает `/dev/pts/3`,
    /// `ps` — `pts/3` на Linux и `ttys003` на macOS.
    static func normalisedTTY(_ raw: String) -> String {
        raw.hasPrefix("/dev/") ? String(raw.dropFirst(5)) : raw
    }

    /// Эвристика статуса: шелл — покой; чужой процесс с недавней активностью —
    /// работа; он же, но давно молчащий, — вероятно, ждёт ввода.
    static func status(command: String, activity: Int, now: Int) -> AppModel.SessionStatus {
        if shellCommands.contains(command) { return .idle }
        if now > 0, activity > 0, now - activity > workingWindowSeconds { return .blocked }
        return .working
    }

    // MARK: - Этот Мак рядом с серверами

    /// Читает живые сессии локального tmux. Его нет — список пуст, и рейл
    /// говорит об этом словами, а не пустотой.
    public func loadLocalSessions() async {
        guard let tmux = localTmuxPath else {
            localSessions = []
            return
        }
        localSessions = Self.parseSessions(
            await LocalTmux.run(Self.pollCommand(tmux: Shell.quote(tmux))))
    }

    /// Переводит терминал на этот Мак — в названную сессию или, если tmux
    /// здесь нет, в обычный одноразовый шелл.
    public func focusLocal(_ name: String?) {
        localFocused = true
        localSession = name
        screen = .terminal
        saveLayout()
    }

    /// Заводит локальную сессию с введённым именем и сразу открывает её.
    /// Сама сессия появится в tmux при подключении: `new-session -A` — это
    /// «подключиться или создать», второго способа тут не нужно.
    public func createLocalSession() {
        let name = SSHInvocation.tmuxSessionName(newSessionName) ?? "main"
        newSessionName = ""
        focusLocal(name)
        if !localSessions.contains(where: { $0.name == name }) {
            localSessions.append(TmuxSession(name: name, windows: 1, attached: true))
        }
    }

    /// Снимает локальную сессию вместе со всем, что в ней запущено.
    public func killLocalSession(_ name: String) async {
        guard let tmux = localTmuxPath else { return }
        // Поверхность гасим первой: за ней стоит tmux-клиент, которому иначе
        // осталось бы разговаривать с мёртвой сессией.
        if let safe = SSHInvocation.tmuxSessionName(name) {
            surfaces.discard(.localSession(name: safe, tmux: tmux))
        }
        _ = await LocalTmux.run(
            "\(Shell.quote(tmux)) kill-session -t \(Shell.quote(name)) 2>/dev/null || true")
        if localSession == name { localSession = nil }
        await loadLocalSessions()
        saveLayout()
    }

    // MARK: - Слежение за сессиями

    /// Начинает спрашивать сервер о сессиях, пока на окно смотрят.
    ///
    /// Иначе статус обновлялся бы только при смене хоста или сессии, а агент,
    /// упёршийся в вопрос, оставался бы «работающим», пока человек сам не
    /// заглянет в раздел. Слежение одно на приложение: второй вызов ничего не
    /// заводит.
    public func startSessionWatch() {
        guard sessionWatch == nil, windowActive, isUnlocked else { return }
        sessionWatch = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                // Спрашивать бывает некого: ни хоста, ни tmux на этом Маке.
                // Тогда цикл просто ждёт — заводить и гасить его на каждое
                // подключение значило бы держать две правды о том, идёт ли опрос.
                if self.session != nil { await self.loadSessions() }
                if self.localTmuxPath != nil { await self.loadLocalSessions() }
                await AppModel.pause(seconds: self.watchInterval)
            }
        }
    }

    /// Останавливает слежение: окно ушло в фон или соединения больше нет.
    public func stopSessionWatch() {
        sessionWatch?.cancel()
        sessionWatch = nil
    }

    /// Как часто спрашивать. Тот же интервал, что у метрик, но не чаще двух
    /// секунд: это ssh-команда, а не локальное чтение.
    var watchInterval: Double { max(2, pollSeconds) }

    /// Пауза между опросами.
    ///
    /// Это не «поспать и считать, что готово»: готовность здесь — ответ
    /// сервера, и его мы ждём по факту, внутри `loadSessions`. Таймер задаёт
    /// только промежуток между вопросами.
    static func pause(seconds: Double) async {
        try? await Task.sleep(for: .seconds(seconds))
    }

    // MARK: - Раскладка, которая переживает перезапуск

    /// Поднимает раскладку прошлого запуска: те же спейсы, те же сессии, тот же
    /// сплит. Хосты, которых больше нет в списке, отсеиваются — иначе в рейле
    /// висел бы спейс, ведущий в никуда.
    func restoreLayout() {
        let saved = layoutStore.load().keeping(hosts: Set(book.hosts.map(\.id)))
        spaces = saved.spaces
        var restoredSessions: [ServerHost.ID: String] = [:]
        for (rawID, name) in saved.spaceSessions {
            guard let id = UUID(uuidString: rawID) else { continue }
            restoredSessions[id] = name
        }
        spaceSessions = restoredSessions
        splitVertical = saved.splitVertical
        // Раскладка прошлой версии знала только про одну вторую панель — она
        // и читается как список из неё одной.
        extraSessions = saved.panes ?? saved.secondSession.map { [$0] } ?? []
        terminalSession = saved.session
        pendingFocus = saved.focused
        localSession = saved.localSession
        localFocused = saved.localFocused ?? false
    }

    /// Пишет раскладку на диск. Вызывается из действий, меняющих вид раздела:
    /// файл крошечный, а терять открытые спейсы обиднее, чем лишний раз его
    /// переписать.
    func saveLayout() {
        var sessions: [String: String] = [:]
        for (id, name) in spaceSessions { sessions[id.uuidString] = name }
        layoutStore.save(
            TerminalLayout(
                spaces: spaces,
                spaceSessions: sessions,
                focused: selectedHost ?? pendingFocus,
                session: terminalSession,
                secondSession: extraSessions.first,
                splitVertical: splitVertical,
                panes: extraSessions,
                localSession: localSession,
                localFocused: localFocused
            ))
    }

    /// Возвращается в спейс, на который смотрели перед закрытием приложения.
    ///
    /// Вызывается, когда человек открыл «Терминал»: соединение поднимается
    /// тогда, когда на него будут смотреть, а не на разблокировке окна.
    public func resumeLayout() async {
        guard session == nil, !localFocused, let id = pendingFocus,
            let host = book.hosts.first(where: { $0.id == id })
        else { return }
        pendingFocus = nil
        await connect(to: host)
    }

    /// Переводит терминал в выбранную сессию. Прежняя панель не гаснет: её
    /// поверхность остаётся живой, и возврат к ней отдаёт ленту такой, какой
    /// её оставили.
    public func attachSession(_ name: String) {
        guard terminalSession != name || localFocused else { return }
        localFocused = false
        terminalSession = name
        if let host = selectedHost { spaceSessions[host] = name }
        screen = .terminal
        saveLayout()
    }

    /// Добавляет ещё одну живую панель. Каждая садится в свою сессию на том же
    /// хосте (не в ту же, что соседняя, — иначе это одна и та же лента).
    public func splitTerminal() {
        guard extraSessions.count + 1 < Self.paneLimit else { return }
        var taken = Set(extraSessions)
        taken.insert(terminalSession ?? "main")
        extraSessions.append(Self.nextPaneName(taken: taken))
        screen = .terminal
        saveLayout()
    }

    /// Имя для новой панели: первое свободное из `side`, `side2`, `side3`…
    /// Чистая функция — занятые имена приходят снаружи.
    static func nextPaneName(taken: Set<String>) -> String {
        if !taken.contains("side") { return "side" }
        for index in 2...Self.paneLimit + 8 where !taken.contains("side\(index)") {
            return "side\(index)"
        }
        // Столько имён занять нельзя при потолке в несколько панелей, но
        // вернуть что-то осмысленное нужно и здесь.
        return "side\(UUID().uuidString.prefix(4))"
    }

    /// Убирает последнюю панель. tmux-сессия за ней остаётся жить на сервере —
    /// гаснет только наш `ssh`, смотреть в который стало некому.
    public func closeSplit() {
        guard let last = extraSessions.last else { return }
        closePane(last)
    }

    /// Убирает названную панель.
    public func closePane(_ name: String) {
        guard let index = extraSessions.firstIndex(of: name) else { return }
        if let destination = destination(session: name) { surfaces.discard(destination) }
        extraSessions.remove(at: index)
        saveLayout()
    }

    /// Меняет ориентацию сплита: рядом ↔ одна над другой.
    public func flipSplit() {
        splitVertical.toggle()
        saveLayout()
    }

    /// Переключает фокус на другой спейс (хост). tmux на прежнем хосте
    /// продолжает работать — мы просто отводим от него взгляд.
    public func switchSpace(_ id: ServerHost.ID) {
        guard id != selectedHost || localFocused,
            let host = book.hosts.first(where: { $0.id == id })
        else { return }
        localFocused = false
        screen = .terminal
        guard id != selectedHost else {
            saveLayout()
            return
        }
        Task { await connect(to: host) }
    }

    /// Убирает спейс из рейла. Если это текущий — отключаемся от него и
    /// переводим фокус на соседний. Сессии на сервере при этом не трогаются.
    public func closeSpace(_ id: ServerHost.ID) {
        spaces.removeAll { $0 == id }
        spaceSessions[id] = nil
        saveLayout()
        guard id == selectedHost else { return }
        if let next = spaces.first, let host = book.hosts.first(where: { $0.id == next }) {
            Task { await connect(to: host) }
        } else {
            Task { await disconnect() }
        }
    }

    /// Заводит новую сессию с введённым именем и сразу подключается.
    public func createSession() {
        let name = SSHInvocation.tmuxSessionName(newSessionName) ?? "main"
        newSessionName = ""
        localFocused = false
        terminalSession = name
        if let host = selectedHost { spaceSessions[host] = name }
        screen = .terminal
        saveLayout()
        // Список обновится по факту подключения; но покажем её сразу, чтобы рейл
        // не выглядел пустым, пока идёт attach.
        if !liveSessions.contains(where: { $0.name == name }) {
            liveSessions.append(TmuxSession(name: name, windows: 1, attached: true))
        }
    }

    /// Снимает сессию на сервере целиком — вместе со всем, что в ней запущено.
    /// Поэтому это делают явной кнопкой, а не мимоходом.
    public func killSession(_ name: String) async {
        guard let session else { return }
        // Поверхность гасим до убийства сессии: за ней стоит ssh, который иначе
        // остался бы висеть с мёртвым tmux на той стороне.
        if let destination = destination(session: name) { surfaces.discard(destination) }
        _ = try? await session.run("tmux kill-session -t \(Shell.quote(name)) 2>/dev/null || true")
        if terminalSession == name { terminalSession = nil }
        extraSessions.removeAll { $0 == name }
        saveLayout()
        await loadSessions()
    }
}
