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
    /// Почему профиль не записался в последний раз; `nil` — записан.
    ///
    /// Молча упавшая запись — худшая из ошибок этого приложения: человек видит
    /// свои серверы, а после закрытия окна их больше нет.
    public internal(set) var saveError: String?
    /// Можно ли писать профиль: он прочитан с диска или его там ещё не было.
    var profileWritable = false
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
    /// Что можно перенести в список: считается один раз, когда список пуст.
    public internal(set) var importOffers: [ImportOffer] = []
    public var isAddingHost = false
    /// Окно быстрого подключения по ⇧⌘O.
    public var isQuickConnectOpen = false
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
    /// Что сейчас едет по проводу: имя файла и сторона. nil — очередь пуста.
    /// Одна передача за раз: два scp по одному сокету делят полосу и время
    /// выполнения обоих только растёт.
    public internal(set) var transfer: FileTransfer?
    /// Откуда брать файл, принесённый из Finder: он лежит вне локальной панели,
    /// и его путь иначе было бы неоткуда взять.
    var droppedSource: URL?
    /// Передача, упирающаяся в уже существующий файл. Заменить или нет —
    /// решает человек: молча затереть чужую работу нельзя.
    public var pendingOverwrite: FileTransfer?

    /// Одна передача файла: что, куда и в какую сторону.
    public struct FileTransfer: Identifiable, Sendable, Equatable {
        public enum Direction: Sendable { case download, upload }
        public var id = UUID()
        public var file: RemoteFile
        public var direction: Direction
        /// Полный путь на принимающей стороне — он же то, что может быть занято.
        public var destination: String
    }

    /// Журнал действий ИИ и режимы доступа по хостам.
    public internal(set) var auditEntries: [AuditEntry] = []
    public internal(set) var mcpModes: [ServerHost.ID: MCPMode] = [:]
    let policy = AccessPolicy()
    let audit = AuditLog()
    /// Локальный сокет для MCP-клиентов; живёт, пока открыто приложение.
    var bridge: SocketServer?
    public internal(set) var bridgeError: String?
    /// Где Claude Code видит мост; `nil` — ещё не проверяли.
    public internal(set) var claudeCodeStatus: ClientRegistration.Status?
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

    /// Живые поверхности терминала. Лежат рядом с моделью, а не внутри вида:
    /// SwiftUI пересоздаёт вид на каждом переключении раздела, и шелл вместе с
    /// ним начинался бы заново.
    public let surfaces = TerminalSurfaces()

    /// Держать шелл внутри tmux на сервере, чтобы он пережил закрытие
    /// приложения и обрыв сети. По духу herdr — включено по умолчанию.
    public var persistentSessions = true
    /// Имя tmux-сессии, к которой сейчас подключён терминал. nil — «main».
    public var terminalSession: String?
    /// Живые tmux-сессии на выбранном хосте, для рейла сессий.
    public internal(set) var liveSessions: [TmuxSession] = []
    /// Есть ли tmux на выбранном хосте. Нет — постоянные сессии невозможны, и
    /// шелл каждый раз начинается с нуля. Про это говорят прямо: молчаливый
    /// откат оставляет человека гадать, почему терминал всегда чистый.
    public internal(set) var hasTmux = true
    /// Черновик имени при создании новой сессии.
    public var newSessionName = ""

    /// Слежение за сессиями: агент упирается в вопрос молча, и если не
    /// спрашивать сервер, человек узнает об этом, только когда сам заглянет
    /// в раздел. nil — слежение не идёт.
    var sessionWatch: Task<Void, Never>?
    /// Смотрит ли кто-нибудь на окно. Опрос замирает, когда нет.
    var windowActive = true

    /// Сколько сессий ждут ответа человека. Ради этого числа в шапке горит
    /// метка у «Терминала», даже когда открыт другой раздел.
    public var blockedSessions: Int {
        (liveSessions + localSessions + [plainShell].compactMap(\.self)).reduce(into: 0) { total, session in
            if session.status == .blocked { total += 1 }
        }
    }

    /// Открытые «спейсы» — хосты, к которым в этой сессии подключались, в
    /// порядке открытия. Рейл терминала показывает их сверху; между ними
    /// переключаются, не теряя того, что крутится на сервере в tmux.
    public internal(set) var spaces: [ServerHost.ID] = []
    /// Какая сессия была открыта в каждом спейсе — чтобы вернуться в неё, а не
    /// в «main», когда переключаешься обратно.
    var spaceSessions: [ServerHost.ID: String] = [:]

    /// Путь к tmux на этом Маке. nil — его тут нет, и локальные сессии
    /// перезапуск не переживут. Ищется фактом при запуске.
    public internal(set) var localTmuxPath: String?
    /// Живые локальные сессии — те же, что у сервера, только здесь. У herdr
    /// локальные рабочие пространства стоят в одном списке с серверными.
    public internal(set) var localSessions: [TmuxSession] = []
    /// Обычный шелл этого Мака как сессия: кто в нём на переднем плане и ждёт ли.
    public internal(set) var plainShell: TmuxSession?
    /// Локальная сессия, на которую смотрит терминал. nil — обычный
    /// одноразовый шелл.
    public var localSession: String?
    /// Смотрит ли терминал на этот Мак, а не на сервер.
    public var localFocused = false

    /// Куда пишется раскладка раздела «Терминал». Читается она не здесь, а
    /// когда откроется профиль: до него список хостов пуст, и сверить
    /// идентификаторы спейсов не с чем.
    let layoutStore = TerminalLayoutStore()
    /// Спейс, в который вернёмся, когда человек откроет «Терминал». Само
    /// подключение отложено намеренно: лезть в сеть на разблокировке окна —
    /// не то, чего ждёшь от входа по отпечатку.
    var pendingFocus: ServerHost.ID?

    /// Дополнительные панели: имена tmux-сессий рядом с основной, в порядке
    /// появления. Пусто — одна панель.
    ///
    /// Раньше здесь была ровно одна «вторая панель» (`secondSession`), но у
    /// herdr панелей внутри рабочего места столько, сколько нужно: агент,
    /// его же тесты и лог рядом — это три ленты, а не две.
    public var extraSessions: [String] = []
    /// Сколько панелей держим одновременно. За каждой стоит живой `ssh` и свой
    /// скроллбэк, а на экране ноутбука пятая панель — это уже не работа.
    public static let paneLimit = 4

    /// Одна панель сплита: имя сессии и её адрес.
    public struct Pane: Identifiable {
        public var id: String { name }
        public var name: String
        public var destination: TerminalHost.Destination
    }
    /// Делить экран по вертикали (панели рядом) или по горизонтали (одна над
    /// другой).
    public var splitVertical = true

    /// Одна tmux-сессия на сервере: имя, сколько окон, подключён ли кто-то.
    public struct TmuxSession: Identifiable, Sendable, Equatable {
        public var id: String { name }
        public var name: String
        public var windows: Int
        public var attached: Bool
        /// Что в ней происходит прямо сейчас — по переднему процессу.
        public var status: SessionStatus = .idle
        /// Кодирующий агент, найденный в её панелях. nil — там обычная работа
        /// руками. Ради этого поля рейл и отличается от списка процессов:
        /// видно не «что-то крутится», а «Claude Code ждёт ответа».
        public var agent: CodingAgent?
    }

    /// Состояние сессии, как у «агентов» herdr.
    ///
    /// Определяется эвристикой по tmux: у шелла-приглашения — покой, у чужого
    /// процесса с недавней активностью — работа, у процесса, что давно молчит, —
    /// вероятно, ждёт ввода. Это догадка, а не факт, и подаётся как подсказка.
    public enum SessionStatus: String, Sendable, Equatable {
        case idle, working, blocked
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
    public internal(set) var plannedCommands: [RecipeStep] = []
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
        #"{"mcpServers":{"phosphor":{"command":"\#(shimPath)"}}}"#
    }


    /// Куда смотрит терминал: на этот Мак или на выбранный сервер.
    public var terminalDestination: TerminalHost.Destination {
        if localFocused { return localDestination }
        return destination(session: terminalSession ?? "main") ?? .local
    }

    /// Куда смотрит терминал на этом Маке: в постоянную сессию, если она
    /// выбрана и tmux здесь есть, иначе — обычный одноразовый шелл.
    public var localDestination: TerminalHost.Destination {
        guard persistentSessions, let name = localSession, let tmux = localTmuxPath,
            let safe = SSHInvocation.tmuxSessionName(name)
        else { return .local }
        return .localSession(name: safe, tmux: tmux)
    }

    /// Дополнительные панели с их адресами. Пусто — панель одна.
    ///
    /// Сплит принадлежит серверному спейсу: смотрим на этот Мак — показываем
    /// одну панель, а остальные ждут возвращения на хост вместе со своими
    /// лентами.
    public var extraPanes: [Pane] {
        guard !localFocused else { return [] }
        return extraSessions.compactMap { name in
            destination(session: name).map { Pane(name: name, destination: $0) }
        }
    }

    /// Адрес названной сессии на выбранном хосте. nil — смотреть не на что:
    /// хост не выбран или соединение к нему ещё не поднято.
    ///
    /// Адрес — он же ключ живой поверхности, поэтому он обязан быть одним и тем
    /// же при каждом обращении: иначе панель показывала бы новый шелл там, где
    /// человек оставил работающий.
    func destination(session name: String) -> TerminalHost.Destination? {
        guard let id = selectedHost,
            let host = book.hosts.first(where: { $0.id == id }),
            let socket = sessionSocketPath
        else { return nil }
        // Постоянные сессии (herdr-стиль): шелл живёт внутри tmux на сервере и
        // переживает закрытие приложения. Выключено — обычный одноразовый шелл.
        return .remote(
            host: host, reach: book.reach(for: host), controlPath: socket,
            session: persistentSessions ? name : nil)
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
    var saveTask: Task<Void, Never>?

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
        // tmux на этом Маке ищем сразу: от ответа зависит, обещает ли рейл
        // локальные сессии или честно говорит, что их не будет.
        localTmuxPath = LocalTmux.find()
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
            let proof = try await gate.authenticate(reason: strings("auth.reason"))
            guard await loadProfile(proof: proof) else { return }
            isUnlocked = true
            // Дверь открыта — можно спрашивать о сессиях, не дожидаясь, пока
            // человек сам зайдёт в раздел: метка о ждущем агенте нужна раньше.
            startSessionWatch()
        } catch let failure as GateError where failure != .refused {
            unlockError = strings.gateError(failure)
        } catch {
            unlockError = strings("auth.cancelled")
        }
    }

    public func lock() {
        isUnlocked = false
        // За закрытой дверью спрашивать не о чем: опрос сессий останавливаем
        // вместе с интерфейсом. Сами сессии это не трогает — они на серверах.
        stopSessionWatch()
    }

    /// Читает профиль. `false` — окно остаётся на экране входа.
    ///
    /// Пустой список в памяти не должен выглядеть как первый запуск, когда
    /// профиль на диске есть, но не открылся: первая же правка записала бы
    /// пустышку поверх настоящих серверов. Поэтому запись разрешается, только
    /// если профиль прочитан или его действительно ещё нет.
    private func loadProfile(proof: OwnerProof) async -> Bool {
        profileWritable = false
        do {
            book = try await profiles.load(HostBook.self, reason: strings("auth.reason"), proof: proof)
            syncForwardsFromBook()
            await syncMCPModesFromBook()
            // Список хостов на месте — значит есть с чем сверить спейсы из
            // прошлого запуска.
            restoreLayout()
        } catch ProfileStoreError.empty {
            // Первый запуск: список пуст. Ничего не выдумываем — человек либо
            // импортирует свои серверы (~/.ssh, известные хосты, история
            // Termius), либо заводит хост руками. Экран хостов подсказывает как.
            book = HostBook()
        } catch SecretError.denied {
            // «Отмена» на запросе связки ключей — не повод открывать окно:
            // вторая попытка откроет профиль как обычно.
            unlockError = strings("auth.cancelled")
            return false
        } catch ProfileStoreError.keyLost {
            holdWrites(strings("vault.keyLost"))
            return true
        } catch ProfileStoreError.enrollmentChanged, SecretError.enrollmentChanged {
            // Не «что-то пошло не так»: палец добавили или убрали, и записи под
            // прежним набором больше не открываются никогда. Человеку нужно
            // знать именно это — иначе он будет прикладывать палец по кругу.
            holdWrites(strings("vault.enrollmentChanged"))
            return true
        } catch {
            holdWrites("\(strings("vault.unreadable")) \(strings.describe(error))")
            return true
        }
        profileWritable = true
        saveError = nil
        return true
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
        // Спейс открыт — запоминаем раскладку, чтобы перезапуск её вернул.
        saveLayout()
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
            // Есть живое соединение — значит есть у кого спрашивать про сессии.
            startSessionWatch()
            await startAutoForwards()
            // Подключились к тому, чего нет в списке, — предлагаем запомнить.
            // Именно предлагаем: список засоряется, только если человек согласен.
            if !isSaved(host) { rememberOffer = host }
        case .failed(let reason):
            await record(.failed, host: host, detail: strings.connectionFailure(reason))
        default:
            break
        }
    }

    /// Переносит данные сессии в поля, из которых рисуются панели.
    private func adopt(_ state: SessionState) {
        profile = state.profile
        if let snapshot = state.latest { snapshots.append(snapshot) }
        // «Когда я был здесь в прошлый раз» и «что это за система» — карточка
        // хоста обещает и то и другое. Запись бережливая: чаще раза в минуту
        // она не меняется, иначе каждый снимок метрик тянул бы перешифровку
        // профиля.
        if let id = selectedHost, book.remember(id, osName: state.profile?.osName) {
            scheduleSave()
        }
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
        // Список серверных сессий гасим, чтобы в шапке не горела метка от
        // хоста, с которым мы уже простились. Слежение при этом продолжается:
        // сессии на этом Маке живут и без соединения.
        liveSessions = []
    }

    /// Приостанавливает опрос, когда окно ушло на второй план.
    public func setWindowActive(_ active: Bool) async {
        windowActive = active
        await session?.setActive(active)
        // Слежение за сессиями — такой же опрос: фоновому окну незачем будить
        // ни процессор, ни сервер.
        if active {
            startSessionWatch()
        } else {
            stopSessionWatch()
        }
    }

    /// Планирует запись профиля, схлопывая частые правки в одну.
    public func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task {
            // `try?`: сон прерывает только отмена, а отмена значит, что пришла
            // правка новее и её запись уже запланирована.
            try? await Task.sleep(for: .milliseconds(700))
            guard !Task.isCancelled else { return }
            await writeProfile()
        }
    }

}
