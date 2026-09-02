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
    /// Настройки шрифта и стекла поверх выбранной темы.
    public var fontSize: Double = 13
    public var ligatures = true
    public var lineHeight: Double = 1.4
    /// Питомец в углу, интервал опроса и глубина буфера логов.
    /// Движение интерфейса — выбор человека, а не наш.
    public var motion = MotionAmount.full
    public var connectMotion = ConnectMotion.sweep
    public var logMotion = LogMotion.rise
    public var petVisible = true
    public var pollSeconds: Double = 4
    public var logLines = 5_000
    public var scanlines: Double?
    public var glow: Double?
    public var vignette: Double?
    /// Импортированные схемы живут рядом со встроенными.
    public internal(set) var importedThemes: [Theme] = []
    public internal(set) var themeImportNote: String?

    /// Все доступные темы: встроенные плюс импортированные.
    public var allThemes: [Theme] { BuiltInThemes.all + importedThemes }

    func theme(id: String) -> Theme {
        allThemes.first { $0.id == id } ?? BuiltInThemes.phosphor
    }
    public var eggs = EasterEggs()
    public var pet: Pet = .cat

    public var book = HostBook()
    public var selectedGroup: HostGroup.ID?
    public var query = ""
    public var selectedHost: ServerHost.ID?
    public var isAddingHost = false
    public var isAddingGroup = false
    public var editingGroup: HostGroup?
    public var groupNameDraft = ""
    /// Хост, открытый на правку, и хост, ожидающий подтверждения удаления.
    public var editingHost: ServerHost?
    public var pendingHostRemoval: ServerHost?
    /// Хост, для которого открыто своё контекстное меню, и точка, где кликнули.
    public var menuHost: ServerHost?
    public var menuPoint: CGPoint = .zero

    /// Пункты меню карточки. Правка и удаление живут здесь: сама карточка —
    /// это кнопка «подключиться», и путать одно с другим не стоит.
    public func cardMenuItems(for host: ServerHost) -> [MenuItem] {
        [
            MenuItem(strings("menu.connect")) { [self] in
                screen = .terminal
                Task { await connect(to: host) }
            },
            MenuItem(strings("menu.files")) { [self] in
                screen = .files
                Task { await connect(to: host) }
            },
            .separator,
            MenuItem(strings("menu.edit")) { [self] in editingHost = host },
            MenuItem(strings("menu.duplicate")) { [self] in duplicate(host) },
            .separator,
            MenuItem(strings("common.delete"), kind: .destructive) { [self] in pendingHostRemoval = host },
        ]
    }
    public var importReport: ImportReport?

    /// Живая сессия выбранного хоста, если он подключён.
    public internal(set) var session: HostSession?
    public internal(set) var sessionState = SessionState()
    /// Управляющий сокет текущей сессии: терминал едет по нему же.
    public internal(set) var sessionSocketPath: String?
    /// Переменные окружения выбранного контейнера: читаются по требованию,
    /// потому что `docker inspect` — отдельный вызов, а не часть опроса.
    public internal(set) var containerEnvironment: [(name: String, value: String)] = []
    public internal(set) var containerEnvironmentNote: String?
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
    /// Итог последнего действия над ресурсами — показываем рядом с таблицей.
    public internal(set) var resourcesMessage: String?
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
    /// Ключи на этой машине (~/.ssh) — их публичная половина.
    public internal(set) var localKeys: [LocalKey] = []
    /// Хост, к которому только что подключились «на лету» и который ещё не
    /// сохранён. Повод предложить запомнить — но не сохранять втихую.
    public var rememberOffer: ServerHost?

    /// Экспорт/импорт профиля: что делаем и итог для человека.
    public var profilePrompt: ProfilePrompt?
    public internal(set) var profileNote: String?
    /// Окно повторного Touch ID в секундах — то же, что задаётся из настроек.
    public var biometricReuseSeconds: Double = 10

    public enum ProfilePrompt: Identifiable, Sendable {
        case export
        case importFrom(URL)
        public var id: String {
            switch self {
            case .export: "export"
            case .importFrom(let url): "import:\(url.path)"
            }
        }
    }

    // MARK: - Постоянные сессии (herdr-стиль)

    /// Держать шелл внутри tmux на сервере, чтобы он пережил закрытие
    /// приложения и обрыв сети. По духу herdr — включено по умолчанию.
    public var persistentSessions = true
    /// Имя tmux-сессии, к которой сейчас подключён терминал. nil — «main».
    public var terminalSession: String?
    /// Живые tmux-сессии на выбранном хосте, для рейла сессий.
    public internal(set) var liveSessions: [TmuxSession] = []
    /// Черновик имени при создании новой сессии.
    public var newSessionName = ""

    /// Открытые «спейсы» — хосты, к которым в этой сессии подключались, в
    /// порядке открытия. Рейл терминала показывает их сверху; между ними
    /// переключаются, не теряя того, что крутится на сервере в tmux.
    public internal(set) var spaces: [ServerHost.ID] = []
    /// Какая сессия была открыта в каждом спейсе — чтобы вернуться в неё, а не
    /// в «main», когда переключаешься обратно.
    var spaceSessions: [ServerHost.ID: String] = [:]

    /// Одна tmux-сессия на сервере: имя, сколько окон, подключён ли кто-то.
    public struct TmuxSession: Identifiable, Sendable, Equatable {
        public var id: String { name }
        public var name: String
        public var windows: Int
        public var attached: Bool
    }
    public internal(set) var myFingerprint: String?
    public internal(set) var keysError: String?
    public var pendingKeyRemoval: AuthorizedKey?
    public var isAddingKey = false
    public var newKeyLine = ""

    /// Что мы поняли из вставленной строки. Пусто — значит это не ключ.
    public var newKeyPreview: String? {
        guard let key = AuthorizedKeysFile.parse(newKeyLine).first else { return nil }
        return "\(key.algorithm) · \(key.fingerprint)"
    }

    /// Настройка сервера.
    public internal(set) var provisionSteps: [StepProgress] = []
    public internal(set) var provisionLog = RingBuffer<String>(capacity: 4_000)
    public internal(set) var isProvisioning = false
    public internal(set) var plannedCommands: [(step: String, commands: [String])] = []
    public var showsPlannedCommands = false
    var runner: ProvisionRunner?

    /// Разрушающее действие, ожидающее подтверждения.
    public var pendingAction: PendingAction?
    public var pendingResource: PendingResource?

    /// Разрушающее действие над образом, томом или сетью, ждущее ответа.
    public struct PendingResource: Identifiable, Sendable {
        public let id = UUID()
        public var action: ResourceAction
    }
    /// Итог последнего действия — одной строкой под списком.
    public var lastOutcome: ActionOutcome?
    /// Логи выбранного контейнера. Кольцевой: логи умеют идти мегабайтами.
    public internal(set) var logs = RingBuffer<LogLine>(capacity: 5_000)
    /// Счётчик строк лога. Номер нужен только для анимации появления: по
    /// смещению в кольцевом буфере строку не опознать — оно сдвигается.
    var logCounter: UInt64 = 0
    var logTask: Task<Void, Never>?

    /// Действие, которому нужно «да» от человека.
    public struct PendingAction: Identifiable, Sendable {
        public var id = UUID()
        public var action: ContainerAction
        public var container: Container
    }

    public var strings: Strings { Strings(language: language) }

    /// Строфа выбирается один раз за запуск: `welcome` — вычисляемое, и без
    /// этого стих менялся бы на каждой перерисовке экрана.
    private let verseIndex = Int.random(in: 0..<Welcome.verseCount)

    /// Приветствие, которое открывает развёртка экрана входа.
    public var welcome: Welcome {
        Welcome(
            language: language,
            lastLogin: connectionEvents.first?.time,
            verseIndex: verseIndex
        )
    }

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
        // Постоянные сессии (herdr-стиль): шелл живёт внутри tmux на сервере и
        // переживает закрытие приложения. Выключено — обычный одноразовый шелл.
        let session = persistentSessions ? (terminalSession ?? "main") : nil
        return .remote(
            host: host, reach: book.reach(for: host), controlPath: socket, session: session)
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
        var theme = theme(id: id)
        // Личные настройки перекрывают тему: тема — общий пресет, а рябь и
        // свечение зависят от монитора и от того, кто на него смотрит.
        if let scanlines { theme.scanlines = scanlines }
        if let glow { theme.glow = glow }
        if let vignette { theme.vignette = vignette }
        return Style(
            theme: theme, fontSize: fontSize, lineHeight: lineHeight, motion: motion.scale)
    }

    /// Хост, к которому прямо сейчас идёт соединение или прощупывание.
    ///
    /// Именно этот отрезок и стоит показывать: он длится секунды, а всё
    /// остальное время состояние либо «готов», либо «отказ с причиной».
    public func isConnecting(_ host: ServerHost) -> Bool {
        guard selectedHost == host.id else { return false }
        switch sessionState.phase {
        case .connecting, .probing: return true
        case .idle, .ready, .failed: return false
        }
    }

    public var visibleHosts: [ServerHost] {
        book.search(query, groupID: selectedGroup)
    }

    private let appearance = AppearanceStore()
    var gate: any BiometricGate
    let profiles: ProfileStore
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
        // Окно повторного Touch ID из настроек: короче — безопаснее.
        self.biometricReuseSeconds = saved.biometricReuseSeconds ?? 10
        self.gate.reuseDuration = self.biometricReuseSeconds
        themeID = saved.themeID
        language = Language(rawValue: saved.language) ?? .system
        pet = Pet(rawValue: saved.pet) ?? .cat
        eggs = EasterEggs(enabled: saved.eggsEnabled)
        fontSize = saved.fontSize
        ligatures = saved.ligatures
        lineHeight = saved.lineHeight
        scanlines = saved.scanlines
        glow = saved.glow
        vignette = saved.vignette
        petVisible = saved.petVisible ?? true
        pollSeconds = saved.pollSeconds ?? 4
        logLines = saved.logLines ?? 5_000
        logs = RingBuffer(capacity: logLines)
        motion = MotionAmount(rawValue: saved.motion ?? "") ?? .full
        connectMotion = ConnectMotion(rawValue: saved.connectMotion ?? "") ?? .sweep
        logMotion = LogMotion(rawValue: saved.logMotion ?? "") ?? .rise
    }

    /// Сохраняет внешний вид. Вызывается из представлений при изменении.
    public func saveAppearance() {
        appearance.save(
            Appearance(
                themeID: themeID,
                language: language.rawValue,
                pet: pet.rawValue,
                eggsEnabled: eggs.enabled,
                fontSize: fontSize,
                ligatures: ligatures,
                lineHeight: lineHeight,
                scanlines: scanlines,
                glow: glow,
                vignette: vignette,
                petVisible: petVisible,
                pollSeconds: pollSeconds,
                logLines: logLines,
                motion: motion.rawValue,
                connectMotion: connectMotion.rawValue,
                logMotion: logMotion.rawValue,
                biometricReuseSeconds: biometricReuseSeconds
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
            try await gate.authenticate(reason: strings("auth.reason"))
            await loadProfile()
            isUnlocked = true
        } catch GateError.unavailable(let reason) {
            unlockError = "\(strings("auth.unavailable")) \(reason)"
        } catch GateError.lockedOut {
            unlockError = strings("auth.lockedOut")
        } catch {
            unlockError = strings("auth.cancelled")
        }
    }

    public func lock() {
        isUnlocked = false
    }

    private func loadProfile() async {
        do {
            book = try await profiles.load(HostBook.self, reason: strings("auth.reason"))
            syncForwardsFromBook()
        } catch ProfileStoreError.empty {
            // Первый запуск: список пуст. Ничего не выдумываем — человек либо
            // импортирует свои серверы (~/.ssh, известные хосты, история
            // Termius), либо заводит хост руками. Экран хостов подсказывает как.
            book = HostBook()
        } catch ProfileStoreError.keyLost {
            unlockError = strings("vault.keyLost")
        } catch {
            unlockError = "\(strings("vault.unreadable")) \(error.localizedDescription)"
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
        // Хост становится спейсом при первом подключении; порядок сохраняем.
        if !spaces.contains(host.id) { spaces.append(host.id) }
        // Возвращаемся в ту сессию, что была открыта в этом спейсе.
        terminalSession = spaceSessions[host.id]
        let transport = SystemSSHTransport(host: host, reach: book.reach(for: host))
        sessionSocketPath = transport.socketPath
        let fresh = HostSession(host: host, transport: transport)
        session = fresh
        sessionState = SessionState()
        await fresh.setPollInterval(.seconds(pollSeconds))
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
            // Подключились к тому, чего нет в списке, — предлагаем запомнить.
            // Именно предлагаем: список засоряется, только если человек согласен.
            if !isSaved(host) { rememberOffer = host }
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
            try? await profiles.save(book, reason: strings("auth.saveReason"))
        }
    }

}
