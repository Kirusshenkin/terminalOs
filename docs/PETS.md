# Свои питомцы · Custom pets

[Русский](#русский) · [English](#english)

## Русский

В углу рейла живёт питомец: котёнок, поссум или свой. Он стоит, гуляет
туда-обратно и спит, пока ты работаешь (ввод или вывод в терминале за
последние 20 секунд).

Свой питомец — это `.json` с сетками символов. Цветов в файле нет: каждый
символ — роль, а цвет даёт тема, поэтому питомец смотрится в любой теме.

| Символ | Роль |
|---|---|
| `.` | пусто |
| `b` | тело |
| `r` | контур |
| `e` | глаз |
| `s` | полоса |
| `n` | нос |

```json
{
  "format": 1,
  "id": "fox",
  "name": "Лиса",
  "states": {
    "idle":  { "frameMs": 600,  "frames": [ ["....r...r...", "...rbr.rbr.."], ["…"] ] },
    "walk":  { "frameMs": 125,  "frames": [ ["…"], ["…"] ] },
    "sleep": { "frameMs": 1200, "frames": [ ["…"] ] },
    "blink": { "frames": [ ["…"] ] }
  }
}
```

Полный пример — [`docs/pets/fox.json`](pets/fox.json).

| Поле | Правило |
|---|---|
| `format` | `1` |
| `id` | Строчные латинские буквы, цифры, дефис; до 40 знаков. `cat` и `glider` заняты. |
| `name` | 1–40 знаков, как питомец подписан в настройках. |
| `states` | Обязательны `idle`, `walk`, `sleep`. Необязательно `blink` — проигрывается поверх `idle` раз в три секунды. Других нет. |
| `frames` | 1–8 кадров. Кадр — список строк одной длины, до 32×32 символов. |
| `frameMs` | 60–2000. По умолчанию: `idle` 500, `walk` 125, `sleep` 1000, `blink` 150. |

Рисуй лицом вправо: влево приложение отразит само. Нижняя строка кадра
стоит на полу. Файл — до 64 КБ.

**Как добавить.** Настройки → Поведение → питомец → **импорт…**. Файл
проверяется и копируется в `~/Library/Application Support/Phosphor/pets`.
Удалить — правый клик по имени. Сломанный файл в папке не прячет остальных:
под списком написано, что с ним не так.

**Через MCP.** `list_pets`, `add_pet` (аргумент `pet` — JSON целиком),
`remove_pet`. Добавление и удаление каждый раз подтверждаешь ты. Ошибка
называет состояние и номер кадра, так что агент может поправить именно его.

## English

The rail's corner has a pet: a cat, a sugar glider or your own. It stands,
walks there and back, and sleeps while you work (terminal input or output in
the last 20 seconds).

Your own pet is a `.json` of character grids. The file has no colours: each
character is a role and the theme paints it, so the pet fits any theme.

| Character | Role |
|---|---|
| `.` | empty |
| `b` | body |
| `r` | rim |
| `e` | eye |
| `s` | stripe |
| `n` | nose |

See the example above and [`docs/pets/fox.json`](pets/fox.json).

| Field | Rule |
|---|---|
| `format` | `1` |
| `id` | Lowercase letters, digits, hyphens; up to 40. `cat` and `glider` are taken. |
| `name` | 1–40 characters, shown in Settings. |
| `states` | `idle`, `walk`, `sleep` are required. `blink` is optional and plays over `idle` every three seconds. Nothing else. |
| `frames` | 1–8 frames. A frame is a list of equally long rows, up to 32×32. |
| `frameMs` | 60–2000. Defaults: `idle` 500, `walk` 125, `sleep` 1000, `blink` 150. |

Draw facing right; the app mirrors it to walk left. The bottom row stands on
the floor. Files are up to 64 KB.

**Adding.** Settings → Behaviour → pet → **import…**. The file is checked and
copied to `~/Library/Application Support/Phosphor/pets`. Right-click a name to
delete it. A broken file does not hide the others: the reason is shown below
the list.

**Through MCP.** `list_pets`, `add_pet` (argument `pet` is the whole JSON),
`remove_pet`. You confirm every addition and removal. Errors name the state and
frame number, so an agent can fix exactly that part.
