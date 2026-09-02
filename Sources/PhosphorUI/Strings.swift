public import Foundation

/// Interface language. Both are first class; the default follows the system.
public enum Language: String, CaseIterable, Sendable {
    case russian = "ru"
    case english = "en"

    public var title: String {
        switch self {
        case .russian: "Русский"
        case .english: "English"
        }
    }

    /// Best match for the user's system preference.
    public static var system: Language {
        let preferred = Locale.preferredLanguages.first ?? "en"
        return preferred.hasPrefix("ru") ? .russian : .english
    }
}

/// Every string the interface shows.
///
/// Keys are English; nothing is hard-coded in a view. Keeping the table in one
/// place also keeps the two languages honest — a missing translation is visible
/// here rather than at runtime.
public struct Strings: Sendable {
    public var language: Language

    public init(language: Language = .system) { self.language = language }

    public func callAsFunction(_ key: String) -> String {
        Self.table[key]?[language] ?? key
    }

    private static let table: [String: [Language: String]] = [
        // Lock screen
        "lock.touch": [.russian: "приложи палец", .english: "touch to unlock"],
        "lock.reading": [.russian: "читаю отпечаток", .english: "reading fingerprint"],
        "lock.open": [.russian: "доступ открыт", .english: "access granted"],
        "lock.noAccount": [
            .russian: "ни логина, ни пароля. учётной записи нет — есть профиль на этой машине",
            .english: "no login, no password. there is no account — only a profile on this Mac",
        ],
        "lock.fallback": [
            .russian: "нет Touch ID? apple watch · пароль учётной записи",
            .english: "no Touch ID? apple watch · account password",
        ],
        "lock.locked": [.russian: "заблокировано", .english: "locked"],
        "lock.unlocked": [.russian: "открыто", .english: "unlocked"],
        "lock.vault": [
            .russian: "секреты не покидают Secure Enclave",
            .english: "secrets never leave the Secure Enclave",
        ],

        // Sections
        "nav.hosts": [.russian: "хосты", .english: "hosts"],
        "nav.keys": [.russian: "ключи", .english: "keys"],
        "nav.forwarding": [.russian: "проброс портов", .english: "port forwarding"],
        "nav.snippets": [.russian: "сниппеты", .english: "snippets"],
        "nav.known": [.russian: "известные хосты", .english: "known hosts"],
        "nav.log": [.russian: "журнал", .english: "log"],
        "nav.containers": [.russian: "контейнеры", .english: "containers"],
        "nav.images": [.russian: "образы", .english: "images"],
        "nav.volumes": [.russian: "тома", .english: "volumes"],
        "nav.networks": [.russian: "сети", .english: "networks"],
        "nav.overview": [.russian: "обзор", .english: "overview"],
        "nav.processes": [.russian: "процессы", .english: "processes"],
        "nav.storage": [.russian: "память и диски", .english: "memory and disks"],
        "nav.netStat": [.russian: "сеть", .english: "network"],
        "nav.journal": [.russian: "журнал", .english: "journal"],
        "nav.access": [.russian: "доступ", .english: "access"],
        "nav.tools": [.russian: "инструменты", .english: "tools"],
        "nav.palette": [.russian: "палитра", .english: "palette"],
        "nav.glass": [.russian: "стекло", .english: "glass"],
        "nav.language": [.russian: "язык и отсылки", .english: "language and eggs"],

        // Tabs
        "tab.terminal": [.russian: "терминал", .english: "terminal"],
        "tab.docker": [.russian: "docker", .english: "docker"],
        "tab.files": [.russian: "файлы", .english: "files"],
        "tab.monitor": [.russian: "мониторинг", .english: "monitor"],
        "tab.theme": [.russian: "тема", .english: "theme"],
        "tab.provision": [.russian: "настройка", .english: "provision"],
        "tab.activity": [.russian: "активность ии", .english: "ai activity"],

        // Hosts
        "hosts.search": [
            .russian: "найти хост, тег, группу или user@host…",
            .english: "find a host, tag, group or user@host…",
        ],
        "hosts.connect": [.russian: "подключиться", .english: "connect"],
        "hosts.new": [.russian: "+ новый хост", .english: "+ new host"],
        "hosts.import": [.russian: "импорт ~/.ssh/config", .english: "import ~/.ssh/config"],
        "hosts.groups": [.russian: "группы", .english: "groups"],
        "hosts.all": [.russian: "хосты", .english: "hosts"],
        "hosts.filterHint": [.russian: "нажми, чтобы отфильтровать", .english: "click to filter"],
        "hosts.clearFilter": [.russian: "нажми ещё раз — снять", .english: "click again to clear"],
        "hosts.empty": [.russian: "ничего не найдено", .english: "nothing found"],

        // Docker
        "docker.containers": [.russian: "контейнеры", .english: "containers"],
        "docker.logs": [.russian: "логи", .english: "logs"],
        "docker.overview": [.russian: "обзор", .english: "overview"],
        "docker.env": [.russian: "переменные", .english: "environment"],
        "docker.restart": [.russian: "перезапустить", .english: "restart"],
        "docker.stop": [.russian: "остановить", .english: "stop"],
        "docker.remove": [.russian: "удалить", .english: "remove"],
        "docker.secretsHidden": [
            .russian: "секреты замаскированы и не попадают в аудит",
            .english: "secrets are masked and never reach the audit log",
        ],

        // Monitor
        "monitor.cores": [.russian: "ядра", .english: "cores"],
        "monitor.memory": [.russian: "память", .english: "memory"],
        "monitor.disks": [.russian: "диски", .english: "disks"],
        "monitor.network": [.russian: "сеть", .english: "network"],
        "monitor.steal": [.russian: "сосед по гипервизору", .english: "noisy neighbour"],
        "monitor.uptime": [.russian: "аптайм", .english: "uptime"],

        // Keys
        "keys.yours": [.russian: "твой", .english: "yours"],
        "keys.current": [
            .russian: "этим ключом ты подключён сейчас", .english: "you are connected with this key",
        ],
        "keys.weak": [.russian: "слабый ключ", .english: "weak key"],
        "keys.lockout": [
            .russian: "удалить ключ, которым ты подключён, можно только с подтверждением",
            .english: "removing the key you are connected with needs explicit confirmation",
        ],

        // Provisioning
        "provision.fresh": [.russian: "свежий сервер", .english: "fresh server"],
        "provision.offer": [
            .russian: "сервер только что поднят и пуст. Настроить по обычному рецепту?",
            .english: "this server was just brought up and is empty. Run the usual recipe?",
        ],
        "provision.run": [.russian: "настроить", .english: "provision"],
        "provision.show": [.russian: "показать команды", .english: "show commands"],
        "provision.later": [.russian: "позже", .english: "later"],
        "provision.done": [.russian: "готово", .english: "done"],
        "provision.running": [.russian: "идёт", .english: "running"],
        "provision.waiting": [.russian: "ожидает", .english: "waiting"],
        "provision.skipped": [.russian: "уже есть", .english: "already there"],

        // Settings
        "settings.language": [.russian: "язык интерфейса", .english: "interface language"],
        "settings.pet": [.russian: "питомец", .english: "pet"],
        "settings.eggs": [.russian: "отсылки", .english: "easter eggs"],
        "settings.theme": [.russian: "тема", .english: "theme"],

        // Easter eggs — translated, never transliterated.
        "egg.unbreakable": [.russian: "неуязвимый", .english: "unbreakable"],
        "egg.horde": [.russian: "орда собралась", .english: "the horde has gathered"],
        "egg.eclipse": [.russian: "затмение", .english: "the eclipse"],
        "egg.shadowClone": [.russian: "теневое клонирование", .english: "shadow clone technique"],
        "egg.firstRule": [
            .russian: "первое правило: никто не входит по паролю",
            .english: "first rule: nobody logs in with a password",
        ],
        "egg.waitForIt": [.russian: "это будет… подожди…", .english: "it's gonna be… wait for it…"],
        "egg.legendary": [.russian: "…легендарно", .english: "…legendary"],
    ]
}
