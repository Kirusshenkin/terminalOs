import Foundation

/// Подписи питомцев: выбор, импорт и разбор файлов своих питомцев.
extension Strings {
    static let petTable: [String: [Language: String]] = [
        "pet.cat": [.russian: "котёнок", .english: "cat"],
        "pet.glider": [.russian: "поссум", .english: "glider"],
        "pet.import": [.russian: "импорт…", .english: "import…"],
        "pet.delete": [.russian: "удалить питомца", .english: "delete pet"],
        "pet.imported": [.russian: "добавлен питомец: %@", .english: "pet added: %@"],
        "pet.fromFile": [.russian: "свой питомец из файла", .english: "your own pet, from a file"],
        "pet.howTo": [
            .russian: "Своего питомца можно нарисовать сеткой символов — формат в docs/PETS.md.",
            .english: "You can draw your own pet as a grid of characters — the format is in docs/PETS.md.",
        ],
        "pet.brokenFiles": [
            .russian: "Эти файлы в папке питомцев не прочитаны:",
            .english: "These files in the pets folder were not read:",
        ],
        "foot.petAsleep": [.russian: "%@ спит", .english: "%@ is asleep"],
        "pf.tooLarge": [
            .russian: "файл больше 64 КБ — питомец столько не весит",
            .english: "the file is over 64 KB — a pet is never that big",
        ],
        "pf.notJSON": [.russian: "это не JSON питомца: %@", .english: "this is not pet JSON: %@"],
        "pf.format": [
            .russian: "формат %@ не поддерживается, нужен 1",
            .english: "format %@ is not supported, use 1",
        ],
        "pf.badID": [
            .russian: "id «%@»: строчные латинские буквы, цифры и дефис, до 40 знаков",
            .english: "id «%@»: lowercase latin letters, digits and hyphens, up to 40",
        ],
        "pf.reservedID": [
            .russian: "id «%@» занят встроенным питомцем — выбери другой",
            .english: "id «%@» belongs to a built-in pet — pick another",
        ],
        "pf.badName": [.russian: "имя — от 1 до 40 знаков", .english: "the name must be 1–40 characters"],
        "pf.missingState": [
            .russian: "нет состояния «%@»: обязательны idle, walk и sleep",
            .english: "state «%@» is missing: idle, walk and sleep are required",
        ],
        "pf.unknownState": [
            .russian: "неизвестное состояние «%@»: бывают idle, walk, sleep, blink",
            .english: "unknown state «%@»: use idle, walk, sleep, blink",
        ],
        "pf.frameCount": [
            .russian: "у состояния «%@» должно быть от 1 до 8 кадров",
            .english: "state «%@» needs 1 to 8 frames",
        ],
        "pf.frameSize": [
            .russian: "кадр «%@» больше 32×32 — уменьши рисунок",
            .english: "frame «%@» is larger than 32×32 — draw it smaller",
        ],
        "pf.ragged": [
            .russian: "кадр «%@»: все строки должны быть одной длины",
            .english: "frame «%@»: every row must be the same length",
        ],
        "pf.unknownInk": [
            .russian: "кадр «%@»: непонятный символ — бывают . b r e s n",
            .english: "frame «%@»: unknown character — use . b r e s n",
        ],
        "pf.badDuration": [
            .russian: "у состояния «%@» frameMs должен быть от 60 до 2000",
            .english: "state «%@»: frameMs must be 60 to 2000",
        ],
        "pf.exists": [
            .russian: "питомец «%@» уже есть — сначала удали его",
            .english: "pet «%@» already exists — delete it first",
        ],
        "pf.notFound": [.russian: "своего питомца «%@» нет", .english: "there is no custom pet «%@»"],
        "pf.cannotRead": [.russian: "файл не читается: %@", .english: "cannot read the file: %@"],
        "pf.cannotWrite": [
            .russian: "не удалось записать в папку питомцев: %@",
            .english: "could not write to the pets folder: %@",
        ],
    ]
}
