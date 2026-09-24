import Foundation

/// Подписи для того, что приходит из пакетов (см. `Strings+Packages.swift`).
///
/// Отдельно от основной таблицы: у неё свой потолок длины, а эти строки
/// растут вместе с пакетами, а не с экранами.
extension Strings {
    static let packageTable: [String: [Language: String]] = [
        "reach.direct": [.russian: "напрямую", .english: "direct"],
        "reach.proxy": [.russian: "прокси", .english: "proxy"],
        "reach.jump": [.russian: "через бастион", .english: "via bastion"],
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
            .russian: "все сети, к которым никто не подключён", .english: "every network with nothing attached",
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
            .russian: "данные внутри тома пропадут навсегда", .english: "the data in the volume is gone for good",
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
            .russian: "ключ хоста %@ изменился — подключение остановлено",
            .english: "the host key of %@ changed — connection stopped",
        ],
        "err.hostKeyChangedPlain": [
            .russian: "ключ хоста изменился — подключение остановлено",
            .english: "the host key changed — connection stopped",
        ],
        "err.unreachable": [
            .russian: "%@ не отвечает — сервер выключен, адрес неверный или порт закрыт",
            .english: "%@ is not answering — the server is off, the address is wrong or the port is closed",
        ],
        "err.connectFailed": [
            .russian: "не удалось подключиться к %@ — попробуй ssh из обычного Терминала, он покажет причину",
            .english: "could not connect to %@ — try ssh from the regular Terminal, it will show why",
        ],
        "err.exitCode": [.russian: "команда завершилась с кодом %@", .english: "the command exited with code %@"],
        "err.cancelled": [.russian: "отменено", .english: "cancelled"],
        "err.done": [.russian: "готово", .english: "done"],
        "err.dockerSocket": [
            .russian: "нет доступа к сокету docker — нужен sudo или группа docker",
            .english: "no access to the docker socket — needs sudo or the docker group",
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
    ]
}
