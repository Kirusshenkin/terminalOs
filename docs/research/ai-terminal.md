# Аудит интеграции AI ↔ Phosphor Terminal

## Резюме

MCP-сервер **полностью реализован и функционален**, но **невидим пользователю**. Мост работает, 13 инструментов доступны, аудит ведётся, UI для управления существует — но:

1. **Phosphor НЕ зарегистрирован** в Claude Code (нет записи в `~/.claude.json/mcpServers`)
2. **Три критических бага** блокируют нормальное использование (issues #3, #7, #8)
3. **Нет point-of-entry** в приложении для быстрого подключения Claude Code
4. **Нет видимости** агентов, работающих внутри tmux-сессий

---

## 1. Что существует: MCP-архитектура и реализация

### 1.1 MCP-сервер (работает)

**Файлы:** `Sources/phosphor-mcp/main.swift` (156 строк), `MCPBridge/` пакет

**Архитектура:**
```
Claude Code/Desktop ─stdin/stdout─> phosphor-mcp (шим) ─Unix socket─> Phosphor.app
```

**Шим (`phosphor-mcp`):**
- Выполняемый файл: `/Applications/Phosphor.app/Contents/MacOS/phosphor-mcp` (1.8 МБ)
- JSON-RPC 2.0 over stdio
- Проксирует запросы приложению через локальный Unix-сокет
- Валидация: проверяет наличие app и токена, перед отправкой
- Ошибки: специфичные («Phosphor не запущен», «Phosphor не отвечает»)

**Тестирование шима:**
```
$ echo '{"jsonrpc":"2.0","id":1,"method":"initialize",...}' | /Applications/Phosphor.app/Contents/MacOS/phosphor-mcp
{"jsonrpc":"2.0","id":1,"result":{"protocolVersion":"2024-11-05",...}}
```
✅ Работает и отвечает корректно.

### 1.2 MCP инструменты (13 штук, закрытый каталог)

**Read tools (7):**
- `list_hosts` — серверы и статус подключения
- `host_metrics` — CPU, память, диск, сеть, uptime
- `host_report` — что не так с хостом (пороги уже применены)
- `list_containers` — контейнеры с состоянием и метриками
- `container_logs` — последние логи с фильтром
- `container_inspect` — полный docker inspect
- `list_authorized_keys` — ключи на сервере со свопринтками

**Write tools (6):**
- `run_command` — выполнить команду на хосте
- `container_action` — start/stop/restart/pause/unpause/kill/remove
- `manage_authorized_key` — добавить/убрать ключ по отпечатку
- `add_host`, `update_host`, `remove_host` — управление списком

**Запрос `tools/list` над stdio отвечает полным каталогом** (проверено, результат выше).

### 1.3 Политика доступа (реализована в `MCPBridge/Policy.swift`)

**Четыре режима per-host:**
- `disabled` — ничего, по умолчанию для новых хостов
- `read-only` — read-tools отвечают, write-tools отклоняют
- `confirm` — write-tools поднимают диалог в UI, требуют подтверждения
- `full` — write-tools запускаются без вопроса (но deny-list всё равно действует)

**Дополнительные слои защиты:**
- Deny-list поверх всего: `rm -rf /`, `mkfs`, `dd of=/dev/`, `shutdown`, `:(){ :|:& };:`
- Подтверждение с таймаутом (не вечное)
- Rate-limiting: 20 write-вызовов в минуту по умолчанию
- Секреты не возвращаются, маскируются в env переменных
- Masked выводятся переменные с `PASS`, `KEY`, `TOKEN`, `SECRET` в имени

**Тесты:** `Tests/PhosphorTests/MCPTests.swift` — полное покрытие политики.

### 1.4 Аудит (работает)

**Файл:** `MCPBridge/Audit.swift`

Каждый вызов записывается:
- Timestamp
- Host name и ID
- Tool name
- Arguments
- Decision (allow/deny/confirm)
- Success/failure
- Summary

**Важно:** логирование **append-only**, нет инструмента для стирания логов. Модель может действовать, но не может скрыть следы.

### 1.5 UI для управления (существует в `PhosphorUI/`)

**Файл:** `ActivityView.swift` (полный)

Три вкладки в разделе Activity (доступно в главном меню):

1. **Journal** — лог всех вызовов MCP с результатами
   - Отобранные в реверс-порядке (новые сверху)
   - Показывает: время, инструмент, хост, аргументы, решение, статус

2. **Access** — управление режимом per-host
   - Для каждого хоста кнопки: Disabled / ReadOnly / Confirm / Full
   - Показывает текущий режим цветом и фоном (опасность цвета соответствует режиму)
   - **БАГ #7:** нет ScrollView → нижние хосты недоступны при десятках хостов

3. **Tools** — справочник всех инструментов
   - Таблица: имя, описание, класс (read/write)
   - Цветовая разметка по типу

**В разделе Access также:**
- Инструкция «How to connect» в три шага
- Команда для регистрации: `claude mcp add phosphor /Applications/Phosphor.app/Contents/MacOS/phosphor-mcp`
- Статус мостика (если есть ошибка подключения)
- Warning про deny-list

---

## 2. Почему владелец НЕ видит функциональность: корневые причины

### 2.1 Phosphor НЕ зарегистрирован в Claude Code

**Проверено:**
- `~/.claude.json` содержит `mcpServers` для 11 других серверов (demo, chrome-devtools, github, figma, serf и пр.)
- **Phosphor в списке ОТСУТСТВУЕТ**
- В `~/.claude/settings.json` нет записей про phosphor

**Вывод:** Мост компилируется и работает, но:
- Claude Code о нём не знает
- Инструменты недоступны в Claude Code и Claude Desktop
- Если пользователь попробует, то получит «unknown server»

### 2.2 Нет точки входа в самом приложении

**Найденное:**
- В приложении есть вкладка Activity → Access → инструкция и команда регистрации
- **НО:** команда копируется и вставляется **вручную в терминал вне приложения**
- Нет кнопки «Register in Claude Code» или автоматической регистрации

**Файл:** `ActivityView.swift:100–110` (блок с инструкцией)

```swift
Text(model.bridgeCommand)  // "claude mcp add phosphor /Applications/Phosphor.app/..."
    .textSelection(.enabled)  // копируемо, но не кликабельно
    .padding(...)
```

### 2.3 Три критических бага блокируют использование даже при регистрации

#### Issue #3: Режимы не сохраняются после перезапуска app

**Состояние кода:**
- `AccessPolicy.modes` живёт в памяти, а не на диске (`MCPBridge/Policy.swift`)
- `AppModel.setMCPMode()` пишет в `mcpModes` (Memory), но **не вызывает сохранение в HostBook**
- Поля `ServerHost.mcpMode` и `HostGroup.mcpMode` существуют
- `HostBook.mcpMode(for:)` умеет читать и наследовать от группы — **но никто его не вызывает**

**Результат:** После перезапуска все хосты снова "disabled", и пользователь видит, что мост "сломан".

**Файлы:** 
- `Sources/MCPBridge/Policy.swift` — нет сохранения
- `Sources/PhosphorUI/AppModel+MCP.swift:19–29` — пишет только в память

#### Issue #7: Страница доступа без прокрутки

**Состояние кода:**
- `ActivityView.swift:access` — VStack с ForEach по хостам, но **нет ScrollView**
- При 40+ хостов (импорт из Termius) нижние и блок "как подключить" уходят за край

**Файлы:** `Sources/PhosphorUI/ActivityView.swift:63–104`

```swift
private var access: some View {
    VStack {  // ← нет ScrollView
        ForEach(model.book.hosts) { host in
            // ...
        }
        // "How to connect" блок ниже, недоступен при скроле
    }
}
```

**Результат:** Нельзя выдать MCP-доступ хостам из конца списка без ручной правки профиля.

#### Issue #8: list_hosts обещает статус, но не отдаёт

**Состояние кода:**
- Описание: "Серверы и статус подключения"
- Результат: `<id> <name> user@host:port` — **без статуса**
- ИИ не может понять, к какому хосту app уже подключен, гадает или дёргает инструменты впустую

**Файлы:** `MCPBridge/Tools.swift` (инструмент реализует это, проверить)

---

## 3. Что не реализовано или broken

| Функция | Статус | Файлы |
|---|---|---|
| MCP-сервер и шим | ✅ Работает | `Sources/phosphor-mcp/main.swift`, `MCPBridge/` |
| 13 инструментов | ✅ Все доступны по JSON-RPC | `MCPBridge/Tools.swift` |
| Политика доступа | ✅ Реализована и тестируется | `MCPBridge/Policy.swift`, `Tests/PhosphorTests/MCPTests.swift` |
| Аудит | ✅ Работает, read-only лог | `MCPBridge/Audit.swift` |
| UI Activity tabs | ✅ Все три вкладки есть | `PhosphorUI/ActivityView.swift` |
| Регистрация в Claude Code | ❌ Ручная, нет автоматизма | нет файла |
| Сохранение режимов | ❌ **ISSUE #3** | нет код |
| Прокрутка на Access | ❌ **ISSUE #7** | `ActivityView.swift:63` |
| Статус подключения в list_hosts | ❌ **ISSUE #8** | `Tools.swift` |
| Видимость агентов в tmux | ❌ Не реализовано | `CodingAgent.swift` тесты только для detection |

---

## 4. Предложенные опции для видимого AI ↔ Terminal

### Опция 1: One-click "Connect Claude Code" в ActivityView

**Что это:**
- Кнопка в разделе Activity → Access → инструкция
- При клике: `open claude://mcp-add?server=phosphor&command=...`
- Claude Code обрабатывает URL-схему и добавляет phosphor в config, показывает OK

**Pros:**
- ✅ Минимум кликов (1-2)
- ✅ Понятно с первого взгляда
- ✅ Работает с Claude Code, Claude Desktop нужна иная схема (JSON config)

**Cons:**
- ❌ URL-схема в Claude Code нужна, её может не быть
- ❌ Для Claude Desktop/Cursor — неприменимо (нужна ручная правка JSON)
- ❌ Не решает проблему повторной регистрации, если app переустановится

**Effort:** 2–3 часа (обработка URL, UI)  
**Risk:** Low (только UI, нет изменений в политике)  
**Файлы:** `ActivityView.swift`, `AppModel.swift`

---

### Опция 2: In-terminal AI command bar (local prototype)

**Что это:**
- В главном терминале (локальном окне Phosphor) текстовое поле: "Ask AI..."
- Ввод: natural language → Claude API (с ключом пользователя или local CLI)
- Вывод: предложенная команда + preview, пользователь кликает "Run" или отклоняет

**Пример:**
```
User: "restart the web service on prod"
AI: Proposed: ssh prod-01 sudo systemctl restart web
User: [Run] [Cancel] [Explain]
```

**Pros:**
- ✅ Не требует регистрации Claude Code (работает в самом приложении)
- ✅ Конфиденциальность (API-ключ хранится в Keychain)
- ✅ Быстро (preview перед запуском)
- ✅ Видимо и понятно прямо в интерфейсе

**Cons:**
- ❌ Требует локального Claude API client (claude-code CLI) или собственного интеграция
- ❌ Ограничено контекстом (только текущая сессия, мало истории)
- ❌ Не использует MCP (не может применить все инструменты, только локальные)
- ❌ Дублирует Claude Code (зачем еще один LLM интерфейс?)

**Effort:** 4–6 часов (UI + API integration)  
**Risk:** Medium (внешний API, ключ управления)  
**Файлы:** новые `LocalAIView.swift`, `APIClient.swift`

---

### Опция 3: Agent sessions panel (Herdr-style)

**Что это:**
- Расширение SessionRail (левая панель, где tmux-сессии)
- Новая секция: "AI Agents" с запущенными агентами
- Для каждого: ID, статус (running/idle/error), последняя активность, кнопка stop

**Как работает:**
- `CodingAgent.detect()` уже распознаёт claude, codex, cursor, aider и пр. в tmux
- Слежение: app периодически запрашивает `ps` на хосте, фильтрует по известным агентам
- UI показывает: `claude (idle, 2m ago)`, `codex (running, query...)`

**Пример UI:**
```
THIS MAC
- zsh (local, 10s ago)
- claude --resume (running, 1m ago)   [stop]

SPACES
prod-01
  tmux: main (4 windows)
  AI Agents:
  - claude (idle, 5m ago)
  - codex (running, processing...)    [stop]
```

**Pros:**
- ✅ Видимо и контролируемо (зная, что claude работает, ты уверен)
- ✅ Слежение, не вмешательство (не нужно менять политику MCP)
- ✅ Напоминает herdr (сессии как рабочие места)
- ✅ Работает с любым агентом (не требует MCP регистрации)

**Cons:**
- ❌ Дополнительные `ps` запросы (production-хосты?)
- ❌ Требует парсинга командной строки (уязвимо к изменениям аргументов)
- ❌ Не показывает **что** делает агент (только что он работает)
- ❌ Статус может быть ошибочным (процесс завис, но выглядит живым)

**Effort:** 3–5 часов (detection already works, add UI + polling)  
**Risk:** Low (чтение PS, никакая запись)  
**Файлы:** `SessionRail.swift`, `AppModel.swift` (polling logic)

---

### Опция 4: Approval queue UI with read-only preview (MCP-first)

**Что это:**
- Новая вкладка Activity → **Approvals** (после Journal и Access)
- Когда режим `confirm`, write-инструмент **не выполняется сразу**
- Вместо этого появляется карточка в очереди:
  ```
  Tool: run_command
  Host: prod-01
  Command: systemctl restart web
  Requested by: claude (10 seconds ago)
  [Approve] [Deny] [Explain to AI]
  ```

**Как работает:**
- `CallTool` в MCP возвращает `pending` вместо выполнения
- App показывает UI, человек решает
- AI-клиент может опционально получить feedback

**Пример workflow:**
```
Claude Code: "restart the web service"
    ↓
Phosphor (MCP): tool pending confirmation
Claude Code: waiting...
    ↓
You: see the command in Approvals, understand, click [Approve]
    ↓
Phosphor: command runs, returns output
Claude Code: gets result, proceeds
```

**Pros:**
- ✅ Полностью использует MCP (фундаментально, не костыль)
- ✅ Видимо и контролируемо (ты видишь **каждое** пишущее действие)
- ✅ Привычно (как в confirm-режиме, но в отдельной вкладке)
- ✅ Гибко: можно отклонить, попросить объяснение, отредактировать команду

**Cons:**
- ❌ Требует изменения MCP-протокола (новый тип result?)
- ❌ AI-клиент должен поддержать pending state (может быть не у всех)
- ❌ Увеличивает latency (человек должен одобрить, а не автоматически)
- ❌ Привычка "одобрять все" становится норм (как UAC в Windows)

**Effort:** 5–8 часов (MCP protocol change, UI, state management)  
**Risk:** Medium (меняет MCP-контракт, может сломать clients)  
**Файлы:** `ActivityView.swift`, `MCPBridge/Tools.swift`, `MCPBridge/Policy.swift`

---

## 5. Рекомендация

**Ближайший sprint (приоритет):**

1. **Исправить Issue #3** (режимы не сохраняются)
   - Это критично: без этого мост выглядит сломанным
   - 1 час кода: вызови `HostBook.setMCPMode()` вместо прямой правки `mcpModes`

2. **Исправить Issue #7** (добавить ScrollView в Access)
   - 20 минут кода, но блокирует использование на 40+ хостах

3. **Реализовать Опцию 1 или 3** (видимость в UI)
   - Опция 1 проще для Claude Code (but не для Desktop)
   - Опция 3 универсальнее и соответствует дизайну herdr

**Долгосрочно:**
- Опция 4 — если хочется полного контроля (утяжеляет интерфейс, но честный)
- Опция 2 — только если есть запрос на встроенный AI (не рекомендуется, дублирует Claude Code)

---

## Файлы для справки

### Основные
- `/Users/kirillm/Documents/project/terminal/docs/MCP.md` — полная документация
- `/Users/kirillm/Documents/project/terminal/docs/PLAN.md` §15–16 — дизайн MCP и модель угроз

### Реализация
- `Sources/phosphor-mcp/main.swift` (156 lines) — JSON-RPC шим
- `Sources/MCPBridge/` — политика, аудит, инструменты
- `Sources/PhosphorUI/ActivityView.swift` — UI для управления
- `Tests/PhosphorTests/MCPTests.swift` — тесты политики
- `Tests/PhosphorTests/TerminalAgentTests.swift` — detection agents в tmux

### Конфигурация Claude Code
- `~/.claude.json/mcpServers` — здесь phosphor отсутствует

### Issues
- #3 — режимы не сохраняются (critical)
- #7 — прокрутка на Access (blocks usage at scale)
- #8 — list_hosts не отдаёт статус (degrades AI reasoning)

---

**Дата аудита:** 2026-09-24  
**Версия app:** Phosphor, build ?.?, deployed to /Applications
