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
    ]
}
