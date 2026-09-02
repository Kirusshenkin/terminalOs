public import AppKit
public import AuthKit
public import DockerKit
public import Foundation
public import HostsKit
public import KeysKit
public import MCPBridge
public import MetricsKit
public import PhosphorCore
public import ProvisionKit
public import SSHKit
public import SessionKit
public import ThemeKit

/// Which screen the window is showing.
public enum Section: String, CaseIterable, Sendable {
    case hosts, terminal, files, docker, monitor, provision, activity, theme
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
    public var screen: Section = .hosts
    public var language: Language = .system
    public var themeID = BuiltInThemes.phosphor.id
    public var eggs = EasterEggs()
    public var pet: Pet = .cat

    public var book = HostBook()
    public var selectedGroup: HostGroup.ID?
    public var query = ""
    public var selectedHost: ServerHost.ID?
    public var isAddingHost = false
    /// Хост, открытый на правку, и хост, ожидающий подтверждения удаления.
    public var editingHost: ServerHost?
    public var pendingHostRemoval: ServerHost?
    public var importReport: ImportReport?

    /// Живая сессия выбранного хоста, если он подключён.
    public internal(set) var session: HostSession?
    public internal(set) var sessionState = SessionState()
    /// Управляющий сокет текущей сессии: терминал едет по нему же.
    public internal(set) var sessionSocketPath: String?
    private var observerToken: UUID?

    public var selectedContainer: String?
    public var snapshots = RingBuffer<Snapshot>(capacity: 1_800)
    public var profile: HostProfile?
    public var provisionOffer: HostProfile?

    /// Что терминал просит подтвердить: запись в буфер, необычная ссылка.
    public var guardPrompt: GuardPrompt?

    /// Страница внутри каждого раздела.
    public var page: HostsPage = .hosts
    public var dockerPage: DockerPage = .containers
    public var monitorPage: MonitorPage = .overview
    public var activityPage: ActivityPage = .journal
    public var themePage: ThemePage = .palette

    /// Образы, тома и сети выбранного хоста.
    public internal(set) var images: [DockerImage] = []
    public internal(set) var volumes: [DockerVolume] = []
    public internal(set) var networks: [DockerNetwork] = []

    /// Пробросы портов и их состояние.
    public var forwards: [PortForward] = []
    public internal(set) var activeForwards: Set<UUID> = []
    public internal(set) var forwardError: String?

    /// Вывод последнего сниппета и отсылка, если он ушёл на группу.
    public internal(set) var snippetOutput = ""
    public internal(set) var snippetEgg: String?

    /// Известные хосты и журнал подключений.
    public internal(set) var knownHosts: [KnownHost] = []
    public internal(set) var knownHostsError: String?
    public internal(set) var connectionEvents: [ConnectionEvent] = []
    let connections = ConnectionLog()

    /// Файловые панели.
    public var localPath = NSHomeDirectory()
    public var remotePath = "/"
    public internal(set) var localFiles: [RemoteFile] = []
    public internal(set) var remoteFiles: [RemoteFile] = []
    public internal(set) var filesError: String?

    /// Журнал действий ИИ и режимы доступа по хостам.
    public internal(set) var auditEntries: [AuditEntry] = []
    public internal(set) var mcpModes: [ServerHost.ID: MCPMode] = [:]
    let policy = AccessPolicy()
    let audit = AuditLog()
    /// Локальный сокет для MCP-клиентов; живёт, пока открыто приложение.
    var bridge: SocketServer?
    public internal(set) var bridgeError: String?
    public var mcpConfirmation: ConfirmationRequest?

    /// Ключи на выбранном сервере.
    public internal(set) var serverKeys: [AuthorizedKey] = []
    public internal(set) var myFingerprint: String?
    public internal(set) var keysError: String?
    public var pendingKeyRemoval: AuthorizedKey?

    /// Настройка сервера.
    public internal(set) var provisionSteps: [StepProgress] = []
    public internal(set) var provisionLog = RingBuffer<String>(capacity: 4_000)
    public internal(set) var isProvisioning = false
    public internal(set) var plannedCommands: [(step: String, commands: [String])] = []
    public var showsPlannedCommands = false
    var runner: ProvisionRunner?

    /// Разрушающее действие, ожидающее подтверждения.
    public var pendingAction: PendingAction?
    /// Итог последнего действия — одной строкой под списком.
    public var lastOutcome: ActionOutcome?
    /// Логи выбранного контейнера. Кольцевой: логи умеют идти мегабайтами.
    public internal(set) var logs = RingBuffer<String>(capacity: 5_000)
    var logTask: Task<Void, Never>?

    /// Действие, которому нужно «да» от человека.
    public struct PendingAction: Identifiable, Sendable {
        public var id = UUID()
        public var action: ContainerAction
        public var container: Container
    }

    public var strings: Strings { Strings(language: language) }

    /// Строка для конфигурации MCP-клиента.
    public var bridgeCommand: String {
        let shim = Bundle.main.bundleURL
            .appendingPathComponent("Contents/MacOS/phosphor-mcp").path
        return #"{"mcpServers":{"phosphor":{"command":"\#(shim)"}}}"#
    }

    /// Куда смотрит терминал: на локальный шелл или на выбранный сервер.
    public var terminalDestination: TerminalHost.Destination {
        guard let id = selectedHost,
            let host = book.hosts.first(where: { $0.id == id }),
            let socket = sessionSocketPath
        else { return .local }
        return .remote(host: host, reach: book.reach(for: host), controlPath: socket)
    }

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

    private let appearance = AppearanceStore()
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

        let saved = appearance.load()
        themeID = saved.themeID
        language = Language(rawValue: saved.language) ?? .system
        pet = Pet(rawValue: saved.pet) ?? .cat
        eggs = EasterEggs(enabled: saved.eggsEnabled)
    }

    /// Сохраняет внешний вид. Вызывается из представлений при изменении.
    public func saveAppearance() {
        appearance.save(
            Appearance(
                themeID: themeID,
                language: language.rawValue,
                pet: pet.rawValue,
                eggsEnabled: eggs.enabled
            ))
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
            syncForwardsFromBook()
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
        let transport = SystemSSHTransport(host: host, reach: book.reach(for: host))
        sessionSocketPath = transport.socketPath
        let fresh = HostSession(host: host, transport: transport)
        session = fresh
        sessionState = SessionState()
        observerToken = await fresh.observe { [weak self] state in
            Task { @MainActor in
                self?.sessionState = state
                self?.adopt(state)
            }
        }
        await fresh.start()

        // Журнал пишет факт, а не содержимое: куда, когда и через что.
        switch await fresh.current.phase {
        case .ready:
            await record(.connected, host: host)
            await startAutoForwards()
        case .failed(let reason):
            await record(.failed, host: host, detail: reason)
        default:
            break
        }
    }

    /// Переносит данные сессии в поля, из которых рисуются панели.
    private func adopt(_ state: SessionState) {
        profile = state.profile
        if let snapshot = state.latest { snapshots.append(snapshot) }
        // Свежий сервер предлагаем настроить один раз, а не при каждом обновлении.
        if let hostProfile = state.profile, hostProfile.isFresh, provisionOffer == nil {
            provisionOffer = hostProfile
        }
    }

    public func disconnect() async {
        if let host = book.hosts.first(where: { $0.id == selectedHost }), session != nil {
            await record(.disconnected, host: host)
        }
        if let session, let observerToken { await session.stopObserving(observerToken) }
        await session?.stop()
        session = nil
        observerToken = nil
        sessionState = SessionState()
        sessionSocketPath = nil
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
    }

}
