public import AppKit
public import Foundation
public import HostsKit
public import PhosphorCore
public import SSHKit
public import UserNotifications

/// Пульт по всем спейсам сразу, как в herdr: сессии и агенты каждого хоста
/// видны в рейле, даже когда смотришь в другой; превью экрана сессии без
/// подключения; сигнал, когда агенту понадобился ответ.
@MainActor
extension AppModel {
    /// Что известно о спейсе, на который сейчас не смотрят.
    public enum SpaceSnapshot: Sendable, Equatable {
        /// Канала к хосту нет: сеть упала, Мак спал, канал закрылся по
        /// таймауту. Подключение — по клику, из фона мы не логинимся.
        case offline
        case sessions([TmuxSession])
    }

    /// Где живёт сессия с агентом: на этом Маке или на хосте.
    public enum AgentPlace: Hashable, Sendable {
        /// nil — обычный шелл без tmux.
        case local(String?)
        case remote(ServerHost.ID, String)

        var host: ServerHost.ID? {
            if case .remote(let id, _) = self { return id }
            return nil
        }
    }

    /// Как часто досматривать работающего агента, пока окно в фоне. Реже, чем
    /// при открытом окне: ответ нужен человеку, который ушёл, а не следит.
    static let backgroundWatchSeconds = 10.0
    /// Сколько строк экрана показывает превью: хватает понять, о чём агент
    /// спрашивает, и не превращает подсказку во второй терминал.
    static let previewLineLimit = 14
    /// Длиннее строки обрезаются: превью узкое, а строка без переноса — это
    /// одна черта через весь экран.
    static let previewLineWidth = 160

    /// Сессии фоновых спейсов одним списком — для счётчика «ждут ответа».
    var backgroundSessions: [TmuxSession] {
        spaces.flatMap { id -> [TmuxSession] in
            guard id != selectedHost, case .sessions(let list) = spaceSnapshots[id] else { return [] }
            return list
        }
    }

    /// Работает ли сейчас хоть один агент где угодно. Только ради такого
    /// случая опрос и продолжается, когда окно в фоне.
    var anyAgentWorking: Bool {
        agentSessions.contains { $0.session.status == .working }
    }

    /// Все сессии с агентами — здесь и на всех спейсах — с их адресами.
    var agentSessions: [(place: AgentPlace, session: TmuxSession)] {
        var result: [(AgentPlace, TmuxSession)] = []
        if let plainShell, plainShell.agent != nil { result.append((.local(nil), plainShell)) }
        for session in localSessions where session.agent != nil {
            result.append((.local(session.name), session))
        }
        if let host = selectedHost {
            for session in liveSessions where session.agent != nil {
                result.append((.remote(host, session.name), session))
            }
        }
        for id in spaces where id != selectedHost {
            guard case .sessions(let list) = spaceSnapshots[id] else { continue }
            for session in list where session.agent != nil {
                result.append((.remote(id, session.name), session))
            }
        }
        return result
    }

    // MARK: - Фоновые спейсы

    /// Канал фонового опроса для спейса. Он делит ssh-сокет с подключением, и
    /// поэтому сам по себе ничего не открывает.
    func spaceTransport(for id: ServerHost.ID, keep: Bool = true) -> SystemSSHTransport? {
        if let existing = spaceTransports[id] { return existing }
        guard let host = book.hosts.first(where: { $0.id == id }) else { return nil }
        let transport = SystemSSHTransport(host: host, route: book.route(for: host))
        if keep { spaceTransports[id] = transport }
        return transport
    }

    /// Опрашивает сессии всех спейсов, кроме текущего, разом.
    ///
    /// Параллельно, потому что один хост за медленным прокси иначе задерживал
    /// бы весь рейл на свой таймаут.
    func loadSpaces() async {
        let targets = spaces.filter { $0 != selectedHost }.compactMap { id in
            spaceTransport(for: id).map { (id, $0) }
        }
        guard !targets.isEmpty else { return }
        let command = Shell.withPackagePaths + Self.pollCommand()
        let results = await withTaskGroup(of: (ServerHost.ID, String?).self) { group in
            for (id, transport) in targets {
                group.addTask {
                    let result = await transport.runIfConnected(command)
                    return (id, result?.succeeded == true ? result?.stdout : nil)
                }
            }
            var collected: [ServerHost.ID: String?] = [:]
            for await (id, output) in group { collected[id] = output }
            return collected
        }
        // Пока шёл опрос, человек мог переключиться в один из этих спейсов или
        // закрыть его: такие ответы уже никому не нужны.
        for (id, output) in results where spaces.contains(id) && id != selectedHost {
            spaceSnapshots[id] = output.map { .sessions(Self.parseSessions($0)) } ?? .offline
        }
    }

    // MARK: - Превью

    /// Последние строки экрана сессии, без подключения к ней. nil — показать
    /// нечего: канала нет или tmux не ответил.
    ///
    /// Текст только показывается: в нём может оказаться что угодно, вплоть до
    /// токена, напечатанного в шелле, — поэтому ни в лог, ни на диск.
    public func preview(_ place: AgentPlace) async -> [String]? {
        let output: String?
        switch place {
        case .local(nil):
            return nil
        case .local(let name?):
            guard let tmux = localTmuxPath else { return nil }
            output = await LocalTmux.run(Self.captureCommand(session: name, tmux: Shell.quote(tmux)))
        case .remote(let id, let name):
            let command = Self.captureCommand(session: name)
            if id == selectedHost, let session {
                // Не дошло — превью просто не будет; разбираться с причиной
                // будет само подключение, а не подсказка при наведении.
                output = try? await session.run(command).stdout
            } else {
                output = await spaceTransport(for: id)?.runIfConnected(command)?.stdout
            }
        }
        guard let output else { return nil }
        return Self.previewLines(output)
    }

    /// Снимок видимого экрана активной панели сессии, текстом без цветов.
    static func captureCommand(session: String, tmux: String = "tmux") -> String {
        "\(tmux) capture-pane -p -J -t \(Shell.quote(session + ":")) 2>/dev/null"
    }

    /// Готовит снимок экрана к показу. Чистая функция.
    ///
    /// Пустой низ экрана отрезается — иначе превью было бы из пустых строк под
    /// приглашением. Управляющие символы выкидываются: `capture-pane` без `-e`
    /// их не даёт, но текст пришёл с чужой машины, и верить ему на слово не
    /// стоит.
    static func previewLines(_ output: String) -> [String] {
        var lines = output.split(separator: "\n", omittingEmptySubsequences: false).map { line in
            let printable = line.unicodeScalars.filter { $0.value >= 0x20 && $0 != "\u{7F}" }
            let clean = String(String.UnicodeScalarView(printable))
                .replacingOccurrences(of: "\\s+$", with: "", options: .regularExpression)
            return clean.count > previewLineWidth ? String(clean.prefix(previewLineWidth)) + "…" : clean
        }
        while lines.last?.isEmpty == true { lines.removeLast() }
        return Array(lines.suffix(previewLineLimit))
    }

    // MARK: - «Ждёт тебя»

    /// Сверяет агентов с прошлым опросом: кто только что стал ждать ответа и
    /// стоит не перед глазами — о том уведомление. Число ждущих — на иконке
    /// в Dock, чтобы его было видно из любого приложения.
    func noticeWaitingAgents() {
        let waiting = agentSessions.filter { $0.session.status == .blocked }
        let now = Set(waiting.map(\.place))
        for (place, session) in waiting where !waitingAgents.contains(place) && !isInView(place) {
            guard let agent = session.agent else { continue }
            agentNotifier.post(
                title: "\(agent.title) · \(strings("term.status.blocked"))",
                body: placeTitle(place), place: place)
        }
        waitingAgents = now
        NSApp?.dockTile.badgeLabel = now.isEmpty ? nil : String(now.count)
    }

    /// Смотрит ли человек на эту сессию прямо сейчас.
    func isInView(_ place: AgentPlace) -> Bool {
        guard windowActive, screen == .terminal else { return false }
        switch place {
        case .local(let name):
            return localFocused && localSession == name
        case .remote(let id, let name):
            return !localFocused && selectedHost == id
                && ((terminalSession ?? "main") == name || extraSessions.contains(name))
        }
    }

    /// Подпись места для уведомления: «хост · сессия» или «этот Мак · сессия».
    func placeTitle(_ place: AgentPlace) -> String {
        switch place {
        case .local(let name):
            return "\(strings("term.thisMac")) · \(name ?? strings("term.plainShell"))"
        case .remote(let id, let name):
            let host = book.hosts.first { $0.id == id }?.name ?? ""
            return "\(host) · \(name)"
        }
    }

    /// Открывает сессию из уведомления или из рейла.
    public func jump(to place: AgentPlace) {
        switch place {
        case .local(let name):
            focusLocal(name)
        case .remote(let id, let name):
            if id == selectedHost {
                attachSession(name)
            } else {
                // Подключение вернёт сессию, записанную за спейсом.
                spaceSessions[id] = name
                switchSpace(id)
            }
        }
    }
}

/// Уведомления macOS о ждущих агентах и обратный путь: клик открывает сессию.
///
/// Делегат центра уведомлений обязан быть объектом NSObject и жить всё время
/// работы приложения — поэтому отдельный класс, а не модель.
@MainActor
final class AgentNotifier: NSObject, UNUserNotificationCenterDelegate {
    /// Куда вести клик. Слабая ссылка: уведомление не должно держать модель.
    weak var model: AppModel?
    private var asked = false
    private let placeKey = "place"

    /// Центр уведомлений есть только у собранного приложения: в `swift test`
    /// бандла нет, и обращение к нему роняет процесс.
    private var available: Bool { Bundle.main.bundleIdentifier != nil }

    func attach(_ model: AppModel) {
        guard self.model == nil, available else { return }
        self.model = model
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        // Ответ прямо из уведомления: Enter, Esc или строка текста (план §23).
        let strings = model.strings
        center.setNotificationCategories([
            UNNotificationCategory(
                identifier: Self.category,
                actions: [
                    UNNotificationAction(identifier: Self.accept, title: strings("term.reply.acceptAction")),
                    UNNotificationAction(identifier: Self.decline, title: strings("term.reply.decline")),
                    UNTextInputNotificationAction(
                        identifier: Self.text, title: strings("term.reply.textAction"),
                        textInputButtonTitle: strings("term.reply.send"),
                        textInputPlaceholder: strings("term.reply.placeholder")),
                ],
                intentIdentifiers: [])
        ])
    }

    nonisolated static let category = "agent.waiting"
    nonisolated static let accept = "agent.accept"
    nonisolated static let decline = "agent.decline"
    nonisolated static let text = "agent.text"

    func post(title: String, body: String, place: AppModel.AgentPlace) {
        guard available else { return }
        let center = UNUserNotificationCenter.current()
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.categoryIdentifier = Self.category
        content.userInfo = [placeKey: Self.encode(place)]
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        // Разрешение спрашиваем при первом поводе, а не на запуске: так человек
        // видит, зачем оно. Отказ — законный ответ: остаётся метка в Dock.
        let ask = !asked
        asked = true
        Task {
            if ask { _ = try? await center.requestAuthorization(options: [.alert, .sound]) }
            // Не доставилось (уведомления выключены) — метка в Dock всё равно
            // стоит; терять здесь нечего.
            try? await center.add(request)
        }
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse
    ) async {
        let raw = response.notification.request.content.userInfo["place"] as? String
        let reply: AgentReply? =
            switch response.actionIdentifier {
            case Self.accept: .accept
            case Self.decline: .decline
            case Self.text: (response as? UNTextInputNotificationResponse).map { .text($0.userText) }
            default: nil
            }
        await MainActor.run {
            guard let raw, let place = Self.decode(raw) else { return }
            guard let reply else {
                NSApp.activate()
                model?.jump(to: place)
                return
            }
            Task { [weak model] in
                // Не дошло — открываем сессию: ответить там можно всегда.
                guard let model, await !model.reply(reply, to: place) else { return }
                NSApp.activate()
                model.jump(to: place)
            }
        }
    }

    /// Окно впереди, но смотрят в другую сессию: баннер всё равно нужен.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter, willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }

    /// Адрес сессии строкой для `userInfo`: `local:<имя>` или `remote:<uuid>:<имя>`.
    /// Имя tmux-сессии двоеточий не содержит — санитайзер их не пропускает.
    nonisolated static func encode(_ place: AppModel.AgentPlace) -> String {
        switch place {
        case .local(let name): "local:\(name ?? "")"
        case .remote(let id, let name): "remote:\(id.uuidString):\(name)"
        }
    }

    nonisolated static func decode(_ raw: String) -> AppModel.AgentPlace? {
        let parts = raw.split(separator: ":", maxSplits: 2, omittingEmptySubsequences: false).map(String.init)
        switch parts.first {
        case "local" where parts.count == 2:
            return .local(parts[1].isEmpty ? nil : parts[1])
        case "remote" where parts.count == 3:
            return UUID(uuidString: parts[1]).map { .remote($0, parts[2]) }
        default:
            return nil
        }
    }
}
