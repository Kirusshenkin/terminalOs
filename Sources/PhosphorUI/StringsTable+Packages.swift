import Foundation

/// Подписи для того, что приходит из пакетов (см. `Strings+Packages.swift`).
///
/// Отдельно от основной таблицы: у неё свой потолок длины, а эти строки
/// растут вместе с пакетами, а не с экранами.
extension Strings {
    static let packageTable: [String: [Language: String]] = [
        // Перезапуск ради обновления (здесь, а не в основной таблице: та у предела длины).
        "upd.interruptTitle": [.russian: "перезапуск оборвёт работу агента", .english: "restarting will stop an agent"],
        "upd.interruptBody": [
            .russian: "работает в обычном шелле этого Мака и завершится при перезапуске. Сессии tmux не пострадают — "
                + "в следующий раз запускай агента в tmux-сессии (+ у «этот мак»)",
            .english: "is running in the plain shell of this Mac and will end on restart. tmux sessions are not affected — "
                + "next time start the agent in a tmux session (+ next to this Mac)",
        ],
        "upd.interruptGo": [.russian: "всё равно обновить", .english: "update anyway"],
        "reach.direct": [.russian: "напрямую", .english: "direct"],
        "reach.proxy": [.russian: "прокси", .english: "proxy"],
        "reach.jump": [.russian: "через бастион", .english: "via bastion"],
        "host.viaBastion": [.russian: "через бастион", .english: "through a bastion"],
        "host.pickBastion": [.russian: "выбери хост-бастион", .english: "pick a bastion host"],
        "host.noBastions": [
            .russian: "сначала добавь сам бастион как обычный хост",
            .english: "add the bastion itself as a regular host first",
        ],
        "guard.never": [.russian: "не спрашивать", .english: "never ask"],
        "guard.dangerous": [.russian: "при опасных действиях", .english: "on dangerous actions"],
        "guard.always": [.russian: "при подключении", .english: "on connect"],
        "mode.disabled": [.russian: "выключено", .english: "off"],
        "mode.readOnly": [.russian: "только чтение", .english: "read only"],
        "mode.confirm": [.russian: "с подтверждением", .english: "with confirmation"],
        "mode.full": [.russian: "полный", .english: "full"],
        "clog.connected": [.russian: "подключение", .english: "connected"],
        "clog.disconnected": [.russian: "отключение", .english: "disconnected"],
        "clog.failed": [.russian: "не удалось", .english: "failed"],
        "cstate.running": [.russian: "работает", .english: "running"],
        "cstate.exited": [.russian: "остановлен", .english: "stopped"],
        "cstate.paused": [.russian: "на паузе", .english: "paused"],
        "cstate.restarting": [.russian: "перезапускается", .english: "restarting"],
        "cstate.created": [.russian: "создан", .english: "created"],
        "cstate.dead": [.russian: "мёртв", .english: "dead"],
        "cstate.unknown": [.russian: "неизвестно", .english: "unknown"],
        "caction.start": [.russian: "запустить", .english: "start"],
        "caction.stop": [.russian: "остановить", .english: "stop"],
        "caction.restart": [.russian: "перезапустить", .english: "restart"],
        "caction.pause": [.russian: "приостановить", .english: "pause"],
        "caction.unpause": [.russian: "продолжить", .english: "resume"],
        "caction.kill": [.russian: "убить", .english: "kill"],
        "caction.remove": [.russian: "удалить", .english: "remove"],
        "res.pruneImages": [.russian: "удалить безымянные образы", .english: "remove untagged images"],
        "res.pruneVolumes": [.russian: "удалить неиспользуемые тома", .english: "remove unused volumes"],
        "res.pruneNetworks": [.russian: "удалить неиспользуемые сети", .english: "remove unused networks"],
        "res.pruneImagesSubject": [.russian: "все образы без имени", .english: "every untagged image"],
        "res.pruneVolumesSubject": [
            .russian: "все тома, которые никто не подключил", .english: "every volume no container uses",
        ],
        "res.pruneNetworksSubject": [
            .russian: "все сети, к которым никто не подключён",
            .english: "every network with nothing attached",
        ],
        "res.removeImageWarning": [
            .russian: "образ придётся качать заново; контейнеры на нём удалить не даст",
            .english: "the image will have to be pulled again; containers using it block the removal",
        ],
        "res.pruneImagesWarning": [
            .russian: "слои без имени уйдут — следующая сборка будет дольше",
            .english: "untagged layers go away — the next build will take longer",
        ],
        "res.removeVolumeWarning": [
            .russian: "данные внутри тома пропадут навсегда",
            .english: "the data in the volume is gone for good",
        ],
        "res.pruneVolumesWarning": [
            .russian: "данные всех неподключённых томов пропадут навсегда",
            .english: "the data in every unused volume is gone for good",
        ],
        "res.removeNetworkWarning": [
            .russian: "контейнеры в этой сети потеряют связь друг с другом",
            .english: "containers on this network lose contact with each other",
        ],
        "res.pruneNetworksWarning": [
            .russian: "пользовательские сети без контейнеров будут удалены",
            .english: "user networks with no containers will be removed",
        ],
        "res.untagged": [.russian: "<без имени>", .english: "<untagged>"],
        "key.weakDSA": [.russian: "DSA — устарел и небезопасен", .english: "DSA — outdated and unsafe"],
        "key.weakRSA": [.russian: "бит — короче 3072", .english: "bits — shorter than 3072"],
        "known.hashed": [.russian: "имя скрыто (запись хеширована)", .english: "name hidden (hashed entry)"],
        "file.symlink": [.russian: "ссылка", .english: "link"],
        "file.directory": [.russian: "папка", .english: "folder"],
        "file.plain": [.russian: "файл", .english: "file"],
        "fwd.local": [.russian: "локальный", .english: "local"],
        "fwd.remote": [.russian: "удалённый", .english: "remote"],
        "fwd.server": [.russian: "сервер", .english: "server"],
        "unit.b": [.russian: "Б", .english: "B"],
        "unit.kb": [.russian: "КБ", .english: "KB"],
        "unit.mb": [.russian: "МБ", .english: "MB"],
        "unit.gb": [.russian: "ГБ", .english: "GB"],
        "unit.tb": [.russian: "ТБ", .english: "TB"],
        "unit.pb": [.russian: "ПБ", .english: "PB"],
        "unit.day": [.russian: "д", .english: "d"],
        "unit.hour": [.russian: "ч", .english: "h"],
        "unit.minute": [.russian: "м", .english: "m"],
        "unit.second": [.russian: "с", .english: "s"],

        // Ошибки пакетов (Strings+Errors.swift). %@ — подстановка.
        "err.proxyDown": [
            .russian: "прокси %@ не отвечает — запущен ли V2Box?",
            .english: "proxy %@ is not answering — is V2Box running?",
        ],
        "err.denied": [
            .russian: "%@ отказал в доступе — ключа нет в authorized_keys?",
            .english: "%@ refused access — is your key missing from authorized_keys?",
        ],
        "err.deniedPlain": [
            .russian: "сервер отказал в доступе — ключа нет в authorized_keys?",
            .english: "the server refused access — is your key missing from authorized_keys?",
        ],
        "err.hostKeyChanged": [
            .russian: "ключ хоста %@ изменился — подключение остановлено. Если сервер переустанавливали, "
                + "убери старый ключ во вкладке «ключи» → «доверенные серверы» и подключись снова; "
                + "если нет — это может быть подмена, не подключайся",
            .english: "the host key of %@ changed — connection stopped. If the server was reinstalled, "
                + "remove the old key in Keys → trusted servers and connect again; "
                + "if not, this may be an impersonation, do not connect",
        ],
        "err.hostKeyChangedPlain": [
            .russian: "ключ хоста изменился — подключение остановлено",
            .english: "the host key changed — connection stopped",
        ],
        "err.hostKeyUnknown": [
            .russian: "%@ ещё не знаком этому Маку: сверь отпечаток ниже с консолью провайдера и нажми «доверять»",
            .english: "%@ is new to this Mac: check the fingerprint below against your provider's console and press trust",
        ],
        "err.trustFailed": [
            .russian: "не удалось записать ключ в ~/.ssh/known_hosts:",
            .english: "could not write the key to ~/.ssh/known_hosts:",
        ],
        "err.scanFailed": [
            .russian: "отпечаток сервера получить не удалось — проверь адрес и порт, затем «переподключиться»",
            .english: "could not get the server's fingerprint — check the address and port, then reconnect",
        ],
        "host.trust": [.russian: "доверять и подключиться", .english: "trust and connect"],
        "host.scanning": [.russian: "получаю отпечаток…", .english: "getting the fingerprint…"],
        "err.hostKeyUnknownPlain": [
            .russian: "сервер ещё не знаком этому Маку — откройте его в Phosphor и примите отпечаток",
            .english: "the server is new to this Mac — open it in Phosphor and accept its fingerprint",
        ],
        "err.viaBastion": [.russian: "бастион: ", .english: "bastion: "],
        "err.routeMissing": [
            .russian: "%@ ходит через бастион, которого больше нет в списке — выбери другой "
                + "в настройках хоста или поставь «напрямую»",
            .english: "%@ goes through a bastion that is no longer in the list — pick another one "
                + "in the host settings or set it to direct",
        ],
        "err.routeLoop": [
            .russian: "цепочка бастионов замкнулась на %@ — хост не может идти через самого себя; "
                + "поправь «как дотянуться» у хостов цепочки",
            .english: "the bastion chain loops back to %@ — a host cannot go through itself; "
                + "fix how the hosts in the chain are reached",
        ],
        "err.routeDeep": [
            .russian: "у %@ больше трёх бастионов подряд — сократи цепочку в настройках хостов",
            .english: "%@ has more than three bastions in a row — shorten the chain in the host settings",
        ],
        "err.unreachable": [
            .russian: "%@ не отвечает — сервер выключен, адрес неверный или порт закрыт",
            .english: "%@ is not answering — the server is off, the address is wrong or the port is closed",
        ],
        "err.connectFailed": [
            .russian: "не удалось подключиться к %@ — попробуй ssh из обычного Терминала, он покажет причину",
            .english: "could not connect to %@ — try ssh from the regular Terminal, it will show why",
        ],
        "err.exitCode": [
            .russian: "команда завершилась с кодом %@", .english: "the command exited with code %@",
        ],
        "err.cancelled": [.russian: "отменено", .english: "cancelled"],
        "err.done": [.russian: "готово", .english: "done"],
        "err.dockerSocket": [
            .russian: "нет доступа к сокету docker: добавь пользователя в группу — "
                + "sudo usermod -aG docker $USER, затем переподключись",
            .english: "no access to the docker socket: add the user to the group — "
                + "sudo usermod -aG docker $USER, then reconnect",
        ],
        "err.dockerGone": [.russian: "этого уже нет", .english: "it is already gone"],
        "err.dockerNotRunning": [.russian: "контейнер не запущен", .english: "the container is not running"],
        "err.dockerStopFirst": [
            .russian: "сначала остановить: удалять работающий контейнер docker не даёт",
            .english: "stop it first: docker will not remove a running container",
        ],
        "err.dockerInUse": [
            .russian: "занято: сначала убрать контейнеры, которые это используют",
            .english: "in use: remove the containers using it first",
        ],
        "err.portTaken": [
            .russian: "порт %@ уже занят на этой машине — возьми другой",
            .english: "port %@ is already taken on this Mac — pick another",
        ],
        "err.forwardNoConnection": [
            .russian: "нет живого соединения с хостом — подключись сначала",
            .english: "no live connection to the host — connect first",
        ],
        "err.portPrivileged": [
            .russian: "порт %@ требует прав — возьми номер выше 1024",
            .english: "port %@ needs privileges — pick a number above 1024",
        ],
        "err.keyLockOut": [
            .russian: "так не останется ни одного рабочего ключа — доступ к серверу пропадёт",
            .english: "that would leave no working key — you would lose access to the server",
        ],
        "err.notAKey": [
            .russian: "строка не похожа на открытый ключ — вставь строку из файла .pub",
            .english: "that line is not a public key — paste the line from a .pub file",
        ],
        "err.secretMissing": [.russian: "записи нет", .english: "no such entry"],
        "err.secretDenied": [.russian: "подтверждение не получено", .english: "confirmation was not given"],
        "err.keychain": [
            .russian: "связка ключей отказала, код %@", .english: "the keychain refused, code %@",
        ],
        "err.profileEmpty": [.russian: "профиля ещё нет", .english: "there is no profile yet"],
        "auth.noMethod": [
            .russian: "на этом Маке нет ни Touch ID, ни пароля учётной записи",
            .english: "this Mac has neither Touch ID nor an account password",
        ],
        "auth.password": [.russian: "пароль", .english: "password"],

        // Автонастройка: шаги по id, причины пропуска и остановки
        "recipe.packages": [
            .russian: "обновить пакеты и unattended-upgrades",
            .english: "update packages and unattended-upgrades",
        ],
        "recipe.docker": [
            .russian: "Docker и Compose с лимитом логов", .english: "Docker and Compose with a log limit",
        ],
        "recipe.nginx": [.russian: "nginx", .english: "nginx"],
        "recipe.certbot": [.russian: "certbot", .english: "certbot"],
        "recipe.ufw": [.russian: "UFW: только 22, 80, 443", .english: "UFW: only 22, 80, 443"],
        "recipe.passwords": [.russian: "закрыть вход по паролю", .english: "close password login"],
        "recipe.installed": [.russian: "%@ уже установлен", .english: "%@ is already installed"],
        "recipe.needsApt": [
            .russian: "нужен apt: Ubuntu или Debian", .english: "needs apt: Ubuntu or Debian",
        ],
        "keys.addedOn": [.russian: "добавлен", .english: "added"],
        "keys.sortName": [.russian: "по имени", .english: "by name"],
        "keys.sortNewest": [.russian: "новые сверху", .english: "newest first"],
        "tmux.install": [.russian: "поставить tmux", .english: "install tmux"],
        "tmux.installing": [.russian: "ставлю tmux…", .english: "installing tmux…"],
        "tmux.confirmTitle": [.russian: "поставить tmux?", .english: "install tmux?"],
        "tmux.confirmRun": [
            .russian: "будет выполнено ровно это:", .english: "exactly this will run:",
        ],
        "tmux.confirmCopy": [
            .russian: "sudo спросит пароль, поэтому команду запустишь ты: "
                + "она скопируется, вставь её в терминал",
            .english: "sudo will ask for a password, so you run it: "
                + "the command is copied, paste it into the terminal",
        ],
        "tmux.run": [.russian: "поставить", .english: "install"],
        "tmux.copy": [.russian: "скопировать", .english: "copy"],
        "tmux.installed": [
            .russian: "tmux на месте — новые сессии переживут перезапуск",
            .english: "tmux is in place — new sessions will survive a restart",
        ],
        "tmux.copied": [
            .russian: "команда в буфере обмена — вставь её в терминал и введи пароль sudo",
            .english: "the command is on the clipboard — "
                + "paste it into the terminal and enter the sudo password",
        ],
        "tmux.failed": [.russian: "tmux не поставился: ", .english: "tmux was not installed: "],
        "tmux.stillMissing": [
            .russian: "установка прошла, но tmux не находится — проверь, куда его поставил пакетный менеджер",
            .english: "the install finished but tmux is not found — check where the package manager put it",
        ],
        "tmux.noHomebrew": [
            .russian: "на этом Маке нет Homebrew — поставь его с brew.sh, затем tmux",
            .english: "there is no Homebrew on this Mac — install it from brew.sh, then tmux",
        ],
        "term.noTmuxNoCommand": [
            .russian: "на сервере нет tmux — шелл начнётся с нуля при каждом заходе. "
                + "поставьте tmux пакетным менеджером этой системы",
            .english: "no tmux on the server — the shell starts over on every visit. "
                + "install tmux with this system's package manager",
        ],
        "recipe.needsLinux": [.russian: "только для Linux", .english: "Linux only"],
        "prov.unsupportedOS": [
            .russian: "этот рецепт не для %@ — его команды здесь не сработают. "
                + "Выбери другой или импортируй свой рецепт для этой системы",
            .english: "this recipe is not for %@ — its commands would not work here. "
                + "Pick another or import your own recipe for this system",
        ],
        "mon.totalOnly": [
            .russian: "загрузка · общая: на macOS по ядрам не разбить",
            .english: "load · total: macOS does not split it by core",
        ],
        "mon.unsupportedOS": [
            .russian: "метрики для %@ пока не собираются — сбор умеет только Linux и macOS. "
                + "Соединение живо: терминал, Docker и файлы работают",
            .english: "metrics for %@ are not collected yet — "
                + "collection only knows Linux and macOS. "
                + "The connection is alive: terminal, Docker and files work",
        ],
        "recipe.noKeys": [
            .russian: "нет ни одного ключа — закрывать пароли нельзя",
            .english: "there is no key at all — closing passwords would lock you out",
        ],
        "recipe.keyNotProven": [
            .russian: "вход по ключу не подтверждён — пароли не закрываю",
            .english: "key login is not confirmed — passwords stay open",
        ],
        "recipe.stopped": [.russian: "остановлено", .english: "stopped"],

        // Импорт Termius
        "hosts.termiusUnreadable": [
            .russian: "дамп Termius не читается", .english: "the Termius dump cannot be read",
        ],
        "hosts.termiusBadFormat": [
            .russian: "дамп Termius повреждён или в другом формате",
            .english: "the Termius dump is damaged or in another format",
        ],
        "hosts.termiusRedo": [
            .russian: "Выгрузи хосты из Termius заново или удали файл — тогда возьмётся история адресов",
            .english: "Export the hosts from Termius again, or delete the file to use the address history",
        ],

        // Очередь одобрений ИИ
        "ai.queue": [.russian: "ждут твоего ответа", .english: "waiting for your answer"],
        "ai.queueMore": [.russian: "ещё в очереди:", .english: "more in the queue:"],
        "ai.denyAll": [.russian: "отказать всем", .english: "deny all"],
    ]
}
