# Рецепты автонастройки · Provisioning recipes

[Русский](#русский) · [English](#english)

## Русский

Рецепт — это список шагов, которые Phosphor выполняет на сервере по одной
кнопке. Встроенные: **база** (пакеты, Docker, nginx, certbot, UFW, закрытие
паролей), **только Docker** и **мои ключи** (добавить выбранные ключи и, по
желанию, убрать все остальные).

Свой рецепт — это файл `.json`. Импорт: экран «Настройка» → **импорт…**.
Файлы лежат в `~/Library/Application Support/Phosphor/recipes`, по одному на
рецепт. Чужой рецепт никогда не запускается вслепую: кнопка открывает полный
список команд, и запуск — только оттуда.

```json
{
  "format": 1,
  "id": "node",
  "name": "Node.js 22 + pm2",
  "requires": { "os": ["linux"], "packageManager": ["apt"] },
  "steps": [
    { "title": "Node.js 22", "check": "command -v node",
      "commands": ["…", "…"] },
    { "title": "pm2", "asUser": true, "commands": ["npm install -g pm2"] }
  ]
}
```

| Поле | Что значит |
|---|---|
| `format` | Всегда `1`. Файл другого формата отклоняется. |
| `id` | Строчные латинские буквы, цифры, дефис; до 40 знаков. `base`, `docker`, `keys` заняты. |
| `name` | Как рецепт называется на экране, до 80 знаков. |
| `requires.os` | `linux`, `darwin`. Пусто — любая система. |
| `requires.packageManager` | `apt`, `dnf`, `brew`. Пусто — любой. |
| `steps[].title` | Название шага. |
| `steps[].commands` | Команды по порядку, от 1 до 50. Каждая — отдельный вызов, поэтому `export` в одной строке не действует на следующую. |
| `steps[].check` | Необязательно. Код выхода 0 — шаг уже сделан и пропускается. |
| `steps[].asUser` | `true` — от пользователя подключения. По умолчанию от root: не под root команды идут через `sudo -n`. |

Шагов от 1 до 40. Первая ошибка останавливает весь рецепт. Пример целиком:
[`recipes/node.json`](recipes/node.json).

Рецепт можно сделать рецептом группы — тогда для серверов группы он
выбирается по умолчанию.

## English

A recipe is a list of steps Phosphor runs on a server with one button.
Built in: **base** (packages, Docker, nginx, certbot, UFW, closing password
login), **Docker only** and **my keys** (add the chosen keys and, optionally,
remove every other one).

Your own recipe is a `.json` file. Import it from Setup → **import…**. Files
live in `~/Library/Application Support/Phosphor/recipes`, one per recipe.
Someone else's recipe never runs blind: the button opens the full list of
commands, and it runs only from there.

The format is the one shown above:

| Field | Meaning |
|---|---|
| `format` | Always `1`. Any other format is refused. |
| `id` | Lowercase letters, digits, hyphens; up to 40. `base`, `docker`, `keys` are taken. |
| `name` | The name on screen, up to 80 characters. |
| `requires.os` | `linux`, `darwin`. Empty means any system. |
| `requires.packageManager` | `apt`, `dnf`, `brew`. Empty means any. |
| `steps[].title` | The step's name. |
| `steps[].commands` | Commands in order, 1 to 50. Each is a separate call, so an `export` on one line does not reach the next. |
| `steps[].check` | Optional. Exit code 0 means the step is already done and is skipped. |
| `steps[].asUser` | `true` runs as the connecting user. Default is root: without root, commands go through `sudo -n`. |

1 to 40 steps. The first failure stops the whole recipe. A complete example:
[`recipes/node.json`](recipes/node.json).

A recipe can be made a group's recipe; servers in that group then get it
by default.
