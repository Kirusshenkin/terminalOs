import Foundation

/// Подписи автонастройки: рецепты, их файлы, ключи. Отдельная таблица —
/// у двух других свой потолок длины.
extension Strings {
    static let recipeTable: [String: [Language: String]] = [
        "recipe.name.base": [.russian: "база", .english: "base"],
        "recipe.name.docker": [.russian: "только Docker", .english: "Docker only"],
        "recipe.name.keys": [.russian: "мои ключи", .english: "my keys"],
        "recipe.keys.add": [.russian: "добавить выбранные ключи", .english: "add the chosen keys"],
        "recipe.keys.prune": [.russian: "убрать все остальные ключи", .english: "remove every other key"],
        "recipe.alreadyDone": [.russian: "уже сделано", .english: "already done"],
        "recipe.noKeysChosen": [.russian: "ключи не выбраны", .english: "no keys chosen"],
        "recipe.wouldLockOut": [
            .russian: "ключа этого подключения нет среди выбранных — иначе отрежешь себя",
            .english: "this connection's key is not among the chosen — you would cut yourself off",
        ],
        "recipe.needsRoot": [
            .russian: "нужен root или sudo без пароля", .english: "needs root or passwordless sudo",
        ],
        "prov.chooseRecipe": [.russian: "рецепт", .english: "recipe"],
        "prov.notForOS": [.russian: "не для этой системы", .english: "not for this system"],
        "prov.fromFile": [.russian: "из файла", .english: "from a file"],
        "prov.import": [.russian: "импорт…", .english: "import…"],
        "prov.deleteRecipe": [.russian: "удалить рецепт", .english: "delete recipe"],
        "prov.imported": [.russian: "рецепт добавлен: ", .english: "recipe added: "],
        "prov.foreign": [
            .russian: "чужой рецепт: перед запуском прочитай все команды — их написал не Phosphor",
            .english:
                "someone else's recipe: read every command before running — Phosphor did not write them",
        ],
        "prov.runAfterReading": [.russian: "прочитал, запустить", .english: "read it, run"],
        "prov.check": [.russian: "проверка", .english: "check"],
        "prov.asUser": [.russian: "от пользователя", .english: "as the user"],
        "prov.keysToAdd": [.russian: "какие ключи добавить", .english: "keys to add"],
        "prov.removeOthers": [.russian: "убрать все остальные ключи", .english: "remove every other key"],
        "prov.groupRecipe": [.russian: "рецепт группы «%@»", .english: "recipe of group “%@”"],
        "prov.makeGroupRecipe": [
            .russian: "сделать рецептом группы", .english: "make it the group's recipe",
        ],
        "prov.brokenFiles": [.russian: "не прочитаны:", .english: "not read:"],
        "rf.tooLarge": [
            .russian: "файл больше 256 КБ — это не рецепт",
            .english: "the file is over 256 KB — not a recipe",
        ],
        "rf.notJSON": [.russian: "это не JSON рецепта: %@", .english: "this is not recipe JSON: %@"],
        "rf.format": [
            .russian: "формат %@ не поддерживается — нужен \"format\": 1",
            .english: "format %@ is not supported — use \"format\": 1",
        ],
        "rf.badID": [
            .russian: "id «%@» не годится: строчные латинские буквы, цифры и дефис, до 40 знаков",
            .english: "id “%@” is not valid: lowercase letters, digits and hyphens, up to 40",
        ],
        "rf.reservedID": [
            .russian: "id «%@» занят встроенным рецептом — выбери другой",
            .english: "id “%@” belongs to a built-in recipe — pick another",
        ],
        "rf.badName": [
            .russian: "у рецепта нет имени или оно длиннее 80 знаков",
            .english: "the recipe has no name or it is over 80 characters",
        ],
        "rf.stepCount": [
            .russian: "шагов %@ — нужно от 1 до 40", .english: "%@ steps — there must be 1 to 40",
        ],
        "rf.unknownOS": [
            .russian: "система «%@» неизвестна — допустимо linux или darwin",
            .english: "system “%@” is unknown — use linux or darwin",
        ],
        "rf.unknownPM": [
            .russian: "пакетный менеджер «%@» неизвестен — допустимо apt, dnf или brew",
            .english: "package manager “%@” is unknown — use apt, dnf or brew",
        ],
        "rf.badStepTitle": [
            .russian: "у шага %@ нет названия или оно длиннее 80 знаков",
            .english: "step %@ has no title or it is over 80 characters",
        ],
        "rf.commandCount": [
            .russian: "в шаге %@ должно быть от 1 до 50 команд",
            .english: "step %@ must have 1 to 50 commands",
        ],
        "rf.badCommand": [
            .russian: "в шаге %@ пустая или слишком длинная команда",
            .english: "step %@ has an empty or overly long command",
        ],
        "rf.exists": [
            .russian: "рецепт «%@» уже есть — удали его, чтобы заменить",
            .english: "recipe “%@” already exists — delete it to replace it",
        ],
        "rf.cannotRead": [.russian: "файл не читается: %@", .english: "cannot read the file: %@"],
        "rf.cannotWrite": [
            .russian: "не удалось сохранить рецепт: %@", .english: "could not save the recipe: %@",
        ],
    ]
}
