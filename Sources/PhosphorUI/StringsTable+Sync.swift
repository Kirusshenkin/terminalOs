import Foundation

/// Подписи синхронизации между своими машинами (#18).
extension Strings {
    static let syncTable: [String: [Language: String]] = [
        "sync.title": [.russian: "синхронизация машин", .english: "sync between machines"],
        "sync.note": [
            .russian: "Хосты, группы, сниппеты и пробросы — одни на всех твоих Маках. Хранилище — папка "
                + "~/.phosphor-sync на твоём же сервере, он видит только шифртекст. Пароли и ключи "
                + "не уезжают: они в связке ключей каждой машины.",
            .english: "Hosts, groups, snippets and forwards — the same on all your Macs. Storage is the "
                + "~/.phosphor-sync folder on a server of your own, which sees only ciphertext. Passwords "
                + "and keys stay put: they live in each machine's keychain.",
        ],
        "sync.noHosts": [
            .russian: "Сначала добавь сервер: хранилище — папка на нём.",
            .english: "Add a server first: storage is a folder on it.",
        ],
        "sync.storage": [.russian: "хранилище", .english: "storage"],
        "sync.enable": [.russian: "включить", .english: "turn on"],
        "sync.now": [.russian: "синхронизировать", .english: "sync now"],
        "sync.disable": [.russian: "выключить на этой машине", .english: "turn off on this machine"],
        "sync.working": [.russian: "синхронизация…", .english: "syncing…"],
        "sync.synced": [.russian: "синхронизировано %@", .english: "synced %@"],
        "sync.waiting": [
            .russian:
                "Эту машину ещё не пустили. На другой открой Настройки → Профиль и пусти машину с кодом %@.",
            .english: "This machine is not let in yet. On another one, open Settings → Profile and let in "
                + "the machine with code %@.",
        ],
        "sync.confirm": [
            .russian: "Эту машину пустила «%@». Открой на ней Настройки → Профиль: в списке машин у строки "
                + "«эта машина» должен стоять код %@. Совпадает — подтверди. Не совпадает — хранилище подменили, "
                + "ничего не подтверждай.",
            .english: "This machine was let in by «%@». Open Settings → Profile there: the «this machine» "
                + "row must show code %@. If it matches, confirm. If not, storage was tampered with — do not "
                + "confirm.",
        ],
        "sync.trust": [.russian: "код совпадает", .english: "the code matches"],
        "sync.check": [.russian: "проверить", .english: "check"],
        "sync.machines": [.russian: "машины", .english: "machines"],
        "sync.thisMachine": [.russian: "эта машина", .english: "this machine"],
        "sync.revoke": [.russian: "отозвать", .english: "revoke"],
        "sync.revokeConfirm": [
            .russian: "Отозвать «%@»? Она не прочтёт ничего нового, но то, что уже скачала, останется у неё.",
            .english:
                "Revoke «%@»? It will not read anything new, but what it already downloaded stays with it.",
        ],
        "sync.requests": [.russian: "просятся в профиль", .english: "asking to join"],
        "sync.requestNote": [
            .russian: "Пускай, только если тот же код показан на экране той машины.",
            .english: "Let it in only if the same code is shown on that machine's screen.",
        ],
        "sync.approve": [.russian: "пустить", .english: "let in"],
        "sync.dismiss": [.russian: "отклонить", .english: "decline"],
        "sync.noStorage": [
            .russian: "Сервера-хранилища больше нет в списке хостов. Верни его или выключи синхронизацию "
                + "и выбери другой.",
            .english: "The storage server is no longer among your hosts. Bring it back, or turn sync off "
                + "and pick another.",
        ],
        "sync.err.unknownSigner": [
            .russian: "Снимок в хранилище подписала незнакомая машина (%@). Если её отзывали, она всё ещё "
                + "пишет в папку: закрой ей доступ к серверу.",
            .english: "The snapshot in storage was signed by an unknown machine (%@). If it was revoked, it "
                + "still writes to the folder: take away its access to the server.",
        ],
        "sync.err.badSignature": [
            .russian:
                "Подпись снимка в хранилище не сходится: файл меняли не через Phosphor. Ничего не применено.",
            .english: "The snapshot's signature does not match: the file was changed outside Phosphor. "
                + "Nothing was applied.",
        ],
        "sync.err.rollback": [
            .russian: "Хранилище вернуло старую версию (%@ после %@): файл подменили или восстановили из "
                + "резервной копии. Ничего не применено.",
            .english: "Storage returned an old version (%@ after %@): the file was swapped or restored from "
                + "a backup. Nothing was applied.",
        ],
        "sync.err.notForThisMachine": [
            .russian: "Эту машину отозвали с другой. Хосты здесь остались, новых правок не будет. Если это "
                + "ошибка — выключи синхронизацию и подключись заново.",
            .english: "This machine was revoked from another one. Hosts here stay, new edits will not come. "
                + "If that was a mistake, turn sync off and join again.",
        ],
        "sync.err.unreadable": [
            .russian:
                "Запись %@ не открывается: файл в хранилище повреждён или изменён. Ничего не применено.",
            .english:
                "Record %@ does not open: the file in storage is damaged or altered. Nothing was applied.",
        ],
        "sync.err.malformed": [
            .russian: "В хранилище не то, что ожидалось (%@). Возможно, на другой машине Phosphor новее — "
                + "обнови приложение.",
            .english: "Storage holds something unexpected (%@). Phosphor may be newer on another machine — "
                + "update the app.",
        ],
        "sync.err.keys": [
            .russian: "Ключи этой машины не работают: профиль перенесли с другого Мака или сбросили Secure "
                + "Enclave. Выключи синхронизацию и включи заново.",
            .english: "This machine's keys do not work: the profile was moved from another Mac, or the "
                + "Secure Enclave was reset. Turn sync off and on again.",
        ],
        "sync.err.busy": [
            .russian: "Другая машина пишет в хранилище прямо сейчас. Повторю после следующей правки — или "
                + "нажми «синхронизировать».",
            .english: "Another machine is writing to storage right now. It will retry after the next edit — "
                + "or press «sync now».",
        ],
        "sync.err.storage": [
            .russian: "Папка на сервере недоступна: %@. Проверь место на диске и права на ~/.phosphor-sync.",
            .english: "The folder on the server is not available: %@. Check disk space and permissions on "
                + "~/.phosphor-sync.",
        ],
    ]
}
