public import AppKit
public import AuthKit
public import DockerKit
public import Foundation
public import HostsKit
public import MetricsKit
public import PhosphorCore
public import ProvisionKit
public import SSHKit
public import SessionKit
public import ThemeKit

/// Which screen the window is showing.
public enum Screen2: String, CaseIterable, Sendable {
    case hosts, terminal, docker, monitor, keys, theme
}

/// Кто живёт в углу.
public enum Pet: String, CaseIterable, Sendable {
    case cat, glider
    public var title: String {
        switch self {
        case .cat: "CAT"
        case .glider: "GLIDER"
        }
    }
}

/// Строка скроллбэка.
public struct TerminalLine: Sendable, Identifiable {
    public var id: Int
    public var text: String
    public var kind: Kind
    public enum Kind: Sendable { case prompt, output, warning, error }
}

/// Application state.
///
/// Lives on the main actor because every field feeds a view; everything that
/// touches the network happens in the actors under `SSHKit` and arrives here as
/// finished values.
@MainActor
@Observable
public final class AppModel {
    public var isUnlocked = false
    /// Что этот Мак реально умеет: обещаем только доступное.
    public private(set) var gateCapability = GateCapability(
        hasBiometry: false, hasWatch: false, hasPassword: true)
    public private(set) var unlockError: String?
    public private(set) var isUnlocking = false
    public var screen: Screen2 = .hosts
    public var language: Language = .system
    public var themeID = BuiltInThemes.phosphor.id
    public var eggs = EasterEggs()
    public var pet: Pet = .cat

    public var book = HostBook()
    public var selectedGroup: HostGroup.ID?
    public var query = ""
    public var selectedHost: ServerHost.ID?

    /// Живая сессия выбранного хоста, если он подключён.
    public private(set) var session: HostSession?
    public private(set) var sessionState = SessionState()
    private var observerToken: UUID?

    public var containers: [Container] = []
    public var selectedContainer: String?
    public var snapshots = RingBuffer<Snapshot>(capacity: 1_800)
    public var profile: HostProfile?
    public var provisionOffer: HostProfile?

    /// Что терминал просит подтвердить: запись в буфер, необычная ссылка.
    public var guardPrompt: GuardPrompt?

    /// Разрушающее действие, ожидающее подтверждения.
    public var pendingAction: PendingAction?
    /// Итог последнего действия — одной строкой под списком.
    public var lastOutcome: ActionOutcome?
    /// Логи выбранного контейнера. Кольцевой: логи умеют идти мегабайтами.
    public private(set) var logs = RingBuffer<String>(capacity: 5_000)
    private var logTask: Task<Void, Never>?

    /// Действие, которому нужно «да» от человека.
    public struct PendingAction: Identifiable, Sendable {
        public var id = UUID()
        public var action: ContainerAction
        public var container: Container
    }

    /// Terminal scrollback, bounded on purpose.
    public var scrollback = RingBuffer<TerminalLine>(capacity: 50_000)

    public var strings: Strings { Strings(language: language) }

    /// Theme for the current context: a host's group can override the default,
    /// which is how production ends up unmistakably red.
    public var style: Style {
        var id = themeID
        if let hostID = selectedHost,
            let host = book.hosts.first(where: { $0.id == hostID }),
            let groupTheme = book.group(for: host)?.themeID
        {
            id = groupTheme
        }
        return Style(theme: BuiltInThemes.theme(id: id))
    }

    public var visibleHosts: [ServerHost] {
        book.search(query, groupID: selectedGroup)
    }

    private let gate: any BiometricGate
    private let profiles: ProfileStore
    /// Отложенное сохранение: правки копятся и уходят одной записью.
    private var saveTask: Task<Void, Never>?

    public init(
        gate: any BiometricGate = SystemBiometricGate(),
        profiles: ProfileStore = ProfileStore(store: KeychainSecretStore())
    ) {
        self.gate = gate
        self.profiles = profiles
        self.gateCapability = gate.capability()
    }

    /// Проверяет человека и открывает профиль.
    ///
    /// Открытые соединения при блокировке не рвутся — закрывается интерфейс,
    /// а не сессии, иначе однажды это оборвёт долгий деплой.
    public func unlock() async {
        guard !isUnlocking else { return }
        isUnlocking = true
        unlockError = nil
        defer { isUnlocking = false }

        do {
            try await gate.authenticate(reason: "открыть профиль Phosphor")
            await loadProfile()
            isUnlocked = true
        } catch GateError.unavailable(let reason) {
            unlockError = "проверка недоступна: \(reason)"
        } catch GateError.lockedOut {
            unlockError = "биометрия заблокирована — войди паролем учётной записи"
        } catch {
            unlockError = "вход отменён"
        }
    }

    public func lock() {
        isUnlocked = false
    }

    private func loadProfile() async {
        do {
            book = try await profiles.load(HostBook.self, reason: "открыть профиль Phosphor")
        } catch ProfileStoreError.empty {
            // Первый запуск: показываем что-то живое, но ничего не сохраняем,
            // пока человек сам не заведёт хост.
            loadDemoData()
        } catch ProfileStoreError.keyLost {
            unlockError = "профиль на месте, но ключ утерян — восстанови из экспорта"
        } catch {
            unlockError = "профиль не читается: \(error.localizedDescription)"
        }
    }

    /// Запускает действие: разрушающие — только через подтверждение.
    public func request(_ action: ContainerAction, on container: Container) {
        if action.isDestructive {
            pendingAction = PendingAction(action: action, container: container)
        } else {
            Task { await perform(action, on: container) }
        }
    }

    public func confirm(_ pending: PendingAction) {
        pendingAction = nil
        Task { await perform(pending.action, on: pending.container) }
    }

    private func perform(_ action: ContainerAction, on container: Container) async {
        guard let session else {
            lastOutcome = ActionOutcome(
                action: action, containerName: container.name,
                succeeded: false, message: "нет подключения к хосту"
            )
            return
        }
        lastOutcome = await session.perform(action, on: container)
    }

    /// Переключает поток логов на другой контейнер.
    public func watchLogs(of container: Container) async {
        logTask?.cancel()
        logs.removeAll()
        guard let session else { return }
        logTask = await session.streamLogs(for: container) { [weak self] line in
            Task { @MainActor in self?.logs.append(line) }
        }
    }

    public func stopWatchingLogs() {
        logTask?.cancel()
        logTask = nil
    }

    /// Выполняет то, на что человек согласился в диалоге терминала.
    public func accept(_ prompt: GuardPrompt) {
        switch prompt.request {
        case .clipboardWrite(let text):
            let board = NSPasteboard.general
            board.clearContents()
            board.setString(text, forType: .string)
        case .unsafeLink(let uri):
            // Открываем только то, что система сочтёт корректным адресом, и
            // только по явному согласию.
            if let url = URL(string: uri) { NSWorkspace.shared.open(url) }
        }
        guardPrompt = nil
    }

    /// Подключается к хосту и начинает получать от него данные.
    ///
    /// Прошлая сессия закрывается: держать открытыми соединения к хостам, на
    /// которые никто не смотрит, — это чужой ресурс и чужие деньги.
    public func connect(to host: ServerHost) async {
        if let session, let observerToken {
            await session.stopObserving(observerToken)
            await session.stop()
        }
        selectedHost = host.id
        let fresh = HostSession(host: host, reach: book.reach(for: host))
        session = fresh
        sessionState = SessionState()
        observerToken = await fresh.observe { [weak self] state in
            Task { @MainActor in
                self?.sessionState = state
                self?.adopt(state)
            }
        }
        await fresh.start()
    }

    /// Переносит данные сессии в поля, из которых рисуются панели.
    private func adopt(_ state: SessionState) {
        if !state.containers.isEmpty { containers = state.containers }
        profile = state.profile
        if let snapshot = state.latest { snapshots.append(snapshot) }
        // Свежий сервер предлагаем настроить один раз, а не при каждом обновлении.
        if let hostProfile = state.profile, hostProfile.isFresh, provisionOffer == nil {
            provisionOffer = hostProfile
        }
    }

    public func disconnect() async {
        if let session, let observerToken { await session.stopObserving(observerToken) }
        await session?.stop()
        session = nil
        observerToken = nil
        sessionState = SessionState()
    }

    /// Приостанавливает опрос, когда окно ушло на второй план.
    public func setWindowActive(_ active: Bool) async {
        await session?.setActive(active)
    }

    /// Планирует запись профиля, схлопывая частые правки в одну.
    public func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { [profiles, book] in
            try? await Task.sleep(for: .milliseconds(700))
            guard !Task.isCancelled else { return }
            try? await profiles.save(book, reason: "сохранить профиль Phosphor")
        }
    }

    /// Sample content so the window is not empty before a real connection.
    public func loadDemoData() {
        let prod = HostGroup(name: "prod", themeID: "ruby", guardLevel: .always, mcpMode: .readOnly)
        let web = HostGroup(name: "web", themeID: "ice")
        let lab = HostGroup(name: "lab")
        book.groups = [prod, web, lab]
        book.hosts = [
            ServerHost(
                name: "app-1", address: "192.0.2.11", groupID: prod.id, tags: ["ssh", "app"], osName: "ubuntu"
            ),
            ServerHost(
                name: "worker-1", address: "192.0.2.12", groupID: prod.id, tags: ["ssh", "worker"],
                osName: "ubuntu"),
            ServerHost(
                name: "worker-2", address: "192.0.2.13", groupID: prod.id, tags: ["ssh", "worker"],
                osName: "ubuntu"),
            ServerHost(
                name: "lobby", address: "198.51.100.2", groupID: web.id, tags: ["ssh", "lobby"],
                osName: "debian"),
            ServerHost(
                name: "web.dev", address: "198.51.100.3", groupID: web.id, tags: ["ssh", "dev"],
                osName: "debian"),
            ServerHost(
                name: "sandbox", address: "203.0.113.5", groupID: lab.id, tags: ["ssh", "lab"],
                osName: "debian"),
            ServerHost(name: "203.0.113.9", address: "203.0.113.9", tags: ["ssh", "root"]),
        ]
        book.snippets = [
            Snippet(name: "логи контейнера", command: "docker logs --tail 200 {{container}}"),
            Snippet(name: "перезапуск стека", command: "cd {{path}} && docker compose restart"),
        ]
        containers = [
            Container(
                id: "3f9a2c7e11b0", name: "api-gateway", image: "api:2.14", state: .running,
                status: "Up 6 days", ports: "127.0.0.1:8080->8080", project: "prod", health: "healthy"),
            Container(
                id: "9b1e0d4a22c1", name: "postgres-main", image: "pg:16", state: .running,
                status: "Up 41 days", ports: "", project: "prod", health: "healthy"),
            Container(
                id: "77aa31ff90de", name: "worker-billing", image: "wrk:2.1", state: .running,
                status: "Up 2 hours (unhealthy)", ports: "", project: "prod", health: "unhealthy"),
            Container(
                id: "1c0de55ab332", name: "migrator", image: "api:2.14", state: .exited,
                status: "Exited (0) 6 days ago", ports: "", project: "prod", health: nil),
        ]
        selectedContainer = containers.first?.id
        for (index, line) in Self.demoScrollback.enumerated() {
            scrollback.append(TerminalLine(id: index, text: line.0, kind: line.1))
        }
    }

    private static let demoScrollback: [(String, TerminalLine.Kind)] = [
        ("root@app-1:~# docker compose ps", .prompt),
        ("NAME              IMAGE        STATUS", .output),
        ("api-gateway       api:2.14     Up 6 days", .output),
        ("postgres-main     pg:16        Up 41 days", .output),
        ("worker-billing    wrk:2.1      Up 2 hours (unhealthy)", .warning),
        ("migrator          api:2.14     Exited (0) 6 days ago", .warning),
        ("", .output),
        ("root@app-1:~# journalctl -u api --since '10 min ago' | tail -3", .prompt),
        ("11:41:08 api[912]  GET /v2/session 200 14ms", .output),
        ("11:41:09 api[912]  POST /v2/pay 201 62ms", .output),
        ("11:41:12 api[912]  WARN retry upstream billing", .warning),
    ]
}
